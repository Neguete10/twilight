#include "network_profile.h"

#include "network_identity.h"
#include "streamingpreferences.h"

#include <QNetworkInterface>
#include <QSettings>
#include <QtDebug>

namespace {

const char* kSettingsKey = "networkprofiles";

static_assert(static_cast<int>(NetworkProfileStore::Custom) == static_cast<int>(NetworkProfiles::DisplayIntent::Custom),
              "QML display intent values must match the profile book");
static_assert(static_cast<int>(NetworkProfileStore::CouchTv) == static_cast<int>(NetworkProfiles::DisplayIntent::CouchTv),
              "QML display intent values must match the profile book");
static_assert(static_cast<int>(NetworkProfileStore::DeskMonitor) == static_cast<int>(NetworkProfiles::DisplayIntent::DeskMonitor),
              "QML display intent values must match the profile book");
static_assert(static_cast<int>(NetworkProfileStore::BatterySaver) == static_cast<int>(NetworkProfiles::DisplayIntent::BatterySaver),
              "QML display intent values must match the profile book");

static_assert(static_cast<int>(StreamingPreferences::VCC_AUTO) == 0, "stream preset codec integers");
static_assert(static_cast<int>(StreamingPreferences::VCC_FORCE_H264) == 1, "stream preset codec integers");
static_assert(static_cast<int>(StreamingPreferences::VCC_FORCE_HEVC) == 2, "stream preset codec integers");
static_assert(static_cast<int>(StreamingPreferences::VCC_FORCE_HEVC_HDR_DEPRECATED) == 3, "stream preset codec integers");
static_assert(static_cast<int>(StreamingPreferences::VCC_FORCE_AV1) == 4, "stream preset codec integers");
static_assert(static_cast<int>(StreamingPreferences::VCC_FORCE_PYROWAVE) == 5, "stream preset codec integers");
static_assert(static_cast<int>(StreamingPreferences::PWBC_AUTO) == 0, "stream preset pyro backend integers");
static_assert(static_cast<int>(StreamingPreferences::PWBC_METAL) == 1, "stream preset pyro backend integers");
static_assert(static_cast<int>(StreamingPreferences::PWBC_VULKAN) == 2, "stream preset pyro backend integers");
static_assert(static_cast<int>(StreamingPreferences::VDS_AUTO) == 0, "stream preset decoder integers");
static_assert(static_cast<int>(StreamingPreferences::VDS_FORCE_HARDWARE) == 1, "stream preset decoder integers");
static_assert(static_cast<int>(StreamingPreferences::VDS_FORCE_SOFTWARE) == 2, "stream preset decoder integers");
static_assert(static_cast<int>(StreamingPreferences::WM_FULLSCREEN) == 0, "stream preset window integers");
static_assert(static_cast<int>(StreamingPreferences::WM_FULLSCREEN_DESKTOP) == 1, "stream preset window integers");
static_assert(static_cast<int>(StreamingPreferences::WM_WINDOWED) == 2, "stream preset window integers");
static_assert(static_cast<int>(StreamingPreferences::AC_STEREO) == 0, "stream preset audio integers");
static_assert(static_cast<int>(StreamingPreferences::AC_51_SURROUND) == 1, "stream preset audio integers");
static_assert(static_cast<int>(StreamingPreferences::AC_71_SURROUND) == 2, "stream preset audio integers");
static_assert(static_cast<int>(StreamingPreferences::SAC_AUTO) == 0, "stream preset spatial integers");
static_assert(static_cast<int>(StreamingPreferences::SAC_DISABLED) == 1, "stream preset spatial integers");

std::string toStd(const QString& value)
{
    const QByteArray bytes = value.toUtf8();
    return std::string(bytes.constData(), static_cast<std::size_t>(bytes.size()));
}

QString fromStd(const std::string& value)
{
    return QString::fromUtf8(value.data(), static_cast<int>(value.size()));
}

std::vector<NetworkProfiles::Ipv4Iface> collectIpv4()
{
    std::vector<NetworkProfiles::Ipv4Iface> rows;
    const QList<QNetworkInterface> interfaces = QNetworkInterface::allInterfaces();
    for (const QNetworkInterface& iface : interfaces) {
        const bool isUp = iface.flags().testFlag(QNetworkInterface::IsUp);
        const bool isLoopback = iface.flags().testFlag(QNetworkInterface::IsLoopBack);
        const QList<QNetworkAddressEntry> entries = iface.addressEntries();
        for (const QNetworkAddressEntry& entry : entries) {
            if (entry.ip().protocol() != QAbstractSocket::IPv4Protocol) {
                continue;
            }
            NetworkProfiles::Ipv4Iface row;
            row.name = toStd(iface.name());
            row.addressHostOrder = entry.ip().toIPv4Address();
            row.prefixLength = entry.prefixLength();
            row.isUp = isUp;
            row.isLoopback = isLoopback;
            rows.push_back(row);
        }
    }
    return rows;
}

QString profileSubtitle(const NetworkProfiles::Profile& profile, bool matches)
{
    QString binding;
    if (matches) {
        binding = QStringLiteral("Matches this network");
        if (!profile.networkLabel.empty()) {
            binding += QStringLiteral(" · ");
            binding += fromStd(profile.networkLabel);
        }
    }
    else if (profile.bindingKind == NetworkProfiles::BindingKind::Unbound || profile.networkKey.empty()) {
        binding = QStringLiteral("Manual apply");
    }
    else {
        binding = fromStd(profile.networkLabel);
    }

    return binding + QStringLiteral(" · ") +
            fromStd(NetworkProfiles::intentLabel(profile.displayIntent)) +
            QStringLiteral(" · ") +
            fromStd(NetworkProfiles::streamSummary(profile.stream));
}

} // namespace

