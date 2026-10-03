#include "streamhudstats.h"

#include "streamhudparse.h"
#include "settings/streamingpreferences.h"

#include <SDL.h>

#include <QMetaObject>
#include <QPointer>
#include <QSurfaceFormat>
#include <QWindow>

// raise is ignored on macOS: the chips are ordered front on every sync.
// Passing false on other platforms only moves the window.
void twilightHudSync(QWindow* window, void* sdlWindow, bool raise);
void twilightHudDetach(QWindow* window);

static QPointer<QWindow> s_HudWindow;
static void* s_StreamWindow = nullptr;
static int s_StreamMutationDepth = 0;
static bool s_PendingHudOrderFront = false;
static bool s_PendingHudFollow = false;

#ifndef Q_OS_DARWIN
void twilightHudSync(QWindow* window, void* sdlWindow, bool raise)
{
    (void)sdlWindow;
    if (!raise || window == nullptr) {
        return;
    }
    window->show();
    window->raise();
}

void twilightHudDetach(QWindow* window)
{
    (void)window;
}
#endif

static StreamHudStats* s_Instance = nullptr;

void StreamHudStats::create(QObject* parent)
{
    if (s_Instance == nullptr) {
        s_Instance = new StreamHudStats(parent);
    }
}

StreamHudStats* StreamHudStats::instance()
{
    return s_Instance;
}

StreamHudStats::StreamHudStats(QObject* parent)
    : QObject(parent),
      m_Streaming(false),
      m_HasSample(false)
{
}

void StreamHudStats::submitOverlayText(const char* text)
{
    StreamHudStats* self = instance();
    if (self == nullptr) {
        return;
    }

    TwilightHudSample sample;
    if (!twilightParseHudSample(text, &sample)) {
        return;
    }

    const QString codec = QString::fromUtf8(sample.codec);
    QMetaObject::invokeMethod(self, "applySample", Qt::QueuedConnection,
                              Q_ARG(double, sample.fps),
                              Q_ARG(double, sample.bitrateMbps),
                              Q_ARG(bool, sample.hasBitrate),
                              Q_ARG(bool, sample.hasLatency),
                              Q_ARG(double, sample.latencyMs),
                              Q_ARG(QString, codec));
}

void StreamHudStats::applySample(double fps, double bitrateMbps, bool hasBitrate, bool hasLatency, double latencyMs, QString codec)
{
    if (!m_Streaming) {
        return;
    }

    m_HasSample = true;
    if (fps >= 100.0) {
        m_FpsText = QString::number(fps, 'f', 0);
    }
    else {
        m_FpsText = QString::number(fps, 'f', 1);
    }

    if (!hasBitrate) {
        m_BitrateText.clear();
    }
    else if (bitrateMbps < 1.0) {
        m_BitrateText = QString::number(bitrateMbps * 1000.0, 'f', 0) + QLatin1String(" kb/s");
    }
    else {
        m_BitrateText = QString::number(bitrateMbps, 'f', 1) + QLatin1String(" Mb/s");
    }

    if (!hasLatency) {
        m_LatencyText.clear();
    }
    else if (latencyMs >= 10.0) {
        m_LatencyText = QString::number(latencyMs, 'f', 0) + QLatin1String(" ms");
    }
    else {
        m_LatencyText = QString::number(latencyMs, 'f', 1) + QLatin1String(" ms");
    }

    m_CodecText = codec.trimmed();
    emit statsChanged();
}

void StreamHudStats::noteSessionStarted()
{
    const bool was = m_Streaming;
    m_Streaming = true;
    m_HasSample = false;
    m_FpsText.clear();
    m_BitrateText.clear();
    m_LatencyText.clear();
    m_CodecText.clear();
    emit statsChanged();
    if (!was) {
        emit streamingChanged();
    }
}

void StreamHudStats::noteSessionEnded()
{
    if (!m_Streaming && !m_HasSample) {
        return;
    }
    m_Streaming = false;
    m_HasSample = false;
    m_FpsText.clear();
    m_BitrateText.clear();
    m_LatencyText.clear();
    m_CodecText.clear();
    emit statsChanged();
    emit streamingChanged();
}

void StreamHudStats::attachWindow(QObject* window)
{
    QWindow* hud = qobject_cast<QWindow*>(window);
    s_HudWindow = hud;
    if (hud != nullptr && hud->format().alphaBufferSize() < 8) {
        // A transparent Qt Quick window without an alpha buffer never
        // composites, so the chips are invisible even when the window is up.
        QSurfaceFormat format = hud->format();
        format.setAlphaBufferSize(8);
        hud->setFormat(format);
    }
    orderFront();
}

void StreamHudStats::noteStreamWindow(void* sdlWindow)
{
    if (sdlWindow == nullptr && s_StreamWindow != nullptr) {
        // Drop the child relationship before SDL destroys the stream window.
        twilightHudDetach(s_HudWindow.data());
    }
    s_StreamWindow = sdlWindow;
}

static bool hudShouldSync()
{
    StreamHudStats* self = StreamHudStats::instance();
    if (self == nullptr || !self->streaming() || s_HudWindow.isNull()) {
        return false;
    }
    return StreamingPreferences::hudWantsSamples();
}

void StreamHudStats::followStream()
{
    if (s_StreamMutationDepth > 0) {
        s_PendingHudFollow = true;
        return;
    }
    if (!hudShouldSync()) {
        twilightHudDetach(s_HudWindow.data());
        return;
    }
    twilightHudSync(s_HudWindow.data(), s_StreamWindow, false);
}

void StreamHudStats::orderFront()
{
    if (s_StreamMutationDepth > 0) {
        s_PendingHudOrderFront = true;
        return;
    }
    if (!hudShouldSync()) {
        twilightHudDetach(s_HudWindow.data());
        return;
    }
    twilightHudSync(s_HudWindow.data(), s_StreamWindow, true);
}

void StreamHudStats::beginStreamWindowMutation()
{
    if (s_StreamMutationDepth == 0) {
        twilightHudDetach(s_HudWindow.data());
    }
    s_StreamMutationDepth++;
}

void StreamHudStats::endStreamWindowMutation()
{
    if (s_StreamMutationDepth <= 0) {
        s_StreamMutationDepth = 0;
        return;
    }
    s_StreamMutationDepth--;
    if (s_StreamMutationDepth > 0) {
        return;
    }

    const bool orderFrontPending = s_PendingHudOrderFront;
    const bool followPending = s_PendingHudFollow;
    s_PendingHudOrderFront = false;
    s_PendingHudFollow = false;
    if (orderFrontPending) {
        orderFront();
    }
    else if (followPending) {
        followStream();
    }
}

void StreamHudStats::requestDisconnect()
{
    if (!m_Streaming) {
        return;
    }

    // Same path as Ctrl+Alt+Shift+Q / the gamepad quit combo.
    SDL_Event event;
    event.type = SDL_QUIT;
    event.quit.timestamp = SDL_GetTicks();
    SDL_PushEvent(&event);
}
