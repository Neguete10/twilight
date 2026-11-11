#include "settings/streamingpreferences.h"
#include "cli/commandlineparser.h"
#include "backend/nvaddress.h"
#include "backend/nvhttp_xml.h"
#include "backend/autoupdatechecker.h"
#include "backend/updateversion.h"

#include <QAbstractListModel>
#include <QFont>
#include <QGuiApplication>
#include <QImage>
#include <QQmlComponent>
#include <QQmlContext>
#include <QQmlEngine>
#include <QQuickImageProvider>
#include <QQuickWindow>
#include <QSettings>
#include <QTemporaryDir>
#include <QTest>

namespace {

const char kServerInfo[] =
    "<?xml version=\"1.0\"?>"
    "<root status_code=\"200\">"
    "<hostname>Desk</hostname>"
    "<appversion>7.1.0</appversion>"
    "<GfeVersion>3.23.0.74</GfeVersion>"
    "<uniqueid>0123456789ABCDEF</uniqueid>"
    "<HttpsPort>47984</HttpsPort>"
    "<ExternalPort>47989</ExternalPort>"
    "<PairStatus>1</PairStatus>"
    "<state>SUNSHINE_SERVER_FREE</state>"
    "<currentgame>881448767</currentgame>"
    "<LocalIP>192.168.1.20</LocalIP>"
    "</root>";

const char kBusyInfo[] =
    "<?xml version=\"1.0\"?>"
    "<root status_code=\"200\">"
    "<PairStatus>0</PairStatus>"
    "<state>SUNSHINE_SERVER_BUSY</state>"
    "<currentgame>881448767</currentgame>"
    "</root>";

const char kAppList[] =
    "<?xml version=\"1.0\"?>"
    "<root status_code=\"200\">"
    "<App><AppTitle>Desktop</AppTitle><ID>881448767</ID><IsHdrSupported>1</IsHdrSupported></App>"
    "<App><AppTitle>Game</AppTitle><ID>42</ID><IsHdrSupported>0</IsHdrSupported></App>"
    "</root>";

class StubComputerModel : public QAbstractListModel
{
    Q_OBJECT
public:
    Q_INVOKABLE void initialize(QObject*) {}
    Q_INVOKABLE int computerCount() const { return 0; }
    Q_INVOKABLE QString computerNameAt(int) const { return QString(); }
    Q_INVOKABLE QString computerUuidAt(int) const { return QString(); }
    Q_INVOKABLE bool computerOnlineAt(int) const { return false; }
    Q_INVOKABLE bool computerPairedAt(int) const { return false; }
    Q_INVOKABLE bool computerWakeableAt(int) const { return false; }
    Q_INVOKABLE bool computerBusyAt(int) const { return false; }
    Q_INVOKABLE bool computerStatusUnknownAt(int) const { return false; }
    Q_INVOKABLE bool computerSupportedAt(int) const { return true; }
    Q_INVOKABLE QString computerDetailsAt(int) const { return QString(); }
    Q_INVOKABLE QString generatePinString() { return QStringLiteral("0000"); }
    Q_INVOKABLE void pairComputer(int, QString) {}
    Q_INVOKABLE void testConnectionForComputer(int) {}
    Q_INVOKABLE void wakeComputer(int) {}
    Q_INVOKABLE void renameComputer(int, QString) {}
    Q_INVOKABLE void deleteComputer(int) {}

    int rowCount(const QModelIndex&) const override { return 0; }
    QVariant data(const QModelIndex&, int) const override { return QVariant(); }

signals:
    void pairingCompleted(QVariant error);
    void connectionTestCompleted(int result, QString blockedPorts);
    void wakeCompleted(int computerIndex, QString message, bool sent);
};

class StubComputerManager : public QObject
{
    Q_OBJECT
public:
    Q_INVOKABLE void startPolling() {}
    Q_INVOKABLE void stopPollingAsync() {}
    Q_INVOKABLE void addNewHostManually(QString) {}
    Q_INVOKABLE void quitApp(int) {}

signals:
    void computerAddCompleted(bool success, bool mdns);
    void quitAppCompleted(QString error);
};

class StubSystemProperties : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool supportsHdr MEMBER m_SupportsHdr CONSTANT)
    Q_PROPERTY(bool hasDesktopEnvironment MEMBER m_HasDesktop CONSTANT)
    Q_PROPERTY(bool hasBrowser MEMBER m_HasBrowser CONSTANT)
    Q_PROPERTY(bool hasPyroWaveMetal MEMBER m_HasMetal CONSTANT)
    Q_PROPERTY(bool hasPyroWaveVulkan MEMBER m_HasVulkan CONSTANT)
    Q_PROPERTY(QSize maximumResolution MEMBER m_Max CONSTANT)
    Q_PROPERTY(QString versionString MEMBER m_Version CONSTANT)
