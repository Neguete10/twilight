#include "autoupdatechecker.h"
#include "updateversion.h"

#include <QNetworkReply>
#include <QJsonDocument>
#include <QJsonArray>
#include <QJsonObject>
#include <QSettings>
#include <QStringList>
#include <QSysInfo>
#include <QTimer>

namespace {

const char kReleasesUrl[] = "https://api.github.com/repos/Neguete10/twilight/releases/latest";
const char kCheckOnLaunchKey[] = "checkForUpdatesOnLaunch";

} // namespace

AutoUpdateChecker::AutoUpdateChecker(QObject *parent) :
    QObject(parent),
    m_VersionParsed(false),
    m_Nam(nullptr),
    m_Reply(nullptr),
    m_Timeout(new QTimer(this)),
    m_Generation(0),
    m_Checking(false),
    m_Manual(false),
    m_CheckOnLaunch(true)
{
    m_Timeout->setSingleShot(true);
    m_Timeout->setInterval(20000);
    connect(m_Timeout, &QTimer::timeout, this, &AutoUpdateChecker::handleCheckTimeout);

    QSettings settings;
    m_CheckOnLaunch = settings.value(QString::fromLatin1(kCheckOnLaunchKey), true).toBool();

    std::vector<int> current;
    const QString currentVersion(VERSION_STR);
    qInfo() << "Current Twilight version:" << currentVersion;
    m_VersionParsed = parseVersionQuad(currentVersion.toStdString(), current);
    if (!m_VersionParsed)
        qWarning() << "Twilight version could not be parsed:" << currentVersion;
}

bool AutoUpdateChecker::macAppStoreBuild() const
{
#if defined(TWILIGHT_MAS)
    return true;
#else
    return false;
#endif
}

bool AutoUpdateChecker::checksGitHubReleases() const
{
#if defined(TWILIGHT_MAS)
    return false;
#elif defined(Q_OS_WIN32) || defined(Q_OS_DARWIN) || defined(STEAM_LINK) || defined(APP_IMAGE)
    return true;
#else
    return false;
#endif
}

void AutoUpdateChecker::setCheckOnLaunch(bool enabled)
{
    if (m_CheckOnLaunch == enabled)
        return;

    m_CheckOnLaunch = enabled;
    QSettings settings;
    settings.setValue(QString::fromLatin1(kCheckOnLaunchKey), enabled);
    emit checkOnLaunchChanged();
}

void AutoUpdateChecker::setChecking(bool checking)
{
    if (m_Checking == checking)
        return;

    m_Checking = checking;
    emit checkingChanged();
}

void AutoUpdateChecker::clearOffer()
{
    if (m_AvailableVersion.isEmpty() && m_ReleasePageUrl.isEmpty() &&
            m_DownloadUrl.isEmpty() && m_ReleaseNotes.isEmpty()) {
        return;
    }

    m_AvailableVersion.clear();
    m_ReleasePageUrl.clear();
    m_DownloadUrl.clear();
    m_ReleaseNotes.clear();
    emit offerChanged();
}

void AutoUpdateChecker::publishOffer(const QString& version, const QString& releaseUrl, const QString& downloadUrl, const QString& notes)
{
    m_AvailableVersion = version;
    m_ReleasePageUrl = releaseUrl;
    m_DownloadUrl = downloadUrl;
    m_ReleaseNotes = notes;
    emit offerChanged();
}

void AutoUpdateChecker::start()
{
    if (!m_CheckOnLaunch)
        return;
    beginCheck(false);
}

void AutoUpdateChecker::checkNow()
{
    beginCheck(true);
}

