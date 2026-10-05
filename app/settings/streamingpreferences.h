#pragma once

#include "network_profile_logic.h"

#include <QObject>
#include <QRect>
#include <QQmlEngine>
#include <QString>

class StreamingPreferences : public QObject
{
    Q_OBJECT

public:
    static StreamingPreferences* get(QQmlEngine *qmlEngine = nullptr);

    Q_INVOKABLE static int
    getDefaultBitrate(int width, int height, int fps, bool yuv444);

    Q_INVOKABLE void save();

    // Copies or replaces the stream picture a network profile owns.
    // Other preferences (mouse, mDNS, and so on) stay as they are.
    void applyNetworkProfileSettings(const NetworkProfiles::StreamPreset& preset);
    NetworkProfiles::StreamPreset captureNetworkProfileSettings() const;

    void reload();

    enum AudioConfig
    {
        AC_STEREO,
        AC_51_SURROUND,
        AC_71_SURROUND
    };
    Q_ENUM(AudioConfig)

    enum SpatialAudioConfig
    {
        SAC_AUTO,
        SAC_DISABLED
    };
    Q_ENUM(SpatialAudioConfig)

    enum VideoCodecConfig
    {
        VCC_AUTO,
        VCC_FORCE_H264,
        VCC_FORCE_HEVC,
        VCC_FORCE_HEVC_HDR_DEPRECATED, // Kept for backwards compatibility
        VCC_FORCE_AV1,
        VCC_FORCE_PYROWAVE // Prefer PyroWave; H.264/HEVC/AV1 stay available as fallback
    };
    Q_ENUM(VideoCodecConfig)

    // Which GPU library decodes PyroWave. Does not change H.264, HEVC, or AV1.
    // New values go at the end so saved settings keep their numbers.
    // Auto on macOS is Metal when libpyrowave-metal loads, otherwise Vulkan.
    enum PyroWaveBackendConfig
    {
        PWBC_AUTO,
        PWBC_METAL,
        PWBC_VULKAN
    };
    Q_ENUM(PyroWaveBackendConfig)

    enum VideoDecoderSelection
    {
        VDS_AUTO,
        VDS_FORCE_HARDWARE,
        VDS_FORCE_SOFTWARE
    };
    Q_ENUM(VideoDecoderSelection)

    enum WindowMode
    {
        WM_FULLSCREEN,
        WM_FULLSCREEN_DESKTOP,
        WM_WINDOWED
    };
    Q_ENUM(WindowMode)

    enum UIDisplayMode
    {
        UI_WINDOWED,
        UI_MAXIMIZED,
        UI_FULLSCREEN
    };
    Q_ENUM(UIDisplayMode)

    enum CaptureSysKeysMode
    {
        CSK_OFF,
        CSK_FULLSCREEN,
        CSK_ALWAYS,
    };
    Q_ENUM(CaptureSysKeysMode);