public:
    Q_INVOKABLE void refreshDisplays() {}
    Q_INVOKABLE QRect getNativeResolution(int index) const
    {
        return index == 0 ? QRect(0, 0, 2560, 1440) : QRect();
    }
    Q_INVOKABLE QRect getSafeAreaResolution(int) const { return QRect(); }
    Q_INVOKABLE int getRefreshRate(int index) const { return index == 0 ? 120 : 0; }
    Q_INVOKABLE void waitForAsyncLoad() {}

private:
    bool m_SupportsHdr = true;
    bool m_HasDesktop = true;
    bool m_HasBrowser = true;
    bool m_HasMetal = true;
    bool m_HasVulkan = false;
    QSize m_Max = QSize(3840, 2160);
    QString m_Version = QStringLiteral("7.2.0");
};

class StubGamepadNav : public QObject
{
    Q_OBJECT
public:
    Q_INVOKABLE void setUiNavMode(bool) {}
    Q_INVOKABLE int getConnectedGamepads() const { return 0; }
};

class StubHudStats : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool streaming MEMBER m_Streaming CONSTANT)
    Q_PROPERTY(bool hudShown MEMBER m_HudShown CONSTANT)
    Q_PROPERTY(bool quickMenuOpen MEMBER m_Quick CONSTANT)
    Q_PROPERTY(bool hasSample MEMBER m_HasSample CONSTANT)
    Q_PROPERTY(QString fpsText MEMBER m_Fps CONSTANT)
    Q_PROPERTY(QString bitrateText MEMBER m_Bitrate CONSTANT)
    Q_PROPERTY(QString latencyText MEMBER m_Latency CONSTANT)
    Q_PROPERTY(QString codecText MEMBER m_Codec CONSTANT)
public:
    Q_INVOKABLE void attachWindow(QObject*) {}
    Q_INVOKABLE void followStream() {}
    Q_INVOKABLE void orderFront() {}
    Q_INVOKABLE void endStreamFromMenu() {}
    Q_INVOKABLE void closeQuickMenu() {}
    Q_INVOKABLE void armHudConfirm(int) {}
    Q_INVOKABLE void requestDisconnect() {}

signals:
    void hudConfirmExpired();

private:
    bool m_Streaming = false;
    bool m_HudShown = false;
    bool m_Quick = false;
    bool m_HasSample = false;
    QString m_Fps;
    QString m_Bitrate;
    QString m_Latency;
    QString m_Codec;
};

class StubSymbolProvider : public QQuickImageProvider
{
public:
    StubSymbolProvider() : QQuickImageProvider(QQuickImageProvider::Image) {}
    QImage requestImage(const QString&, QSize* size, const QSize& requested) override
    {
        const QSize actual = requested.isValid() ? requested : QSize(16, 16);
        if (size) {
            *size = actual;
        }
        return QImage(actual, QImage::Format_ARGB32_Premultiplied);
    }
};

class StubAppList : public QAbstractListModel
{
    Q_OBJECT
public:
    enum Roles {
        NameRole = Qt::UserRole + 1,
        RunningRole,
        BoxArtRole,
        HiddenRole,
        DirectLaunchRole
    };

