#pragma once

#include <cstdint>
#include <string>
#include <vector>

// Pure profile rules shared by the settings store and the offline test.
// No Qt, so the detection and apply decisions can be checked without a Mac
// or a QML runtime. See docs/NETWORK_PROFILES.md.

namespace NetworkProfiles {

enum class BindingKind {
    Unbound = 0,
    Ssid = 1,
    Fallback = 2
};

enum class DisplayIntent {
    Custom = 0,
    CouchTv = 1,
    DeskMonitor = 2,
    BatterySaver = 3
};

// Picture settings a profile copies onto StreamingPreferences.
// Enum integers match StreamingPreferences so they can be assigned directly.
// bitrateKbps == 0 on an intent preset means "fill with getDefaultBitrate
// when applying". Saved profiles always store a concrete bitrate.
struct StreamPreset {
    int width;
    int height;
    int fps;
    int bitrateKbps;
    bool unlockBitrate;
    int videoCodecConfig;
    int pyroWaveBackend;
    bool enableHdr;
    bool enableYUV444;
    int videoDecoderSelection;
    int windowMode;
    int audioConfig;
    int spatialAudioConfig;
    bool spatialHeadTracking;
    bool enableVsync;
    bool framePacing;
};

struct Profile {
    std::string id;
    std::string name;
    std::string networkKey;
    std::string networkLabel;
    BindingKind bindingKind;
    DisplayIntent displayIntent;
    StreamPreset stream;
};

struct Identity {
    BindingKind kind;
    std::string key;
    std::string label;
    std::string detail;
    bool ssidAvailable;
};

struct Ipv4Iface {
    std::string name;
    std::uint32_t addressHostOrder;
    int prefixLength;
    bool isUp;
    bool isLoopback;
};

StreamPreset emptyStreamPreset();
StreamPreset presetForIntent(DisplayIntent intent);
const char* intentLabel(DisplayIntent intent);
const char* intentDescription(DisplayIntent intent);
const char* codecLabel(int videoCodecConfig);
std::string streamSummary(const StreamPreset& preset);
bool streamPresetValid(const StreamPreset& preset);

// ssid wins when non-empty. Otherwise the best IPv4 interface becomes a
// fallback key, or the identity stays unbound when nothing is up.
Identity identityFromProbe(const std::string& ssid,
                           const std::string& probeNote,
                           const std::vector<Ipv4Iface>& ifaces);

bool networkKeysMatch(const std::string& savedKey, const std::string& currentKey);

class ProfileBook {
public:
    ProfileBook();

    bool upsertByName(Profile profile, std::string* error, bool* replaced);
    bool remove(const std::string& id, std::string* removedName);
    const Profile* find(const std::string& id) const;
    std::vector<const Profile*> matching(const std::string& currentKey) const;
    const std::vector<Profile>& all() const { return m_Profiles; }
    std::string uniqueName(const std::string& base) const;

    std::string serialize() const;
    bool deserialize(const std::string& blob);

private:
    std::vector<Profile> m_Profiles;
    int m_NextId;

    int indexOfName(const std::string& name) const;
    void noteId(const std::string& id);
};

} // namespace NetworkProfiles