    Q_PROPERTY(int width MEMBER width NOTIFY displayModeChanged)
    Q_PROPERTY(int height MEMBER height NOTIFY displayModeChanged)
    Q_PROPERTY(int fps MEMBER fps NOTIFY displayModeChanged)
    Q_PROPERTY(int bitrateKbps MEMBER bitrateKbps NOTIFY bitrateChanged)
    Q_PROPERTY(bool unlockBitrate MEMBER unlockBitrate NOTIFY unlockBitrateChanged)
    Q_PROPERTY(bool enableVsync MEMBER enableVsync NOTIFY enableVsyncChanged)
    Q_PROPERTY(bool gameOptimizations MEMBER gameOptimizations NOTIFY gameOptimizationsChanged)
    Q_PROPERTY(bool spatialHeadTracking MEMBER spatialHeadTracking NOTIFY spatialHeadTrackingChanged)
    Q_PROPERTY(bool playAudioOnHost MEMBER playAudioOnHost NOTIFY playAudioOnHostChanged)
    Q_PROPERTY(bool enableMicrophone MEMBER enableMicrophone NOTIFY enableMicrophoneChanged)
    Q_PROPERTY(QString microphoneStatusText READ microphoneStatusText NOTIFY microphoneStatusTextChanged)
    Q_PROPERTY(bool multiController MEMBER multiController NOTIFY multiControllerChanged)
    Q_PROPERTY(bool enableMdns MEMBER enableMdns NOTIFY enableMdnsChanged)
    Q_PROPERTY(bool quitAppAfter MEMBER quitAppAfter NOTIFY quitAppAfterChanged)
    Q_PROPERTY(bool absoluteMouseMode MEMBER absoluteMouseMode NOTIFY absoluteMouseModeChanged)
    Q_PROPERTY(bool coreHidMouse MEMBER coreHidMouse NOTIFY coreHidMouseChanged)
    Q_PROPERTY(bool absoluteTouchMode MEMBER absoluteTouchMode NOTIFY absoluteTouchModeChanged)
    Q_PROPERTY(bool framePacing MEMBER framePacing NOTIFY framePacingChanged)
    Q_PROPERTY(bool connectionWarnings MEMBER connectionWarnings NOTIFY connectionWarningsChanged)
    Q_PROPERTY(bool richPresence MEMBER richPresence NOTIFY richPresenceChanged)
    Q_PROPERTY(bool gamepadMouse MEMBER gamepadMouse NOTIFY gamepadMouseChanged)
    Q_PROPERTY(bool detectNetworkBlocking MEMBER detectNetworkBlocking NOTIFY detectNetworkBlockingChanged)
    Q_PROPERTY(bool showPerformanceOverlay MEMBER showPerformanceOverlay NOTIFY showPerformanceOverlayChanged)
    // Twilight's glass HUD. Independent of the classic yellow overlay.
    // Stored under the QSettings key "showTwilightHud". Missing key is off.
    Q_PROPERTY(bool showTwilightHud READ showTwilightHud WRITE setShowTwilightHud NOTIFY showTwilightHudChanged)
    Q_PROPERTY(AudioConfig audioConfig MEMBER audioConfig NOTIFY audioConfigChanged)
    Q_PROPERTY(SpatialAudioConfig spatialAudioConfig MEMBER spatialAudioConfig NOTIFY spatialAudioConfigChanged)
    Q_PROPERTY(VideoCodecConfig videoCodecConfig MEMBER videoCodecConfig NOTIFY videoCodecConfigChanged)
    Q_PROPERTY(PyroWaveBackendConfig pyroWaveBackend MEMBER pyroWaveBackend NOTIFY pyroWaveBackendChanged)
    Q_PROPERTY(bool enableHdr MEMBER enableHdr NOTIFY enableHdrChanged)
    Q_PROPERTY(bool enableYUV444 MEMBER enableYUV444 NOTIFY enableYUV444Changed)
    Q_PROPERTY(VideoDecoderSelection videoDecoderSelection MEMBER videoDecoderSelection NOTIFY videoDecoderSelectionChanged)
    Q_PROPERTY(WindowMode windowMode MEMBER windowMode NOTIFY windowModeChanged)
    Q_PROPERTY(WindowMode recommendedFullScreenMode MEMBER recommendedFullScreenMode CONSTANT)
    Q_PROPERTY(UIDisplayMode uiDisplayMode MEMBER uiDisplayMode NOTIFY uiDisplayModeChanged)
    Q_PROPERTY(bool swapMouseButtons MEMBER swapMouseButtons NOTIFY mouseButtonsChanged)
    Q_PROPERTY(bool muteOnFocusLoss MEMBER muteOnFocusLoss NOTIFY muteOnFocusLossChanged)
    Q_PROPERTY(bool backgroundGamepad MEMBER backgroundGamepad NOTIFY backgroundGamepadChanged)
    Q_PROPERTY(bool reverseScrollDirection MEMBER reverseScrollDirection NOTIFY reverseScrollDirectionChanged)
    Q_PROPERTY(bool swapFaceButtons MEMBER swapFaceButtons NOTIFY swapFaceButtonsChanged)
    Q_PROPERTY(bool keepAwake MEMBER keepAwake NOTIFY keepAwakeChanged)
    Q_PROPERTY(CaptureSysKeysMode captureSysKeysMode MEMBER captureSysKeysMode NOTIFY captureSysKeysModeChanged)
    // Always "v2" (Twilight). A stored "v1" is ignored and rewritten.
    // Stored under the QSettings key "uiVersion".
    Q_PROPERTY(QString uiVersion READ uiVersion WRITE setUiVersion NOTIFY uiVersionChanged)
    // UUID of the host last chosen in the Twilight shell. Empty if none.
    // Stored under the QSettings key "lastSelectedHostUuid".
    Q_PROPERTY(QString lastSelectedHostUuid READ lastSelectedHostUuid WRITE setLastSelectedHostUuid NOTIFY lastSelectedHostUuidChanged)