    int rowCount(const QModelIndex&) const override { return 2; }
    QVariant data(const QModelIndex& index, int role) const override
    {
        if (!index.isValid()) {
            return QVariant();
        }
        if (role == NameRole) {
            return index.row() == 0 ? QStringLiteral("Desktop") : QStringLiteral("Game");
        }
        if (role == RunningRole || role == HiddenRole || role == DirectLaunchRole) {
            return false;
        }
        if (role == BoxArtRole) {
            return QString();
        }
        return QVariant();
    }
    QHash<int, QByteArray> roleNames() const override
    {
        return {
            {NameRole, "name"},
            {RunningRole, "running"},
            {BoxArtRole, "boxart"},
            {HiddenRole, "hidden"},
            {DirectLaunchRole, "directLaunch"}
        };
    }

    Q_INVOKABLE int appCount() const { return 2; }
    Q_INVOKABLE QString appNameAt(int index) const
    {
        return index == 0 ? QStringLiteral("Desktop") : QStringLiteral("Game");
    }
    Q_INVOKABLE int appIdAt(int index) const { return index == 0 ? 881448767 : 42; }
    Q_INVOKABLE bool appDirectLaunchAt(int) const { return false; }
    Q_INVOKABLE QString appBoxArtAt(int) const { return QString(); }
    Q_INVOKABLE bool appRunningAt(int) const { return false; }
    Q_INVOKABLE bool appHiddenAt(int) const { return false; }
};

void clearSettings()
{
    QSettings settings;
    settings.clear();
    settings.sync();
}

StreamingPreferences* prefs()
{
    return StreamingPreferences::get();
}

class AppLogicTests : public QObject
{
    Q_OBJECT
private slots:
    void init()
    {
        clearSettings();
        prefs()->reload();
    }

    void defaults()
    {
        StreamingPreferences* streaming = prefs();
        QCOMPARE(streaming->width, 1920);
        QCOMPARE(streaming->height, 1080);
        QCOMPARE(streaming->fps, 60);
        QCOMPARE(streaming->bitrateKbps, StreamingPreferences::getDefaultBitrate(1920, 1080, 60, false));
        QVERIFY(streaming->autoAdjustBitrate);
        QVERIFY(!streaming->enableAdaptiveBitrate);
        QVERIFY(streaming->enableVsync);
        QCOMPARE(streaming->presentMode, StreamingPreferences::PRESENT_AUTO);
        QVERIFY(streaming->gameOptimizations);
        QVERIFY(!streaming->playAudioOnHost);
        QVERIFY(streaming->multiController);
        QVERIFY(streaming->enableMdns);
        QVERIFY(!streaming->quitAppAfter);
        QVERIFY(!streaming->absoluteMouseMode);
        QVERIFY(streaming->absoluteTouchMode);
        QVERIFY(!streaming->framePacing);
        QVERIFY(streaming->connectionWarnings);
        QVERIFY(streaming->configurationWarnings);
        QVERIFY(streaming->richPresence);
        QVERIFY(streaming->gamepadMouse);
        QVERIFY(streaming->detectNetworkBlocking);
        QVERIFY(!streaming->showPerformanceOverlay);
        QVERIFY(!streaming->showPerformanceGraphs);
        QVERIFY(!streaming->swapMouseButtons);
        QVERIFY(!streaming->muteOnFocusLoss);
        QVERIFY(!streaming->backgroundGamepad);
        QVERIFY(!streaming->reverseScrollDirection);
        QVERIFY(!streaming->swapFaceButtons);
        QVERIFY(streaming->keepAwake);
        QVERIFY(!streaming->enableHdr);
        QVERIFY(!streaming->enableYUV444);
        QVERIFY(!streaming->enableMetalFxUpscaling);
        QVERIFY(!streaming->enableMicrophone);
        QVERIFY(!streaming->coreHidMouse);
        QCOMPARE(streaming->audioConfig, StreamingPreferences::AC_STEREO);
        QCOMPARE(streaming->spatialAudioConfig, StreamingPreferences::SAC_DISABLED);
        QCOMPARE(streaming->videoCodecConfig, StreamingPreferences::VCC_AUTO);
        QCOMPARE(streaming->videoDecoderSelection, StreamingPreferences::VDS_AUTO);
        QCOMPARE(streaming->pyroWaveBackend, StreamingPreferences::PWBC_AUTO);
        QCOMPARE(streaming->captureSysKeysMode, StreamingPreferences::CSK_OFF);
        QCOMPARE(streaming->framePacingMode, StreamingPreferences::FRAME_PACING_IMMEDIATE);
        QCOMPARE(streaming->vtMetalFramesInFlight, 3);
        QCOMPARE(streaming->uiVersion(), QStringLiteral("v2"));
        QVERIFY(!streaming->showTwilightHud());
    }

