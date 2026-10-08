#pragma once

#include <QObject>
#include <QString>

// Live FPS / bitrate / latency for the Twilight HUD. Samples are produced on
// the decoder thread from the same overlay text V1 already builds, then
// applied on the GUI thread. The classic SDL overlay is unchanged.
class StreamHudStats : public QObject
{
    Q_OBJECT

    Q_PROPERTY(bool streaming READ streaming NOTIFY streamingChanged)
    Q_PROPERTY(bool hasSample READ hasSample NOTIFY statsChanged)
    Q_PROPERTY(QString fpsText READ fpsText NOTIFY statsChanged)
    Q_PROPERTY(QString bitrateText READ bitrateText NOTIFY statsChanged)
    Q_PROPERTY(QString latencyText READ latencyText NOTIFY statsChanged)
    Q_PROPERTY(QString codecText READ codecText NOTIFY statsChanged)

public:
    static void create(QObject* parent);
    static StreamHudStats* instance();

    bool streaming() const { return m_Streaming; }
    bool hasSample() const { return m_HasSample; }
    QString fpsText() const { return m_FpsText; }
    QString bitrateText() const { return m_BitrateText; }
    QString latencyText() const { return m_LatencyText; }
    QString codecText() const { return m_CodecText; }

    // Safe to call from the decoder thread. No-op until create() has run.
    static void submitOverlayText(const char* text);

    Q_INVOKABLE void noteSessionStarted();
    Q_INVOKABLE void noteSessionEnded();
    Q_INVOKABLE void requestDisconnect();

    // macOS stream loop cannot run the QML Timer: that needs processEvents(),
    // which dequeues the key-up SDL is waiting for. flushStreamUi() expires
    // this deadline instead. Other platforms still use the QML Timer.
    Q_INVOKABLE void armHudConfirm(int msec);

    // The QML HUD window. Kept so the stream loop can raise it after SDL
    // creates the fullscreen window. Parent stays null.
    Q_INVOKABLE void attachWindow(QObject* window);

    // The SDL stream window. The HUD is placed on that window's frame,
    // including after picture-in-picture moves it. Pass null once the
    // window is about to be destroyed.
    static void noteStreamWindow(void* sdlWindow);

    // Move the HUD onto the stream window without raising it.
    // Safe to call from the main thread during Session::execInternal().
    Q_INVOKABLE static void followStream();

    // Place the HUD and raise it above the stream when this HUD is enabled.
    // Safe to call from the main thread during Session::execInternal().
    Q_INVOKABLE static void orderFront();

    // Deliver queued Qt work (HUD samples, the End button) without dequeuing
    // Cocoa NSEvents. The macOS stream loop must not call processEvents().
    static void flushStreamUi();

    // Detach the HUD while the stream window's level, collection behavior,
    // fullscreen state, or frame is changing, then reattach when the matching
    // end runs. Nested. followStream and orderFront during the mutation are
    // deferred until the outermost end. macOS picture-in-picture uses this
    // so AppKit is not asked to restyle a parent that still has a child.
    static void beginStreamWindowMutation();
    static void endStreamWindowMutation();

signals:
    void streamingChanged();
    void statsChanged();
    void hudConfirmExpired();

public slots:
    void applySample(double fps, double bitrateMbps, bool hasBitrate, bool hasLatency, double latencyMs, QString codec);

private:
    explicit StreamHudStats(QObject* parent = nullptr);

    bool m_Streaming;
    bool m_HasSample;
    bool m_ConfirmArmed;
    quint32 m_ConfirmDeadline;
    QString m_FpsText;
    QString m_BitrateText;
    QString m_LatencyText;
    QString m_CodecText;
};
