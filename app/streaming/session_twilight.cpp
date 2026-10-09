#include "session.h"
#include "gui/overlay_toggle.h"
#include "gui/streamhudstats.h"

#ifdef Q_OS_DARWIN
#include "streaming/mac/pip_frame.h"
#include "streaming/mac/pip_window.h"
#endif

#include <QString>

#ifdef Q_OS_DARWIN

void Session::releaseVideoDecoder()
{
    // Same teardown as toggleFullscreen(). On Apple Silicon the
    // AVSampleBufferDisplayLayer path can deadlock WindowServer if the
    // decoder is alive across a fullscreen transition (moonlight-qt #973).
    SDL_LockMutex(m_DecoderLock);
    delete m_VideoDecoder;
    m_VideoDecoder = nullptr;
    SDL_UnlockMutex(m_DecoderLock);
}

static bool usableBoundsForPictureInPicture(SDL_Window* window, SDL_Rect* bounds)
{
    int displayIndex = SDL_GetWindowDisplayIndex(window);
    if (displayIndex < 0) {
        displayIndex = 0;
    }
    if (SDL_GetDisplayUsableBounds(displayIndex, bounds) == 0) {
        return true;
    }
    SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                "SDL_GetDisplayUsableBounds() failed: %s",
                SDL_GetError());
    return SDL_GetDisplayBounds(displayIndex, bounds) == 0;
}

// Holds the Twilight HUD off the stream window while PiP changes level,
// collection behavior, fullscreen, or frame. AppKit child windows are not
// safe across those calls. A follow or raise requested while this is live
// is applied from the destructor, after the parent has no child.
struct PipHudMutationGuard
{
    PipHudMutationGuard()
    {
        StreamHudStats::beginStreamWindowMutation();
    }

    ~PipHudMutationGuard()
    {
        StreamHudStats::endStreamWindowMutation();
    }
};

bool Session::displayCoversWindow(int width, int height) const
{
    int displayIndex = SDL_GetWindowDisplayIndex(m_Window);
    SDL_Rect bounds;
    if (displayIndex < 0 || SDL_GetDisplayBounds(displayIndex, &bounds) != 0) {
        return false;
    }
    return width >= bounds.w - 2 && height >= bounds.h - 2;
}

void Session::reapplyPictureInPictureChrome(bool orderFront)
{
    if (!m_PipActive || m_Window == nullptr || m_PipReapplying) {
        return;
    }
    m_PipReapplying = true;

    {
        PipHudMutationGuard hudDetached;

        if (m_PipSnapBackUntil != 0 && SDL_TICKS_PASSED(SDL_GetTicks(), m_PipSnapBackUntil)) {
            m_PipSnapBackUntil = 0;
        }

        if (m_PipSnapBackUntil != 0 && m_PipFrameW > 0 && m_PipFrameH > 0) {
            int width = 0;
            int height = 0;
            SDL_GetWindowSize(m_Window, &width, &height);
            const bool fullscreen = (SDL_GetWindowFlags(m_Window) & SDL_WINDOW_FULLSCREEN) != 0;
            if (fullscreen || displayCoversWindow(width, height)) {
                if (fullscreen) {
                    SDL_SetWindowFullscreen(m_Window, 0);
                }
#if SDL_VERSION_ATLEAST(2, 0, 5)
                SDL_SetWindowBordered(m_Window, SDL_TRUE);
#endif
                SDL_SetWindowSize(m_Window, m_PipFrameW, m_PipFrameH);
                SDL_SetWindowPosition(m_Window, m_PipFrameX, m_PipFrameY);
            }
        }

        // Floating chrome first, then SDL's always-on-top flag. The flag setter
        // only changes the level; doing it first would let the snapshot below
        // record NSFloatingWindowLevel as the window's original level.
        MacPipApplyFloating(m_Window, orderFront);
#if SDL_VERSION_ATLEAST(2, 0, 5)
        SDL_SetWindowAlwaysOnTop(m_Window, SDL_TRUE);
#endif
    }
    if (orderFront) {
        StreamHudStats::orderFront();
    }
    else {
        StreamHudStats::followStream();
    }
    m_PipReapplying = false;
}