    void bitrateTable()
    {
        QCOMPARE(StreamingPreferences::getDefaultBitrate(1920, 1080, 60, false), 20000);
        QCOMPARE(StreamingPreferences::getDefaultBitrate(1280, 720, 60, false), 10000);
        QCOMPARE(StreamingPreferences::getDefaultBitrate(3840, 2160, 60, false), 80000);
        QCOMPARE(StreamingPreferences::getDefaultBitrate(1920, 1080, 30, false), 10000);
        QCOMPARE(StreamingPreferences::getDefaultBitrate(1920, 1080, 60, true), 40000);
        QCOMPARE(StreamingPreferences::getDefaultBitrate(1920, 1080, 120, false), 28000);
    }

    void roundTrip()
    {
        StreamingPreferences* streaming = prefs();
        streaming->width = 2560;
        streaming->height = 1440;
        streaming->fps = 120;
        streaming->bitrateKbps = 45000;
        streaming->autoAdjustBitrate = false;
        streaming->enableAdaptiveBitrate = true;
        streaming->enableVsync = false;
        streaming->presentMode = StreamingPreferences::PRESENT_VRR;
        streaming->quitAppAfter = true;
        streaming->enableHdr = true;
        streaming->enableYUV444 = true;
        streaming->enableMetalFxUpscaling = true;
        streaming->enableMicrophone = true;
        streaming->audioConfig = StreamingPreferences::AC_51_SURROUND;
        streaming->videoCodecConfig = StreamingPreferences::VCC_FORCE_HEVC;
        streaming->videoDecoderSelection = StreamingPreferences::VDS_FORCE_HARDWARE;
        streaming->swapFaceButtons = true;
        streaming->backgroundGamepad = true;
        streaming->gamepadMouse = false;
        streaming->multiController = false;
        streaming->showPerformanceOverlay = true;
        streaming->setShowTwilightHud(true);
        streaming->coreHidMouse = true;
        streaming->absoluteMouseMode = true;
        streaming->muteOnFocusLoss = true;
        streaming->reverseScrollDirection = true;
        streaming->swapMouseButtons = true;
        streaming->playAudioOnHost = true;
        streaming->enableMdns = false;
        streaming->framePacing = true;
        streaming->save();

        streaming->width = 1;
        streaming->enableMetalFxUpscaling = false;
        streaming->enableVsync = true;
        streaming->quitAppAfter = false;
        streaming->reload();

        QCOMPARE(streaming->width, 2560);
        QCOMPARE(streaming->height, 1440);
        QCOMPARE(streaming->fps, 120);
        QCOMPARE(streaming->bitrateKbps, 45000);
        QVERIFY(!streaming->autoAdjustBitrate);
        QVERIFY(streaming->enableAdaptiveBitrate);
        QVERIFY(!streaming->enableVsync);
        QCOMPARE(streaming->presentMode, StreamingPreferences::PRESENT_VRR);
        QVERIFY(streaming->quitAppAfter);
        QVERIFY(streaming->enableHdr);
        QVERIFY(streaming->enableYUV444);
        QVERIFY(streaming->enableMetalFxUpscaling);
        QVERIFY(streaming->enableMicrophone);
        QCOMPARE(streaming->audioConfig, StreamingPreferences::AC_51_SURROUND);
        QCOMPARE(streaming->videoCodecConfig, StreamingPreferences::VCC_FORCE_HEVC);
        QCOMPARE(streaming->videoDecoderSelection, StreamingPreferences::VDS_FORCE_HARDWARE);
        QVERIFY(streaming->swapFaceButtons);
        QVERIFY(streaming->backgroundGamepad);
        QVERIFY(!streaming->gamepadMouse);
        QVERIFY(!streaming->multiController);
        QVERIFY(streaming->showPerformanceOverlay);
        QVERIFY(streaming->showTwilightHud());
        QVERIFY(streaming->coreHidMouse);
        QVERIFY(streaming->absoluteMouseMode);
        QVERIFY(streaming->muteOnFocusLoss);
        QVERIFY(streaming->reverseScrollDirection);
        QVERIFY(streaming->swapMouseButtons);
        QVERIFY(streaming->playAudioOnHost);
        QVERIFY(!streaming->enableMdns);
        QVERIFY(streaming->framePacing);
    }

