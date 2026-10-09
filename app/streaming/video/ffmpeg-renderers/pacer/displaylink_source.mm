// Avoid conflict between AVFoundation and
// libavutil both defining AVMediaType
#define AVMediaType AVMediaType_FFmpeg
#include "displaylink_source.h"
#undef AVMediaType

#include <SDL_syswm.h>

#include <mach/mach_time.h>

#import <Cocoa/Cocoa.h>
#import <CoreVideo/CoreVideo.h>
#import <QuartzCore/CADisplayLink.h>

static double hostTimeToSeconds(uint64_t hostTime)
{
    // CVTimeStamp.hostTime is mach_absolute_time. CADisplayLink.timestamp is
    // that same clock in seconds (CACurrentMediaTime). FramePacer compares
    // the seconds against SDL_GetPerformanceCounter, which is also mach time.
    static mach_timebase_info_data_t info;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        mach_timebase_info(&info);
    });
    if (info.denom == 0) {
        return 0.0;
    }
    const long double nanos = static_cast<long double>(hostTime) *
                              static_cast<long double>(info.numer) /
                              static_cast<long double>(info.denom);
    return static_cast<double>(nanos / 1000000000.0L);
}

@interface DisplayLinkTarget : NSObject
{
    DisplayLinkSource* _source;
    CADisplayLink* _displayLink API_AVAILABLE(macos(14.0));
    CVDisplayLinkRef _cvLink;
    double _lastTimestamp;
    int _fps;
}

- (instancetype)initWithSource:(DisplayLinkSource*)source
                     forWindow:(NSWindow*)nswindow
                           fps:(int)fps;
- (BOOL)startCADisplayLinkForWindow:(NSWindow*)window fps:(int)fps API_AVAILABLE(macos(14.0));
- (BOOL)startCVDisplayLinkForWindow:(NSWindow*)window;
- (void)link:(CADisplayLink *)update API_AVAILABLE(macos(14.0));
- (void)handleCVOutput:(const CVTimeStamp *)outputTime;
- (void)stopCADisplayLink API_AVAILABLE(macos(14.0));
- (void)stop;

@end

static CVReturn cvDisplayLinkCallback(CVDisplayLinkRef displayLink,
                                      const CVTimeStamp* now,
                                      const CVTimeStamp* outputTime,
                                      CVOptionFlags flagsIn,
                                      CVOptionFlags* flagsOut,
                                      void* context)
{
    (void)displayLink;
    (void)now;
    (void)flagsIn;
    (void)flagsOut;
    DisplayLinkTarget* target = (DisplayLinkTarget*)context;
    if (target != nil) {
        [target handleCVOutput:outputTime];
    }
    return kCVReturnSuccess;
}

DisplayLinkSource::DisplayLinkSource()
    : m_DisplayLinkTarget(nullptr),
      m_TargetTimestamp(0.0)
{
}

DisplayLinkSource::~DisplayLinkSource()
{
    stop();
}

bool DisplayLinkSource::initialize(SDL_Window* window, int fps)
{
    stop();

    SDL_SysWMinfo info;
    SDL_VERSION(&info.version);
    if (!SDL_GetWindowWMInfo(window, &info)) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                     "DisplayLinkSource: SDL_GetWindowWMInfo() failed: %s",
                     SDL_GetError());
        return false;
    }

    NSWindow* nswindow = (__bridge NSWindow *)info.info.cocoa.window;
    if (!nswindow) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                     "DisplayLinkSource: Cocoa window is null");
        return false;
    }

    DisplayLinkTarget* target =
        [[DisplayLinkTarget alloc] initWithSource:this
                                        forWindow:nswindow
                                              fps:fps];
    if (!target) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                     "DisplayLinkSource: error creating DisplayLink");
        return false;
    }

    m_DisplayLinkTarget = target;
    m_TargetTimestamp.store(0.0);

    return true;
}

void DisplayLinkSource::stop()
{
    m_TargetTimestamp.store(0.0);

    DisplayLinkTarget* target = (DisplayLinkTarget*)m_DisplayLinkTarget;
    if (target) {
        [target stop];
        [target release];
        m_DisplayLinkTarget = nullptr;
    }
}

bool DisplayLinkSource::isAsync()
{
    return true;
}

void DisplayLinkSource::displayLinkUpdate(double timestamp, double targetTimestamp)
{
    std::lock_guard<std::mutex> lock(m_mtx);
    m_TargetTimestamp.store(targetTimestamp);
    FramePacer::instance().signalVsyncTS(timestamp, targetTimestamp);
}

///////

@implementation DisplayLinkTarget