NetworkProfileStore* NetworkProfileStore::get()
{
    static NetworkProfileStore* store = new NetworkProfileStore();
    return store;
}

NetworkProfileStore::NetworkProfileStore(QObject* parent)
    : QObject(parent),
      m_SsidAvailable(false),
      m_MatchCount(0)
{
    load();
    refreshNetwork();
}

bool NetworkProfileStore::ssidAccessRequestable() const
{
#ifdef Q_OS_MACOS
    return !m_SsidAvailable;
#else
    return false;
#endif
}

void NetworkProfileStore::load()
{
    QSettings settings;
    const QString blob = settings.value(QLatin1String(kSettingsKey)).toString();
    if (blob.isEmpty()) {
        return;
    }
    NetworkProfiles::ProfileBook loaded;
    if (!loaded.deserialize(toStd(blob))) {
        qWarning("Saved network profiles could not be read; the stored value was left unchanged.");
        setStatus(QStringLiteral("Saved network profiles could not be read."));
        return;
    }
    m_Book = loaded;
}

bool NetworkProfileStore::writeBook(const NetworkProfiles::ProfileBook& book) const
{
    QSettings settings;
    settings.setValue(QLatin1String(kSettingsKey), fromStd(book.serialize()));
    settings.sync();
    return settings.status() == QSettings::NoError;
}

void NetworkProfileStore::setStatus(const QString& status)
{
    if (m_Status == status) {
        return;
    }
    m_Status = status;
    emit statusMessageChanged();
}

NetworkProfiles::Identity NetworkProfileStore::detectIdentity() const
{
    const SsidProbe probe = probePlatformSsid();
    return NetworkProfiles::identityFromProbe(probe.ssid, probe.note, collectIpv4());
}

void NetworkProfileStore::publish()
{
    const std::vector<const NetworkProfiles::Profile*> matches = m_Book.matching(toStd(m_NetworkKey));
    m_MatchCount = static_cast<int>(matches.size());
    m_SoleMatchId.clear();
    m_SoleMatchName.clear();
    if (matches.size() == 1) {
        m_SoleMatchId = fromStd(matches[0]->id);
        m_SoleMatchName = fromStd(matches[0]->name);
    }

    QVariantList rows;
    const std::vector<NetworkProfiles::Profile>& profiles = m_Book.all();
    for (std::size_t i = 0; i < profiles.size(); i++) {
        const NetworkProfiles::Profile& profile = profiles[i];
        const bool matchesCurrent = NetworkProfiles::networkKeysMatch(profile.networkKey, toStd(m_NetworkKey));
        QVariantMap row;
        row.insert(QStringLiteral("id"), fromStd(profile.id));
        row.insert(QStringLiteral("name"), fromStd(profile.name));
        row.insert(QStringLiteral("subtitle"), profileSubtitle(profile, matchesCurrent));
        row.insert(QStringLiteral("matchesCurrent"), matchesCurrent);
        row.insert(QStringLiteral("displayIntent"), static_cast<int>(profile.displayIntent));
        rows.append(row);
    }
    m_Profiles = rows;
    emit profilesChanged();
}

void NetworkProfileStore::refreshNetwork()
{
    const NetworkProfiles::Identity identity = detectIdentity();
    m_NetworkLabel = fromStd(identity.label);
    m_NetworkDetail = fromStd(identity.detail);
    m_NetworkKey = fromStd(identity.key);
    m_SsidAvailable = identity.ssidAvailable;
    publish();
    emit networkChanged();
}

void NetworkProfileStore::requestSsidAccess()
{
#ifndef Q_OS_MACOS
    refreshNetwork();
    setStatus(QStringLiteral("Wi-Fi name detection is only available on macOS. This system uses the fallback identity."));
    return;
#else
    setStatus(QStringLiteral("Requesting permission to read the Wi-Fi name..."));
    requestPlatformSsidAccess([this](bool granted) {
        refreshNetwork();
        if (m_SsidAvailable) {
            setStatus(QStringLiteral("Wi-Fi name detected."));
        }
        else if (!granted) {
            setStatus(QStringLiteral("Wi-Fi name is still unavailable. Profiles use the fallback identity, and Apply still works."));
        }
        else {
            setStatus(m_NetworkDetail);
        }
    });
#endif
}