    void savedVsyncOffStaysOff()
    {
        StreamingPreferences* streaming = prefs();
        streaming->enableVsync = false;
        streaming->presentMode = StreamingPreferences::PRESENT_AUTO;
        streaming->save();
        streaming->enableVsync = true;
        streaming->reload();
        QVERIFY(!streaming->enableVsync);
    }

    void missingVsyncWithNoVsyncPresentStartsOff()
    {
        {
            QSettings settings;
            settings.setValue(QStringLiteral("presentMode"), static_cast<int>(StreamingPreferences::PRESENT_NO_VSYNC));
            settings.remove(QStringLiteral("vsync"));
            settings.sync();
        }
        prefs()->reload();
        QVERIFY(!prefs()->enableVsync);
    }

    void metalFxDefaultsOffAndReloads()
    {
        QVERIFY(!prefs()->enableMetalFxUpscaling);
        prefs()->enableMetalFxUpscaling = true;
        prefs()->save();
        prefs()->enableMetalFxUpscaling = false;
        prefs()->reload();
        QVERIFY(prefs()->enableMetalFxUpscaling);
    }

    void unlimitedBitrateWordLoadsAsFiveHundredMegabits()
    {
        {
            QSettings settings;
            settings.setValue(QStringLiteral("bitrate"), QStringLiteral("unlimited"));
            settings.sync();
        }
        prefs()->reload();
        QCOMPARE(prefs()->bitrateKbps, 500000);
        QVERIFY(!prefs()->autoAdjustBitrate);
    }

    void customBitrateStopsTracking()
    {
        prefs()->bitrateKbps = 12345;
        prefs()->autoAdjustBitrate = true;
        prefs()->save();
        prefs()->reload();
        QCOMPARE(prefs()->bitrateKbps, 12345);
        QVERIFY(!prefs()->autoAdjustBitrate);
    }

    void deprecatedHevcHdrSplitsIntoHdrAndAuto()
    {
        {
            QSettings settings;
            settings.setValue(QStringLiteral("videocfg"), static_cast<int>(StreamingPreferences::VCC_FORCE_HEVC_HDR_DEPRECATED));
            settings.setValue(QStringLiteral("hdr"), false);
            settings.sync();
        }
        prefs()->reload();
        QCOMPARE(prefs()->videoCodecConfig, StreamingPreferences::VCC_AUTO);
        QVERIFY(prefs()->enableHdr);
    }

    void spatialAudioMigratesHeadTracking()
    {
        {
            QSettings settings;
            settings.setValue(QStringLiteral("spatialaudiocfg"), 0);
            settings.setValue(QStringLiteral("headtracking"), true);
            settings.sync();
        }
        prefs()->reload();
        QCOMPARE(prefs()->spatialAudioConfig, StreamingPreferences::SAC_HEAD_TRACKED);
        QVERIFY(!QSettings().contains(QStringLiteral("headtracking")));
    }

    void bitrateFieldRejectsOutOfRangeText()
    {
        QCOMPARE(prefs()->bitrateKbpsFromMbpsText(QStringLiteral("18.4")), 18400);
        QCOMPARE(prefs()->bitrateKbpsFromMbpsText(QStringLiteral("nope")), -1);
        QCOMPARE(prefs()->bitrateKbpsFromMbpsText(QStringLiteral("1001")), -1);
        QCOMPARE(prefs()->bitrateMbpsText(20000), QStringLiteral("20"));
    }