- (instancetype)initWithSource:(DisplayLinkSource*)source
                     forWindow:(NSWindow*)window
                            fps:(int)fps
{
    self = [super init];
    if (self) {
        _source = source;
        _cvLink = nullptr;
        _lastTimestamp = 0.0;
        _fps = fps;
        BOOL started = NO;
        if (@available(macOS 14.0, *)) {
            started = [self startCADisplayLinkForWindow:window fps:fps];
            if (started) {
                SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                            "Frame pacing: CADisplayLink");
            }
            else {
                SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                            "Frame pacing: CADisplayLink failed; trying CVDisplayLink");
            }
        }
        if (!started) {
            started = [self startCVDisplayLinkForWindow:window];
            if (started) {
                SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                            "Frame pacing: CVDisplayLink");
            }
        }
        if (!started) {
            [self release];
            return nil;
        }
    }
    return self;
}

- (BOOL)startCADisplayLinkForWindow:(NSWindow*)window fps:(int)fps API_AVAILABLE(macos(14.0))
{
    _displayLink = [window displayLinkWithTarget:self
                                        selector:@selector(link:)];
    if (!_displayLink) {
        return NO;
    }

    _displayLink.preferredFrameRateRange = CAFrameRateRangeMake(fps, fps, fps);
    [_displayLink addToRunLoop:[NSRunLoop mainRunLoop]
                       forMode:NSRunLoopCommonModes];
    return YES;
}

- (BOOL)startCVDisplayLinkForWindow:(NSWindow*)window
{
    NSScreen* screen = window.screen;
    CVReturn status;
    if (screen == nil) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "DisplayLinkSource: NSWindow is not visible on any display");
        status = CVDisplayLinkCreateWithActiveCGDisplays(&_cvLink);
    }
    else {
        CGDirectDisplayID displayId = [[screen deviceDescription][@"NSScreenNumber"] unsignedIntValue];
        status = CVDisplayLinkCreateWithCGDisplay(displayId, &_cvLink);
    }
    if (status != kCVReturnSuccess || _cvLink == nullptr) {
        _cvLink = nullptr;
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                     "DisplayLinkSource: CVDisplayLinkCreate failed: %d",
                     status);
        return NO;
    }

    status = CVDisplayLinkSetOutputCallback(_cvLink, cvDisplayLinkCallback, self);
    if (status != kCVReturnSuccess) {
        CVDisplayLinkRelease(_cvLink);
        _cvLink = nullptr;
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                     "DisplayLinkSource: CVDisplayLinkSetOutputCallback failed: %d",
                     status);
        return NO;
    }

    status = CVDisplayLinkStart(_cvLink);
    if (status != kCVReturnSuccess) {
        CVDisplayLinkRelease(_cvLink);
        _cvLink = nullptr;
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                     "DisplayLinkSource: CVDisplayLinkStart failed: %d",
                     status);
        return NO;
    }
    return YES;
}

- (void)link:(CADisplayLink*)update API_AVAILABLE(macos(14.0))
{
    DisplayLinkSource* source = _source;
    if (source) {
        source->displayLinkUpdate((double)update.timestamp, (double)update.targetTimestamp);
    }
}

- (void)handleCVOutput:(const CVTimeStamp*)outputTime
{
    if (outputTime == nullptr || (outputTime->flags & kCVTimeStampHostTimeValid) == 0) {
        return;
    }

    const double target = hostTimeToSeconds(outputTime->hostTime);
    double timestamp = _lastTimestamp;
    if (!(timestamp > 0.0) || timestamp >= target) {
        // inOutputTime - inNow is the wait until this vsync, not one refresh.
        // The pacer wants deadline - timestamp to be one frame.
        double period = _fps > 0 ? (1.0 / static_cast<double>(_fps)) : (1.0 / 60.0);
        if (_cvLink != nullptr) {
            const CVTime nominal = CVDisplayLinkGetNominalOutputVideoRefreshPeriod(_cvLink);
            if (nominal.timeScale > 0 && nominal.timeValue > 0) {
                period = static_cast<double>(nominal.timeValue) / static_cast<double>(nominal.timeScale);
            }
        }
        timestamp = target - period;
    }
    _lastTimestamp = target;

    DisplayLinkSource* source = _source;
    if (source) {
        source->displayLinkUpdate(timestamp, target);
    }
}

- (void)stopCADisplayLink API_AVAILABLE(macos(14.0))
{
    if (_displayLink) {
        [_displayLink invalidate];
        _displayLink = nil;
    }
}

- (void)stop
{
    _source = nullptr;

    if (@available(macOS 14.0, *)) {
        [self stopCADisplayLink];
    }
    if (_cvLink != nullptr) {
        CVDisplayLinkStop(_cvLink);
        CVDisplayLinkRelease(_cvLink);
        _cvLink = nullptr;
    }
}

- (void)dealloc
{
    [self stop];
    [super dealloc];
}

@end