void AutoUpdateChecker::beginCheck(bool manual)
{
    if (m_Checking) {
        // The launch check is already running. Report that result, because
        // the user just asked.
        if (manual)
            m_Manual = true;
        return;
    }

    m_Manual = manual;

    if (!checksGitHubReleases()) {
        // Launch stays quiet. A manual check explains why there is no prompt.
        if (!manual)
            return;
#if defined(TWILIGHT_MAS)
        finishWithFailure(tr("This copy of Twilight updates through the Mac App Store. It does not download a disk image."));
#else
        finishWithFailure(tr("This build does not check GitHub for Twilight releases."));
#endif
        return;
    }

    if (!m_VersionParsed) {
        finishWithFailure(tr("Twilight could not read its own version."));
        return;
    }

    if (!m_Nam) {
        m_Nam = new QNetworkAccessManager(this);
        // Never communicate over HTTP
        m_Nam->setStrictTransportSecurityEnabled(true);
        m_Nam->setRedirectPolicy(QNetworkRequest::NoLessSafeRedirectPolicy);
        connect(m_Nam, &QNetworkAccessManager::finished,
                this, &AutoUpdateChecker::handleUpdateCheckRequestFinished);
    }

#if QT_VERSION >= QT_VERSION_CHECK(5, 14, 0) && QT_VERSION < QT_VERSION_CHECK(5, 15, 1) && !defined(QT_NO_BEARERMANAGEMENT)
    // HACK: Set network accessibility to work around QTBUG-80947 (introduced in Qt 5.14.0 and fixed in Qt 5.15.1)
    QT_WARNING_PUSH
    QT_WARNING_DISABLE_DEPRECATED
    m_Nam->setNetworkAccessible(QNetworkAccessManager::Accessible);
    QT_WARNING_POP
#endif

    QNetworkRequest request(QUrl(QString::fromLatin1(kReleasesUrl)));
    request.setHeader(QNetworkRequest::UserAgentHeader,
                      QStringLiteral("Twilight-Qt/") + QString(VERSION_STR));
    request.setRawHeader("Accept", "application/vnd.github+json");
#if QT_VERSION >= QT_VERSION_CHECK(5, 15, 0)
    request.setAttribute(QNetworkRequest::Http2AllowedAttribute, true);
#else
    request.setAttribute(QNetworkRequest::HTTP2AllowedAttribute, true);
#endif

    setChecking(true);
    m_Generation++;
    m_Reply = m_Nam->get(request);
    if (!m_Reply) {
        finishWithFailure(tr("Twilight could not check for updates."));
        return;
    }
    m_Reply->setProperty("generation", m_Generation);
    m_Timeout->start();
}

void AutoUpdateChecker::finishWithFailure(const QString& message)
{
    qWarning() << "Update check:" << message;
    setChecking(false);
    if (m_Manual)
        emit checkFailed(message, true);
}

QString AutoUpdateChecker::failureMessage(QNetworkReply* reply) const
{
    const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
    if (status == 403 || status == 429)
        return tr("GitHub asked Twilight to wait before checking again.");
    if (status == 404)
        return tr("No Twilight release was published.");

    switch (reply->error()) {
    case QNetworkReply::HostNotFoundError:
    case QNetworkReply::TimeoutError:
    case QNetworkReply::TemporaryNetworkFailureError:
    case QNetworkReply::NetworkSessionFailedError:
    case QNetworkReply::UnknownNetworkError:
    case QNetworkReply::ConnectionRefusedError:
    case QNetworkReply::OperationCanceledError:
        return tr("Twilight could not reach GitHub to check for updates.");
    default:
        return tr("Twilight could not check for updates.");
    }
}

void AutoUpdateChecker::handleCheckTimeout()
{
    if (!m_Checking)
        return;

    // Invalidate the reply before aborting it. abort() can finish synchronously,
    // and that completion must not replace this timeout.
    m_Generation++;
    if (m_Reply) {
        QNetworkReply* stale = m_Reply;
        m_Reply = nullptr;
        stale->abort();
    }
    if (m_Nam) {
        m_Nam->deleteLater();
        m_Nam = nullptr;
    }
    finishWithFailure(tr("Twilight could not reach GitHub to check for updates."));
}