    void cliStreamOptions()
    {
        StreamingPreferences* streaming = prefs();
        StreamCommandLineParser parser;
        parser.parse(QStringList() << QStringLiteral("twilight") << QStringLiteral("stream")
                     << QStringLiteral("192.168.1.20") << QStringLiteral("Desktop")
                     << QStringLiteral("--720") << QStringLiteral("--fps") << QStringLiteral("60")
                     << QStringLiteral("--video-codec") << QStringLiteral("HEVC")
                     << QStringLiteral("--no-vsync") << QStringLiteral("--hdr")
                     << QStringLiteral("--quit-after") << QStringLiteral("--resolution") << QStringLiteral("1600x900"),
                     streaming);
        QCOMPARE(parser.getHost(), QStringLiteral("192.168.1.20"));
        QCOMPARE(parser.getAppName(), QStringLiteral("Desktop"));
        QCOMPARE(streaming->width, 1600);
        QCOMPARE(streaming->height, 900);
        QCOMPARE(streaming->fps, 60);
        QCOMPARE(streaming->videoCodecConfig, StreamingPreferences::VCC_FORCE_HEVC);
        QVERIFY(!streaming->enableVsync);
        QVERIFY(streaming->enableHdr);
        QVERIFY(streaming->quitAppAfter);
    }

    void cliActions()
    {
        GlobalCommandLineParser global;
        QCOMPARE(global.parse(QStringList() << QStringLiteral("twilight")), GlobalCommandLineParser::NormalStartRequested);
        QCOMPARE(global.parse(QStringList() << QStringLiteral("twilight") << QStringLiteral("list") << QStringLiteral("host")),
                 GlobalCommandLineParser::ListRequested);
        QCOMPARE(global.parse(QStringList() << QStringLiteral("twilight") << QStringLiteral("quit") << QStringLiteral("host")),
                 GlobalCommandLineParser::QuitRequested);
        QCOMPARE(global.parse(QStringList() << QStringLiteral("twilight") << QStringLiteral("pair") << QStringLiteral("host")),
                 GlobalCommandLineParser::PairRequested);
        QCOMPARE(global.parse(QStringList() << QStringLiteral("twilight") << QStringLiteral("stream") << QStringLiteral("host") << QStringLiteral("Desktop")),
                 GlobalCommandLineParser::StreamRequested);

        QuitCommandLineParser quit;
        quit.parse(QStringList() << QStringLiteral("twilight") << QStringLiteral("quit") << QStringLiteral("living-room"));
        QCOMPARE(quit.getHost(), QStringLiteral("living-room"));

        PairCommandLineParser pair;
        pair.parse(QStringList() << QStringLiteral("twilight") << QStringLiteral("pair") << QStringLiteral("10.0.0.8") << QStringLiteral("--pin") << QStringLiteral("1234"));
        QCOMPARE(pair.getHost(), QStringLiteral("10.0.0.8"));
        QCOMPARE(pair.getPredefinedPin(), QStringLiteral("1234"));

        ListCommandLineParser list;
        list.parse(QStringList() << QStringLiteral("twilight") << QStringLiteral("list") << QStringLiteral("host") << QStringLiteral("--csv") << QStringLiteral("--verbose"));
        QCOMPARE(list.getHost(), QStringLiteral("host"));
        QVERIFY(list.isPrintCSV());
        QVERIFY(list.isVerbose());
    }

    void manualHostAddress()
    {
        QString host;
        uint16_t port = 0;
        QVERIFY(NvAddress::parseManualHost(QStringLiteral("192.168.1.20"), &host, &port));
        QCOMPARE(host, QStringLiteral("192.168.1.20"));
        QCOMPARE(port, static_cast<uint16_t>(47989));

        QVERIFY(NvAddress::parseManualHost(QStringLiteral("192.168.1.20:47990"), &host, &port));
        QCOMPARE(port, static_cast<uint16_t>(47990));

        QVERIFY(NvAddress::parseManualHost(QStringLiteral("::1"), &host, &port));
        QCOMPARE(host, QStringLiteral("::1"));
        QCOMPARE(port, static_cast<uint16_t>(47989));

        QVERIFY(!NvAddress::parseManualHost(QStringLiteral("not a host"), &host, &port));

        NvAddress address(QStringLiteral("2001:db8::1"), 47989);
        QCOMPARE(address.toString(), QStringLiteral("[2001:db8::1]:47989"));
    }