void Session::enterPictureInPicture()
{
    if (m_Window == nullptr || m_PipActive) {
        return;
    }

    const int videoW = m_ActiveVideoWidth > 0 ? m_ActiveVideoWidth : m_StreamConfig.width;
    const int videoH = m_ActiveVideoHeight > 0 ? m_ActiveVideoHeight : m_StreamConfig.height;

    SDL_Rect usable;
    if (!usableBoundsForPictureInPicture(m_Window, &usable)) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                     "Picture-in-picture could not read the display bounds");
        return;
    }

    const PipFrame frame = suggestPictureInPictureFrame(
        {usable.x, usable.y, usable.w, usable.h}, videoW, videoH);
    if (frame.w <= 0 || frame.h <= 0) {
        SDL_LogError(SDL_LOG_CATEGORY_APPLICATION,
                     "Picture-in-picture frame was empty");
        return;
    }

    {
        PipHudMutationGuard hudDetached;

        const bool wasFullscreen = (SDL_GetWindowFlags(m_Window) & m_FullScreenFlag) != 0;
        m_PipRestoreFullscreen = wasFullscreen;
        if (!wasFullscreen) {
            SDL_GetWindowPosition(m_Window, &m_PipRestoreX, &m_PipRestoreY);
            SDL_GetWindowSize(m_Window, &m_PipRestoreW, &m_PipRestoreH);
        }
        else {
            // The live fullscreen size is not the window to restore. This is
            // the same windowed rect the session uses at startup.
            getWindowDimensions(m_PipRestoreX, m_PipRestoreY, m_PipRestoreW, m_PipRestoreH);
            releaseVideoDecoder();
            SDL_SetWindowFullscreen(m_Window, 0);
        }

        const char* currentTitle = SDL_GetWindowTitle(m_Window);
        m_PipRestoreTitle = QString::fromUtf8(currentTitle != nullptr ? currentTitle : "");
        m_PipFrameX = frame.x;
        m_PipFrameY = frame.y;
        m_PipFrameW = frame.w;
        m_PipFrameH = frame.h;
        // macOS fullscreen Spaces animate out. Keep correcting a display-sized
        // window for a bit longer than that animation.
        m_PipSnapBackUntil = wasFullscreen ? SDL_GetTicks() + 1500 : 0;

        // Snapshot the current level before raising it. Fullscreen has already
        // been left, so this is the windowed chrome SDL restored.
        MacPipApplyFloating(m_Window, false);
#if SDL_VERSION_ATLEAST(2, 0, 5)
        SDL_SetWindowBordered(m_Window, SDL_TRUE);
#endif
        SDL_SetWindowMinimumSize(m_Window, 160, 90);
        SDL_SetWindowSize(m_Window, frame.w, frame.h);
        SDL_SetWindowPosition(m_Window, frame.x, frame.y);
        MacPipApplyFloating(m_Window, true);
#if SDL_VERSION_ATLEAST(2, 0, 5)
        SDL_SetWindowAlwaysOnTop(m_Window, SDL_TRUE);
#endif

        const QString pipTitle = m_PipRestoreTitle + QStringLiteral(" - Picture in Picture");
        SDL_SetWindowTitle(m_Window, pipTitle.toUtf8().constData());
    }

    m_PipActive = true;
    MacPipUpdateMenu(true);

    // Leave the cursor free so the mini player can sit beside another app.
    // A click in the video captures again, same as a windowed stream.
    if (m_InputHandler != nullptr) {
        m_InputHandler->setCaptureActive(false);
    }

    StreamHudStats::orderFront();

    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                "Entered picture-in-picture at %d,%d %dx%d",
                frame.x, frame.y, frame.w, frame.h);
}