void AutoUpdateChecker::handleUpdateCheckRequestFinished(QNetworkReply* reply)
{
    Q_ASSERT(reply->isFinished());
    reply->deleteLater();

    if (reply == m_Reply)
        m_Reply = nullptr;

    // A timed-out or replaced request can finish after a newer check has started.
    if (reply->property("generation").toInt() != m_Generation)
        return;

    m_Timeout->stop();

    // Delete the QNetworkAccessManager to free resources and
    // prevent the bearer plugin from polling in the background.
    if (m_Nam) {
        m_Nam->deleteLater();
        m_Nam = nullptr;
    }

    const bool manual = m_Manual;
    setChecking(false);

    if (reply->error() != QNetworkReply::NoError) {
        qWarning() << "Update checking failed with error:" << reply->error();
        if (manual)
            emit checkFailed(failureMessage(reply), true);
        return;
    }

    QJsonParseError error;
    const QJsonDocument jsonDoc = QJsonDocument::fromJson(reply->readAll(), &error);
    const QJsonObject release = jsonDoc.object();
    if (jsonDoc.isNull() || release.isEmpty()) {
        qWarning() << "Update manifest malformed:" << error.errorString();
        if (manual)
            emit checkFailed(tr("Twilight could not read the update information from GitHub."), true);
        return;
    }

    if (release.value(QStringLiteral("draft")).toBool() || release.value(QStringLiteral("prerelease")).toBool()) {
        if (manual)
            emit checkFailed(tr("GitHub did not return a stable Twilight release."), true);
        return;
    }

    const QString tag = release.value(QStringLiteral("tag_name")).toString();
    const int relation = newerRelease(QString(VERSION_STR).toStdString(), tag.toStdString());
    if (relation < 0) {
        qWarning() << "Update tag is not a version:" << tag;
        if (manual)
            emit checkFailed(tr("Twilight could not read the update information from GitHub."), true);
        return;
    }

    std::vector<int> latestQuad;
    parseVersionQuad(tag.toStdString(), latestQuad);
    QStringList versionParts;
    for (int component : latestQuad)
        versionParts.append(QString::number(component));
    const QString latestVersion = versionParts.join(QLatin1Char('.'));

    if (relation == 0) {
        qInfo() << "Twilight is current. Latest release:" << latestVersion;
        clearOffer();
        if (manual)
            emit upToDate(latestVersion, true);
        return;
    }

    QString releaseUrl = release.value(QStringLiteral("html_url")).toString();
    if (!isTrustedTwilightReleaseUrl(releaseUrl.toStdString()))
        releaseUrl.clear();

    std::vector<std::string> names;
    std::vector<std::string> urls;
    const QJsonArray assets = release.value(QStringLiteral("assets")).toArray();
    for (int i = 0; i < assets.size(); i++) {
        const QJsonObject asset = assets.at(i).toObject();
        names.push_back(asset.value(QStringLiteral("name")).toString().toStdString());
        urls.push_back(asset.value(QStringLiteral("browser_download_url")).toString().toStdString());
    }

    QString downloadUrl;
#if defined(Q_OS_DARWIN) && !defined(TWILIGHT_MAS)
    downloadUrl = QString::fromStdString(selectDmgDownloadUrl(names, urls, QSysInfo::buildCpuArchitecture().toStdString()));
#endif

    if (releaseUrl.isEmpty() && downloadUrl.isEmpty()) {
        qWarning() << "No trusted Twilight release URL in the GitHub response";
        if (manual)
            emit checkFailed(tr("Twilight could not read the update information from GitHub."), true);
        return;
    }

    const QString notes = QString::fromStdString(trimReleaseNotes(release.value(QStringLiteral("body")).toString().toStdString(), 320));
    qInfo() << "Update available:" << latestVersion << downloadUrl << releaseUrl;
    publishOffer(latestVersion, releaseUrl, downloadUrl, notes);
    // manual is informational. The UI still waits for Download or Not now.
    emit updateAvailable(latestVersion, releaseUrl, downloadUrl, notes, manual);
}