    void serverInfoXml()
    {
        const QString info = QString::fromUtf8(kServerInfo);
        QCOMPARE(nvXmlTagText(info, QStringLiteral("hostname")), QStringLiteral("Desk"));
        QVERIFY(nvPairStatusIsPaired(info));
        QCOMPARE(nvCurrentGameId(info), 0);

        const QString busy = QString::fromUtf8(kBusyInfo);
        QVERIFY(!nvPairStatusIsPaired(busy));
        QCOMPARE(nvCurrentGameId(busy), 881448767);

        QCOMPARE(nvXmlTagText(QString::fromUtf8(kAppList), QStringLiteral("AppTitle")), QStringLiteral("Desktop"));
    }

    void updateCheckIsNotifyOnly()
    {
        AutoUpdateChecker checker;
        QVERIFY(!checker.macAppStoreBuild());
        QVERIFY(checker.checkOnLaunch());
        checker.setCheckOnLaunch(false);
        QCOMPARE(QSettings().value(QStringLiteral("checkForUpdatesOnLaunch")).toBool(), false);

        const QString current = QStringLiteral(VERSION_STR);
        QCOMPARE(current, QStringLiteral("7.2.0"));
        QCOMPARE(newerRelease(current.toStdString(), "v7.1.1"), 0);
        QCOMPARE(newerRelease(current.toStdString(), "v7.2.0"), 0);
        QCOMPARE(newerRelease(current.toStdString(), "v7.3.0"), 1);
        QVERIFY(isTrustedTwilightReleaseUrl("https://github.com/Neguete10/twilight/releases/tag/v7.2.0"));
    }
};