    // Thread-safe read for the decoder thread. True only while the Twilight
    // shell is selected and its performance overlay is enabled.
    static bool hudWantsSamples();

    QString uiVersion() const { return m_UiVersion; }
    void setUiVersion(const QString& version);
    QString lastSelectedHostUuid() const { return m_LastSelectedHostUuid; }
    void setLastSelectedHostUuid(const QString& uuid);
    bool showTwilightHud() const { return m_ShowTwilightHud; }
    void setShowTwilightHud(bool show);

    // macOS only. Shows the system microphone prompt when needed.
    // enableMicrophone becomes true only after access is granted.
    Q_INVOKABLE void setMicrophoneEnabled(bool enabled);

    Q_INVOKABLE void refreshMicrophoneStatus();

    QString microphoneStatusText() const;

    // Directly accessible members for preferences
    int width;
    int height;
    int fps;
    int bitrateKbps;
    bool unlockBitrate;
    bool enableVsync;
    bool gameOptimizations;
    bool spatialHeadTracking;
    bool playAudioOnHost;
    bool enableMicrophone;
    bool multiController;
    bool enableMdns;
    bool quitAppAfter;
    bool absoluteMouseMode;
    bool coreHidMouse;
    bool absoluteTouchMode;
    bool framePacing;
    bool connectionWarnings;
    bool richPresence;
    bool gamepadMouse;
    bool detectNetworkBlocking;
    bool showPerformanceOverlay;
    bool swapMouseButtons;
    bool muteOnFocusLoss;
    bool backgroundGamepad;
    bool reverseScrollDirection;
    bool swapFaceButtons;
    bool keepAwake;
    int packetSize;
    AudioConfig audioConfig;
    SpatialAudioConfig spatialAudioConfig;
    VideoCodecConfig videoCodecConfig;
    PyroWaveBackendConfig pyroWaveBackend;
    bool enableHdr;
    bool enableYUV444;
    VideoDecoderSelection videoDecoderSelection;
    WindowMode windowMode;
    WindowMode recommendedFullScreenMode;
    UIDisplayMode uiDisplayMode;
    CaptureSysKeysMode captureSysKeysMode;

signals:
    void displayModeChanged();
    void bitrateChanged();
    void unlockBitrateChanged();
    void enableVsyncChanged();
    void gameOptimizationsChanged();
    void spatialHeadTrackingChanged();
    void playAudioOnHostChanged();
    void enableMicrophoneChanged();
    void microphoneStatusTextChanged();
    void microphoneAccessFinished(bool granted);
    void multiControllerChanged();
    void unsupportedFpsChanged();
    void enableMdnsChanged();
    void quitAppAfterChanged();
    void absoluteMouseModeChanged();
    void coreHidMouseChanged();
    void absoluteTouchModeChanged();
    void audioConfigChanged();
    void spatialAudioConfigChanged();
    void videoCodecConfigChanged();
    void pyroWaveBackendChanged();
    void enableHdrChanged();
    void enableYUV444Changed();
    void videoDecoderSelectionChanged();
    void uiDisplayModeChanged();
    void windowModeChanged();
    void framePacingChanged();
    void connectionWarningsChanged();
    void richPresenceChanged();
    void gamepadMouseChanged();
    void detectNetworkBlockingChanged();
    void showPerformanceOverlayChanged();
    void showTwilightHudChanged();
    void mouseButtonsChanged();
    void muteOnFocusLossChanged();
    void backgroundGamepadChanged();
    void reverseScrollDirectionChanged();
    void swapFaceButtonsChanged();
    void captureSysKeysModeChanged();
    void keepAwakeChanged();
    void uiVersionChanged();
    void lastSelectedHostUuidChanged();

private:
    explicit StreamingPreferences(QQmlEngine *qmlEngine);

    void publishHudSamplingFlag();

    QString m_UiVersion;
    QString m_LastSelectedHostUuid;
    bool m_ShowTwilightHud;

    // Invoked on the GUI thread from the permission callback. Q_INVOKABLE so
    // QMetaObject::invokeMethod can queue it on Qt 5.9, which has no functor
    // overload of invokeMethod.
    Q_INVOKABLE void completeMicrophoneRequest(int serial, bool granted);

    QQmlEngine* m_QmlEngine;
    int m_MicRequestSerial = 0;
    QString m_MicrophoneStatusText;
};