void Session::exitPictureInPicture()
{
    if (m_Window == nullptr || !m_PipActive) {
        return;
    }

    const bool restoreFullscreen = m_PipRestoreFullscreen;
    m_PipActive = false;
    m_PipSnapBackUntil = 0;
    m_PipRestoreFullscreen = false;
    MacPipUpdateMenu(false);

    {
        PipHudMutationGuard hudDetached;

#if SDL_VERSION_ATLEAST(2, 0, 5)
        SDL_SetWindowAlwaysOnTop(m_Window, SDL_FALSE);
#endif
        MacPipClearFloating(m_Window);
        SDL_SetWindowMinimumSize(m_Window, 0, 0);

        if (!m_PipRestoreTitle.isNull()) {
            SDL_SetWindowTitle(m_Window, m_PipRestoreTitle.toUtf8().constData());
            m_PipRestoreTitle.clear();
        }

        if (m_PipRestoreW > 0 && m_PipRestoreH > 0) {
            SDL_SetWindowSize(m_Window, m_PipRestoreW, m_PipRestoreH);
            SDL_SetWindowPosition(m_Window, m_PipRestoreX, m_PipRestoreY);
        }

        if (restoreFullscreen) {
            releaseVideoDecoder();
            SDL_SetWindowFullscreen(m_Window, m_FullScreenFlag);
        }
    }

    if (m_InputHandler != nullptr) {
        m_InputHandler->updateKeyboardGrabState();
        m_InputHandler->updatePointerRegionLock();
    }

    StreamHudStats::orderFront();

    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                "Exited picture-in-picture");
}

void Session::togglePictureInPicture()
{
    if (m_PipActive) {
        exitPictureInPicture();
    }
    else {
        enterPictureInPicture();
    }
}
#endif // Q_OS_DARWIN

void Session::startMicrophone()
{
    if (!m_Preferences->enableMicrophone) {
        return;
    }

#ifdef Q_OS_DARWIN
    // GeForce Experience has no client-microphone receiver. Sending an
    // unknown control packet there is not useful and is avoided.
    if (m_Computer->isNvidiaServerSoftware) {
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                    "Microphone forwarding stays off for GeForce Experience hosts");
        return;
    }
    if (!m_Microphone.start()) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "Microphone capture did not start; continuing the stream without it");
    }
#else
    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                "Microphone forwarding is only implemented on macOS");
#endif
}

void Session::stopMicrophone()
{
    m_Microphone.stop();
}

void Session::toggleEnabledPerformanceOverlays()
{
    const int targets = performanceOverlayToggleTargets(m_Preferences->showPerformanceOverlay,
                                                        m_Preferences->showTwilightHud());
    if (targets & OverlayToggleClassic) {
        const bool next = !m_OverlayManager.isOverlayEnabled(Overlay::OverlayDebug);
        m_OverlayManager.setOverlayState(Overlay::OverlayDebug, next);
    }
    if ((targets & OverlayToggleTwilight) && StreamHudStats::instance() != nullptr) {
        StreamHudStats* hud = StreamHudStats::instance();
        hud->setHudShown(!hud->hudShown());
    }
    StreamHudStats::flushStreamUi();
    StreamHudStats::followStream();
}

bool Session::quickMenuOpen() const
{
    return StreamHudStats::instance() != nullptr && StreamHudStats::instance()->quickMenuOpen();
}

void Session::toggleQuickMenu()
{
    if (StreamHudStats::instance() == nullptr || !StreamHudStats::instance()->streaming()) {
        return;
    }
    if (quickMenuOpen()) {
        closeQuickMenu();
    }
    else {
        if (m_InputHandler != nullptr) {
            m_InputHandler->releaseCaptureForQuickMenu();
        }
        StreamHudStats::instance()->setQuickMenuOpen(true);
        StreamHudStats::flushStreamUi();
        StreamHudStats::followStream();
    }
}

void Session::closeQuickMenu()
{
    if (StreamHudStats::instance() != nullptr) {
        StreamHudStats::instance()->setQuickMenuOpen(false);
    }
    if (m_InputHandler != nullptr) {
        m_InputHandler->restoreCaptureAfterQuickMenu();
    }
    StreamHudStats::flushStreamUi();
    StreamHudStats::followStream();
}

void Session::endStreamFromQuickMenu()
{
    if (m_InputHandler != nullptr) {
        m_InputHandler->cancelQuickMenuRecapture();
    }
    if (StreamHudStats::instance() != nullptr) {
        StreamHudStats::instance()->setQuickMenuOpen(false);
    }
    if (StreamHudStats::instance() != nullptr) {
        StreamHudStats::instance()->requestDisconnect();
    }
}

void Session::toggleMicrophoneMute()
{
    if (!m_Microphone.isRunning()) {
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                    "Microphone capture is not active");
        return;
    }

    const bool muted = !m_Microphone.isMuted();
    m_Microphone.setMuted(muted);
    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                muted ? "Microphone muted" : "Microphone live");
}