class ShellSmokeTests : public QObject
{
    Q_OBJECT
private slots:
    void shellLoadsAndSettingsStick()
    {
        QQmlEngine engine;
        QStringList warnings;
        QObject::connect(&engine, &QQmlEngine::warnings, &engine, [&warnings](const QList<QQmlError>& errors) {
            for (const QQmlError& error : errors) {
                warnings << error.toString();
            }
        });

        qmlRegisterType<StubComputerModel>("ComputerModel", 1, 0, "ComputerModel");
        qmlRegisterType<StubAppList>("AppModel", 1, 0, "AppModel");
        qmlRegisterSingletonType<StubComputerManager>("ComputerManager", 1, 0, "ComputerManager",
            [](QQmlEngine*, QJSEngine*) -> QObject* { return new StubComputerManager(); });
        qmlRegisterSingletonType<StubSystemProperties>("SystemProperties", 1, 0, "SystemProperties",
            [](QQmlEngine*, QJSEngine*) -> QObject* { return new StubSystemProperties(); });
        qmlRegisterSingletonType<StubGamepadNav>("SdlGamepadKeyNavigation", 1, 0, "SdlGamepadKeyNavigation",
            [](QQmlEngine*, QJSEngine*) -> QObject* { return new StubGamepadNav(); });
        qmlRegisterSingletonType<StubHudStats>("StreamHudStats", 1, 0, "StreamHudStats",
            [](QQmlEngine*, QJSEngine*) -> QObject* { return new StubHudStats(); });
        qmlRegisterSingletonType<AutoUpdateChecker>("AutoUpdateChecker", 1, 0, "AutoUpdateChecker",
            [](QQmlEngine*, QJSEngine*) -> QObject* { return new AutoUpdateChecker(); });
        qmlRegisterSingletonType<StreamingPreferences>("StreamingPreferences", 1, 0, "StreamingPreferences",
            [](QQmlEngine* qmlEngine, QJSEngine*) -> QObject* {
                return StreamingPreferences::get(qmlEngine);
            });

        engine.addImageProvider(QLatin1String("sfsymbol"), new StubSymbolProvider());

        clearSettings();
        prefs()->reload();

        const QString harnessPath = QStringLiteral(TWILIGHT_SOURCE_ROOT) + QStringLiteral("/tests/qml/HarnessWindow.qml");
        QQmlComponent component(&engine, QUrl::fromLocalFile(harnessPath));
        QVERIFY2(!component.isError(), qPrintable(component.errorString()));

        QObject* created = component.create();
        QVERIFY2(created, qPrintable(component.errorString()));
        created->setParent(&engine);
        QTest::qWait(150);

        QObject* shell = created->findChild<QObject*>(QStringLiteral("shell"));
        QVERIFY(shell);

        QObject* computers = shell->findChild<QObject*>(QStringLiteral("computerModel"));
        QVERIFY(computers);
        int count = -1;
        QVERIFY(QMetaObject::invokeMethod(computers, "computerCount", Q_RETURN_ARG(int, count)));
        QCOMPARE(count, 0);

        shell->setProperty("settingsOpen", true);
        QTest::qWait(50);
        QObject* sheet = shell->findChild<QObject*>(QStringLiteral("settingsSheet"));
        QVERIFY(sheet);
        QCOMPARE(sheet->property("open").toBool(), true);

        QVERIFY(!prefs()->enableMetalFxUpscaling);
        QObject* metal = shell->findChild<QObject*>(QStringLiteral("metalFxSwitch"));
        QVERIFY(metal);
        QVERIFY(QMetaObject::invokeMethod(metal, "activate"));
        QVERIFY(prefs()->enableMetalFxUpscaling);

        QVERIFY(prefs()->enableVsync);
        QObject* vsync = shell->findChild<QObject*>(QStringLiteral("vsyncSwitch"));
        QVERIFY(vsync);
        QVERIFY(QMetaObject::invokeMethod(vsync, "activate"));
        QVERIFY(!prefs()->enableVsync);

        QVERIFY(!prefs()->quitAppAfter);
        QObject* quitAfter = shell->findChild<QObject*>(QStringLiteral("quitAfterSwitch"));
        QVERIFY(quitAfter);
        QVERIFY(QMetaObject::invokeMethod(quitAfter, "activate"));
        QVERIFY(prefs()->quitAppAfter);

        QVERIFY(sheet->setProperty("section", QStringLiteral("audio")));
        QCOMPARE(sheet->property("section").toString(), QStringLiteral("audio"));
        QVERIFY(sheet->setProperty("section", QStringLiteral("video")));

        shell->setProperty("settingsOpen", false);
        QTest::qWait(20);
        QCOMPARE(sheet->property("open").toBool(), false);

        StubAppList apps;
        QQmlEngine::setObjectOwnership(&apps, QQmlEngine::CppOwnership);
        shell->setProperty("appModel", QVariant::fromValue(static_cast<QObject*>(&apps)));
        shell->setProperty("appRevision", shell->property("appRevision").toInt() + 1);
        QVERIFY(QMetaObject::invokeMethod(shell, "refreshDesktop"));
        QCOMPARE(shell->property("desktopIndex").toInt(), 0);
        QCOMPARE(shell->property("desktopShown").toBool(), true);
        shell->setProperty("query", QStringLiteral("zzz"));
        QCOMPARE(shell->property("desktopShown").toBool(), false);
        shell->setProperty("query", QString());
        QCOMPARE(shell->property("desktopShown").toBool(), true);

        QString unexpected;
        for (const QString& warning : warnings) {
            unexpected += warning + QLatin1Char('\n');
        }
        QVERIFY2(unexpected.isEmpty(), qPrintable(unexpected));
    }
};

} // namespace

int main(int argc, char** argv)
{
    QTemporaryDir configHome;
    if (!configHome.isValid()) {
        return 2;
    }
    qputenv("XDG_CONFIG_HOME", configHome.path().toUtf8());
    if (qEnvironmentVariableIsEmpty("QT_QPA_PLATFORM")) {
        qputenv("QT_QPA_PLATFORM", "offscreen");
    }
    QCoreApplication::setOrganizationName(QStringLiteral("TwilightTests"));
    QCoreApplication::setOrganizationDomain(QStringLiteral("twilight.tests"));
    QCoreApplication::setApplicationName(QStringLiteral("TwilightTests"));

    QGuiApplication app(argc, argv);
#ifdef Q_OS_DARWIN
    // Same reason as main: the default family "Sans Serif" is not installed.
    app.setFont(QFont(QStringLiteral("Helvetica Neue")));
#endif
    AppLogicTests logic;
    int status = QTest::qExec(&logic, argc, argv);
    ShellSmokeTests shell;
    status |= QTest::qExec(&shell, argc, argv);
    return status;
}

#include "twilight_qt_tests.moc"
