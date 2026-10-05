#pragma once

#include <QObject>
#include <QNetworkAccessManager>

class QNetworkReply;
class QTimer;

// Looks up the latest Twilight release on GitHub.
//
// A newer release is reported to the UI. Nothing is downloaded and the
// running app is not replaced. The user chooses Download / View release
// or Not now. There is no Sparkle (or other) in-place installer in this
// tree; opening the disk image is the follow-up the user finishes in Finder.
class AutoUpdateChecker : public QObject
{
    Q_OBJECT

public:
    explicit AutoUpdateChecker(QObject *parent = nullptr);

    // Launch check. Stays quiet when this copy is current or the network fails.
    Q_INVOKABLE void start();

    // About → Check for Updates. Always reports the outcome.
    Q_INVOKABLE void checkNow();

    Q_PROPERTY(bool checking READ checking NOTIFY checkingChanged)
    Q_PROPERTY(bool checkOnLaunch READ checkOnLaunch WRITE setCheckOnLaunch NOTIFY checkOnLaunchChanged)
    Q_PROPERTY(bool checksGitHubReleases READ checksGitHubReleases CONSTANT)
    Q_PROPERTY(bool macAppStoreBuild READ macAppStoreBuild CONSTANT)
    Q_PROPERTY(QString availableVersion READ availableVersion NOTIFY offerChanged)
    Q_PROPERTY(QString releasePageUrl READ releasePageUrl NOTIFY offerChanged)
    Q_PROPERTY(QString downloadUrl READ downloadUrl NOTIFY offerChanged)
    Q_PROPERTY(QString releaseNotes READ releaseNotes NOTIFY offerChanged)

    bool checking() const { return m_Checking; }
    bool checkOnLaunch() const { return m_CheckOnLaunch; }
    void setCheckOnLaunch(bool enabled);
    bool checksGitHubReleases() const;
    bool macAppStoreBuild() const;

    QString availableVersion() const { return m_AvailableVersion; }
    QString releasePageUrl() const { return m_ReleasePageUrl; }
    QString downloadUrl() const { return m_DownloadUrl; }
    QString releaseNotes() const { return m_ReleaseNotes; }

signals:
    void updateAvailable(QString version, QString releaseUrl, QString downloadUrl, QString notes, bool manual);
    void upToDate(QString version, bool manual);
    void checkFailed(QString message, bool manual);

    void checkingChanged();
    void checkOnLaunchChanged();
    void offerChanged();

private slots:
    void handleUpdateCheckRequestFinished(QNetworkReply* reply);
    void handleCheckTimeout();

private:
    void beginCheck(bool manual);
    void setChecking(bool checking);
    void clearOffer();
    void publishOffer(const QString& version, const QString& releaseUrl, const QString& downloadUrl, const QString& notes);
    void finishWithFailure(const QString& message);
    QString failureMessage(QNetworkReply* reply) const;

    bool m_VersionParsed;
    QNetworkAccessManager* m_Nam;
    QNetworkReply* m_Reply;
    QTimer* m_Timeout;
    int m_Generation;
    bool m_Checking;
    bool m_Manual;
    bool m_CheckOnLaunch;
    QString m_AvailableVersion;
    QString m_ReleasePageUrl;
    QString m_DownloadUrl;
    QString m_ReleaseNotes;
};
