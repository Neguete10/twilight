#pragma once

#include "network_profile_logic.h"

#include <QObject>
#include <QVariantList>

class NetworkProfileStore : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QVariantList profiles READ profiles NOTIFY profilesChanged)
    Q_PROPERTY(int profileCount READ profileCount NOTIFY profilesChanged)
    Q_PROPERTY(int matchingProfileCount READ matchingProfileCount NOTIFY profilesChanged)
    Q_PROPERTY(QString soleMatchId READ soleMatchId NOTIFY profilesChanged)
    Q_PROPERTY(QString soleMatchName READ soleMatchName NOTIFY profilesChanged)
    Q_PROPERTY(QString currentNetworkLabel READ currentNetworkLabel NOTIFY networkChanged)
    Q_PROPERTY(QString currentNetworkDetail READ currentNetworkDetail NOTIFY networkChanged)
    Q_PROPERTY(QString currentNetworkKey READ currentNetworkKey NOTIFY networkChanged)
    Q_PROPERTY(bool ssidAvailable READ ssidAvailable NOTIFY networkChanged)
    Q_PROPERTY(bool ssidAccessRequestable READ ssidAccessRequestable NOTIFY networkChanged)
    Q_PROPERTY(QString statusMessage READ statusMessage NOTIFY statusMessageChanged)

public:
    static NetworkProfileStore* get();

    // Same integers as NetworkProfiles::DisplayIntent, exposed for QML.
    enum DisplayIntent {
        Custom = 0,
        CouchTv = 1,
        DeskMonitor = 2,
        BatterySaver = 3
    };
    Q_ENUM(DisplayIntent)

    QVariantList profiles() const { return m_Profiles; }
    int profileCount() const { return m_Book.all().size(); }
    int matchingProfileCount() const { return m_MatchCount; }
    QString soleMatchId() const { return m_SoleMatchId; }
    QString soleMatchName() const { return m_SoleMatchName; }
    QString currentNetworkLabel() const { return m_NetworkLabel; }
    QString currentNetworkDetail() const { return m_NetworkDetail; }
    QString currentNetworkKey() const { return m_NetworkKey; }
    bool ssidAvailable() const { return m_SsidAvailable; }
    bool ssidAccessRequestable() const;
    QString statusMessage() const { return m_Status; }

    Q_INVOKABLE void refreshNetwork();
    Q_INVOKABLE void requestSsidAccess();
    Q_INVOKABLE QString suggestedProfileName() const;
    Q_INVOKABLE QString intentDescription(int intent) const;
    Q_INVOKABLE bool saveCurrentSettings(const QString& name, int displayIntent, bool bindToNetwork);
    Q_INVOKABLE bool applyProfile(const QString& id);
    Q_INVOKABLE bool deleteProfile(const QString& id);
    Q_INVOKABLE bool applyDisplayIntent(int intent);

signals:
    void profilesChanged();
    void networkChanged();
    void statusMessageChanged();
    void settingsApplied();

private:
    explicit NetworkProfileStore(QObject* parent = nullptr);

    void load();
    bool writeBook(const NetworkProfiles::ProfileBook& book) const;
    void publish();
    void setStatus(const QString& status);
    NetworkProfiles::Identity detectIdentity() const;

    NetworkProfiles::ProfileBook m_Book;
    QVariantList m_Profiles;
    QString m_NetworkLabel;
    QString m_NetworkDetail;
    QString m_NetworkKey;
    QString m_Status;
    QString m_SoleMatchId;
    QString m_SoleMatchName;
    bool m_SsidAvailable;
    int m_MatchCount;
};