QString NetworkProfileStore::suggestedProfileName() const
{
    const std::string seed = m_SsidAvailable ? toStd(m_NetworkLabel) : std::string("New profile");
    return fromStd(m_Book.uniqueName(seed));
}

QString NetworkProfileStore::intentDescription(int intent) const
{
    if (intent < 0 || intent > static_cast<int>(NetworkProfiles::DisplayIntent::BatterySaver)) {
        return QString();
    }
    return QString::fromUtf8(NetworkProfiles::intentDescription(static_cast<NetworkProfiles::DisplayIntent>(intent)));
}

bool NetworkProfileStore::saveCurrentSettings(const QString& name, int displayIntent, bool bindToNetwork)
{
    if (displayIntent < 0 || displayIntent > static_cast<int>(NetworkProfiles::DisplayIntent::BatterySaver)) {
        setStatus(QStringLiteral("Unknown display intent."));
        return false;
    }

    NetworkProfiles::Profile profile;
    const QString trimmed = name.trimmed();
    profile.name = trimmed.isEmpty() ? toStd(suggestedProfileName()) : toStd(trimmed);
    profile.displayIntent = static_cast<NetworkProfiles::DisplayIntent>(displayIntent);
    profile.stream = StreamingPreferences::get()->captureNetworkProfileSettings();

    if (bindToNetwork && !m_NetworkKey.isEmpty()) {
        profile.networkKey = toStd(m_NetworkKey);
        profile.networkLabel = toStd(m_NetworkLabel);
        profile.bindingKind = m_SsidAvailable ? NetworkProfiles::BindingKind::Ssid
                                              : NetworkProfiles::BindingKind::Fallback;
    }
    else {
        profile.bindingKind = NetworkProfiles::BindingKind::Unbound;
        profile.networkLabel = "Any network";
    }

    NetworkProfiles::ProfileBook updated = m_Book;
    std::string error;
    bool replaced = false;
    if (!updated.upsertByName(profile, &error, &replaced)) {
        setStatus(fromStd(error));
        return false;
    }
    if (!writeBook(updated)) {
        setStatus(QStringLiteral("Could not write the profile to settings."));
        return false;
    }
    m_Book = updated;
    publish();
    const QString savedName = fromStd(profile.name);
    setStatus(replaced ? QStringLiteral("Updated %1.").arg(savedName)
                       : QStringLiteral("Saved %1.").arg(savedName));
    return true;
}

bool NetworkProfileStore::applyProfile(const QString& id)
{
    const NetworkProfiles::Profile* profile = m_Book.find(toStd(id));
    if (!profile) {
        setStatus(QStringLiteral("That profile is no longer saved."));
        publish();
        return false;
    }
    StreamingPreferences::get()->applyNetworkProfileSettings(profile->stream);
    emit settingsApplied();
    setStatus(QStringLiteral("Applied %1.").arg(fromStd(profile->name)));
    return true;
}

bool NetworkProfileStore::deleteProfile(const QString& id)
{
    NetworkProfiles::ProfileBook updated = m_Book;
    std::string removedName;
    if (!updated.remove(toStd(id), &removedName)) {
        setStatus(QStringLiteral("That profile is no longer saved."));
        publish();
        return false;
    }
    if (!writeBook(updated)) {
        setStatus(QStringLiteral("Could not update settings."));
        return false;
    }
    m_Book = updated;
    publish();
    setStatus(QStringLiteral("Deleted %1.").arg(fromStd(removedName)));
    return true;
}

bool NetworkProfileStore::applyDisplayIntent(int intent)
{
    if (intent == static_cast<int>(NetworkProfiles::DisplayIntent::Custom)) {
        setStatus(QStringLiteral("Custom keeps the settings already chosen below."));
        return true;
    }
    if (intent < 0 || intent > static_cast<int>(NetworkProfiles::DisplayIntent::BatterySaver)) {
        setStatus(QStringLiteral("Unknown display intent."));
        return false;
    }

    const NetworkProfiles::DisplayIntent displayIntent = static_cast<NetworkProfiles::DisplayIntent>(intent);
    NetworkProfiles::StreamPreset preset = NetworkProfiles::presetForIntent(displayIntent);
    if (preset.width <= 0) {
        setStatus(QStringLiteral("Unknown display intent."));
        return false;
    }
    preset.bitrateKbps = StreamingPreferences::getDefaultBitrate(preset.width,
                                                                 preset.height,
                                                                 preset.fps,
                                                                 preset.enableYUV444);
    StreamingPreferences::get()->applyNetworkProfileSettings(preset);
    emit settingsApplied();
    setStatus(QString::fromUtf8(NetworkProfiles::intentLabel(displayIntent)) +
              QStringLiteral(" defaults loaded. Tweak them below, then save a profile."));
    return true;
}
