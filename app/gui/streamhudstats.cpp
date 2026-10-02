#include "streamhudstats.h"

#include "streamhudparse.h"
#include "settings/streamingpreferences.h"

#include <SDL.h>

#include <QMetaObject>
#include <QPointer>
#include <QWindow>

// raise: also order the window in front. Passing false only moves it.
void twilightHudSync(QWindow* window, void* sdlWindow, bool raise);

static QPointer<QWindow> s_HudWindow;
static void* s_StreamWindow = nullptr;

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
    s_HudWindow = qobject_cast<QWindow*>(window);
    orderFront();
}

void StreamHudStats::noteStreamWindow(void* sdlWindow)
{
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
    if (!hudShouldSync()) {
        return;
    }
    twilightHudSync(s_HudWindow.data(), s_StreamWindow, false);
}

void StreamHudStats::orderFront()
{
    if (!hudShouldSync()) {
        return;
    }
    twilightHudSync(s_HudWindow.data(), s_StreamWindow, true);
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
