#include "network_profile_logic.h"

#include <cstddef>
#include <cstdio>
#include <cstdlib>

namespace NetworkProfiles {

namespace {

constexpr int kMaxProfiles = 32;
constexpr int kMaxNameLength = 64;
constexpr int kMaxFieldLength = 1024;
constexpr int kCodecHevcHdrDeprecated = 3;

std::string trimCopy(const std::string& value)
{
    std::size_t begin = 0;
    while (begin < value.size() && (value[begin] == ' ' || value[begin] == '\t' ||
                                    value[begin] == '\r' || value[begin] == '\n')) {
        begin++;
    }
    std::size_t end = value.size();
    while (end > begin && (value[end - 1] == ' ' || value[end - 1] == '\t' ||
                           value[end - 1] == '\r' || value[end - 1] == '\n')) {
        end--;
    }
    return value.substr(begin, end - begin);
}

char asciiLower(char c)
{
    if (c >= 'A' && c <= 'Z') {
        return static_cast<char>(c - 'A' + 'a');
    }
    return c;
}

bool asciiEquals(const std::string& left, const std::string& right)
{
    if (left.size() != right.size()) {
        return false;
    }
    for (std::size_t i = 0; i < left.size(); i++) {
        if (asciiLower(left[i]) != asciiLower(right[i])) {
            return false;
        }
    }
    return true;
}

bool startsWith(const std::string& value, const char* prefix)
{
    const std::size_t length = std::char_traits<char>::length(prefix);
    return value.size() >= length && value.compare(0, length, prefix) == 0;
}

bool isRfc1918(std::uint32_t address)
{
    const unsigned a = (address >> 24) & 0xffu;
    const unsigned b = (address >> 16) & 0xffu;
    if (a == 10) {
        return true;
    }
    if (a == 192 && b == 168) {
        return true;
    }
    if (a == 172 && b >= 16 && b <= 31) {
        return true;
    }
    return false;
}

bool isLinkLocal(std::uint32_t address)
{
    return (address & 0xffff0000u) == 0xa9fe0000u;
}

int nameRank(const std::string& name)
{
    if (startsWith(name, "en")) {
        return 30;
    }
    if (startsWith(name, "eth")) {
        return 20;
    }
    if (startsWith(name, "wlan")) {
        return 10;
    }
    return 0;
}

int interfaceScore(const Ipv4Iface& iface)
{
    if (!iface.isUp || iface.isLoopback || iface.name.empty()) {
        return -1;
    }
    if (iface.prefixLength < 1 || iface.prefixLength > 32) {
        return -1;
    }
    if (iface.addressHostOrder == 0 || isLinkLocal(iface.addressHostOrder)) {
        return -1;
    }
    int score = nameRank(iface.name);
    if (isRfc1918(iface.addressHostOrder)) {
        score += 100;
    }
    return score;
}

std::string ipv4String(std::uint32_t address)
{
    char buffer[16];
    std::snprintf(buffer, sizeof(buffer), "%u.%u.%u.%u",
                  (address >> 24) & 0xffu,
                  (address >> 16) & 0xffu,
                  (address >> 8) & 0xffu,
                  address & 0xffu);
    return buffer;
}

std::uint32_t networkAddress(std::uint32_t address, int prefixLength)
{
    if (prefixLength >= 32) {
        return address;
    }
    const std::uint32_t mask = 0xffffffffu << (32 - prefixLength);
    return address & mask;
}

std::string escapeField(const std::string& value)
{
    std::string out;
    out.reserve(value.size());
    for (std::size_t i = 0; i < value.size(); i++) {
        const char c = value[i];
        if (c == '\\') {
            out += "\\\\";
        }
        else if (c == '\n') {
            out += "\\n";
        }
        else if (c == '\r') {
            out += "\\r";
        }
        else if (c == '\x1f') {
            out += "\\x";
        }
        else {
            out.push_back(c);
        }
    }
    return out;
}

bool unescapeField(const std::string& value, std::string* out)
{
    out->clear();
    for (std::size_t i = 0; i < value.size(); i++) {
        if (value[i] != '\\') {
            out->push_back(value[i]);
            continue;
        }
        if (i + 1 >= value.size()) {
            return false;
        }
        const char next = value[++i];
        if (next == '\\') {
            out->push_back('\\');
        }
        else if (next == 'n') {
            out->push_back('\n');
        }
        else if (next == 'r') {
            out->push_back('\r');
        }
        else if (next == 'x') {
            out->push_back('\x1f');
        }
        else {
            return false;
        }
    }
    return out->size() <= static_cast<std::size_t>(kMaxFieldLength);
}

std::vector<std::string> splitFields(const std::string& line)
{
    std::vector<std::string> fields;
    std::string current;
    for (std::size_t i = 0; i < line.size(); i++) {
        if (line[i] == '\x1f') {
            fields.push_back(current);
            current.clear();
        }
        else {
            current.push_back(line[i]);
        }
    }
    fields.push_back(current);
    return fields;
}

bool parseInt(const std::string& text, int* out)
{
    if (text.empty()) {
        return false;
    }
    char* end = 0;
    const long value = std::strtol(text.c_str(), &end, 10);
    if (end == text.c_str() || *end != '\0') {
        return false;
    }
    *out = static_cast<int>(value);
    return true;
}

const char* kHeader = "twilight-net-profiles/1";

} // namespace

StreamPreset emptyStreamPreset()
{
    StreamPreset preset = {};
    return preset;
}

StreamPreset presetForIntent(DisplayIntent intent)
{
    StreamPreset preset = emptyStreamPreset();
    preset.pyroWaveBackend = 0;          // PWBC_AUTO
    preset.videoDecoderSelection = 0;    // VDS_AUTO
    preset.spatialAudioConfig = 0;       // SAC_AUTO
    preset.enableVsync = true;
    preset.framePacing = false;
    preset.unlockBitrate = false;
    preset.spatialHeadTracking = false;
    preset.enableYUV444 = false;
    preset.bitrateKbps = 0;

    switch (intent) {
    case DisplayIntent::CouchTv:
        preset.width = 1920;
        preset.height = 1080;
        preset.fps = 60;
        preset.videoCodecConfig = 2;    // VCC_FORCE_HEVC
        preset.enableHdr = true;
        preset.windowMode = 1;          // WM_FULLSCREEN_DESKTOP
        preset.audioConfig = 1;         // AC_51_SURROUND
        break;
    case DisplayIntent::DeskMonitor:
        preset.width = 2560;
        preset.height = 1440;
        preset.fps = 60;
        preset.videoCodecConfig = 0;    // VCC_AUTO
        preset.enableHdr = false;
        preset.windowMode = 2;          // WM_WINDOWED
        preset.audioConfig = 0;         // AC_STEREO
        break;
    case DisplayIntent::BatterySaver:
        preset.width = 1280;
        preset.height = 720;
        preset.fps = 30;
        preset.videoCodecConfig = 1;    // VCC_FORCE_H264
        preset.enableHdr = false;
        preset.windowMode = 2;          // WM_WINDOWED
        preset.audioConfig = 0;         // AC_STEREO
        break;
    case DisplayIntent::Custom:
    default:
        preset.width = 0;
        preset.height = 0;
        preset.fps = 0;
        break;
    }
    return preset;
}

const char* intentLabel(DisplayIntent intent)
{
    switch (intent) {
    case DisplayIntent::CouchTv:
        return "Couch TV";
    case DisplayIntent::DeskMonitor:
        return "Desk monitor";
    case DisplayIntent::BatterySaver:
        return "Battery saver";
    case DisplayIntent::Custom:
    default:
        return "Custom";
    }
}

const char* intentDescription(DisplayIntent intent)
{
    switch (intent) {
    case DisplayIntent::CouchTv:
        return "1080p60, HEVC, HDR, 5.1 audio, borderless fullscreen. A living-room TV preset you can tweak before saving.";
    case DisplayIntent::DeskMonitor:
        return "1440p60, automatic codec, stereo, windowed. A sharper desk-monitor preset you can tweak before saving.";
    case DisplayIntent::BatterySaver:
        return "720p30, H.264, stereo, windowed. Smaller frames for a hotspot or a laptop on battery. Tweak before saving.";
    case DisplayIntent::Custom:
    default:
        return "Keeps the bitrate, resolution, FPS, and codec already chosen below.";
    }
}

const char* codecLabel(int videoCodecConfig)
{
    switch (videoCodecConfig) {
    case 1:
        return "H.264";
    case 2:
        return "HEVC";
    case kCodecHevcHdrDeprecated:
        return "HEVC";
    case 4:
        return "AV1";
    case 5:
        return "PyroWave";
    case 0:
    default:
        return "Auto";
    }
}

std::string streamSummary(const StreamPreset& preset)
{
    char buffer[128];
    const int whole = preset.bitrateKbps / 1000;
    const int frac = (preset.bitrateKbps % 1000) / 100;
    std::snprintf(buffer, sizeof(buffer), "%dx%d · %d FPS · %d.%d Mbps · %s",
                  preset.width, preset.height, preset.fps, whole, frac,
                  codecLabel(preset.videoCodecConfig));
    return buffer;
}

bool streamPresetValid(const StreamPreset& preset)
{
    if (preset.width < 256 || preset.width > 8192) {
        return false;
    }
    if (preset.height < 256 || preset.height > 8192) {
        return false;
    }
    if (preset.fps < 10 || preset.fps > 9999) {
        return false;
    }
    if (preset.bitrateKbps < 500 || preset.bitrateKbps > 500000) {
        return false;
    }
    if (preset.videoCodecConfig < 0 || preset.videoCodecConfig > 5) {
        return false;
    }
    if (preset.pyroWaveBackend < 0 || preset.pyroWaveBackend > 2) {
        return false;
    }
    if (preset.videoDecoderSelection < 0 || preset.videoDecoderSelection > 2) {
        return false;
    }
    if (preset.windowMode < 0 || preset.windowMode > 2) {
        return false;
    }
    if (preset.audioConfig < 0 || preset.audioConfig > 2) {
        return false;
    }
    if (preset.spatialAudioConfig < 0 || preset.spatialAudioConfig > 1) {
        return false;
    }
    return true;
}

Identity identityFromProbe(const std::string& ssid,
                           const std::string& probeNote,
                           const std::vector<Ipv4Iface>& ifaces)
{
    Identity identity = {};
    const std::string trimmed = trimCopy(ssid);
    if (!trimmed.empty()) {
        identity.kind = BindingKind::Ssid;
        identity.key = std::string("ssid:") + trimmed;
        identity.label = trimmed;
        identity.ssidAvailable = true;
        identity.detail = probeNote.empty()
                ? "Wi-Fi name read from CoreWLAN. Profiles bound to this name match while you are on this network."
                : probeNote;
        return identity;
    }

    int bestScore = -1;
    const Ipv4Iface* best = 0;
    for (std::size_t i = 0; i < ifaces.size(); i++) {
        const int score = interfaceScore(ifaces[i]);
        if (score < 0) {
            continue;
        }
        if (!best || score > bestScore ||
                (score == bestScore && ifaces[i].name < best->name) ||
                (score == bestScore && ifaces[i].name == best->name &&
                 ifaces[i].addressHostOrder < best->addressHostOrder)) {
            best = &ifaces[i];
            bestScore = score;
        }
    }

    const std::string why = probeNote.empty() ? "Wi-Fi name unavailable." : probeNote;
    if (!best) {
        identity.kind = BindingKind::Unbound;
        identity.label = "No active network";
        identity.ssidAvailable = false;
        identity.detail = why + " No active IPv4 interface was found, so a new profile stays unbound until a network is up. Apply still works.";
        return identity;
    }

    const std::uint32_t network = networkAddress(best->addressHostOrder, best->prefixLength);
    char prefixBuffer[8];
    std::snprintf(prefixBuffer, sizeof(prefixBuffer), "%d", best->prefixLength);
    const std::string cidr = ipv4String(network) + "/" + prefixBuffer;
    identity.kind = BindingKind::Fallback;
    identity.key = std::string("fallback:") + best->name + ":" + cidr;
    identity.label = best->name + " " + cidr;
    identity.ssidAvailable = false;
    identity.detail = why + " Matching uses " + identity.label +
            " until a Wi-Fi name is available. Saved profiles can still be applied by hand.";
    return identity;
}

bool networkKeysMatch(const std::string& savedKey, const std::string& currentKey)
{
    if (savedKey.empty() || currentKey.empty()) {
        return false;
    }
    if (startsWith(savedKey, "ssid:") && startsWith(currentKey, "ssid:")) {
        return asciiEquals(savedKey.substr(5), currentKey.substr(5));
    }
    return savedKey == currentKey;
}

ProfileBook::ProfileBook()
    : m_NextId(1)
{
}

int ProfileBook::indexOfName(const std::string& name) const
{
    for (std::size_t i = 0; i < m_Profiles.size(); i++) {
        if (asciiEquals(m_Profiles[i].name, name)) {
            return static_cast<int>(i);
        }
    }
    return -1;
}

void ProfileBook::noteId(const std::string& id)
{
    if (id.size() < 2 || id[0] != 'p') {
        return;
    }
    int number = 0;
    if (!parseInt(id.substr(1), &number)) {
        return;
    }
    if (number >= m_NextId) {
        m_NextId = number + 1;
    }
}

std::string ProfileBook::uniqueName(const std::string& base) const
{
    const std::string trimmed = trimCopy(base);
    const std::string seed = trimmed.empty() ? std::string("New profile") : trimmed;
    if (indexOfName(seed) < 0) {
        return seed;
    }
    for (int suffix = 2; suffix < 1000; suffix++) {
        char buffer[16];
        std::snprintf(buffer, sizeof(buffer), " %d", suffix);
        const std::string candidate = seed + buffer;
        if (indexOfName(candidate) < 0) {
            return candidate;
        }
    }
    return seed;
}

bool ProfileBook::upsertByName(Profile profile, std::string* error, bool* replaced)
{
    if (replaced) {
        *replaced = false;
    }
    profile.name = trimCopy(profile.name);
    if (profile.name.empty()) {
        if (error) {
            *error = "Enter a profile name.";
        }
        return false;
    }
    if (profile.name.size() > static_cast<std::size_t>(kMaxNameLength)) {
        if (error) {
            *error = "Profile names are limited to 64 characters.";
        }
        return false;
    }
    if (static_cast<int>(profile.displayIntent) < 0 || static_cast<int>(profile.displayIntent) > 3) {
        if (error) {
            *error = "Unknown display intent.";
        }
        return false;
    }
    if (!streamPresetValid(profile.stream)) {
        if (error) {
            *error = "Current stream settings are outside the range a profile can store.";
        }
        return false;
    }
    if (profile.networkKey.size() > static_cast<std::size_t>(kMaxFieldLength) ||
            profile.networkLabel.size() > static_cast<std::size_t>(kMaxFieldLength)) {
        if (error) {
            *error = "The network identity is too long to store.";
        }
        return false;
    }

    const int existing = indexOfName(profile.name);
    if (existing >= 0) {
        profile.id = m_Profiles[static_cast<std::size_t>(existing)].id;
        m_Profiles[static_cast<std::size_t>(existing)] = profile;
        if (replaced) {
            *replaced = true;
        }
        return true;
    }
    if (static_cast<int>(m_Profiles.size()) >= kMaxProfiles) {
        if (error) {
            *error = "32 network profiles are already saved.";
        }
        return false;
    }
    char idBuffer[16];
    std::snprintf(idBuffer, sizeof(idBuffer), "p%d", m_NextId++);
    profile.id = idBuffer;
    m_Profiles.push_back(profile);
    return true;
}

bool ProfileBook::remove(const std::string& id, std::string* removedName)
{
    for (std::size_t i = 0; i < m_Profiles.size(); i++) {
        if (m_Profiles[i].id == id) {
            if (removedName) {
                *removedName = m_Profiles[i].name;
            }
            m_Profiles.erase(m_Profiles.begin() + static_cast<std::ptrdiff_t>(i));
            return true;
        }
    }
    return false;
}

const Profile* ProfileBook::find(const std::string& id) const
{
    for (std::size_t i = 0; i < m_Profiles.size(); i++) {
        if (m_Profiles[i].id == id) {
            return &m_Profiles[i];
        }
    }
    return 0;
}

std::vector<const Profile*> ProfileBook::matching(const std::string& currentKey) const
{
    std::vector<const Profile*> matches;
    for (std::size_t i = 0; i < m_Profiles.size(); i++) {
        if (networkKeysMatch(m_Profiles[i].networkKey, currentKey)) {
            matches.push_back(&m_Profiles[i]);
        }
    }
    return matches;
}

std::string ProfileBook::serialize() const
{
    std::string blob = kHeader;
    blob.push_back('\n');
    for (std::size_t i = 0; i < m_Profiles.size(); i++) {
        const Profile& profile = m_Profiles[i];
        const StreamPreset& stream = profile.stream;
        const std::string fields[] = {
            profile.id,
            profile.name,
            profile.networkKey,
            profile.networkLabel,
            std::string(1, static_cast<char>('0' + static_cast<int>(profile.bindingKind))),
            std::string(1, static_cast<char>('0' + static_cast<int>(profile.displayIntent))),
        };
        for (std::size_t field = 0; field < 6; field++) {
            if (field) {
                blob.push_back('\x1f');
            }
            blob += escapeField(fields[field]);
        }

        const int numbers[] = {
            stream.width,
            stream.height,
            stream.fps,
            stream.bitrateKbps,
            stream.unlockBitrate ? 1 : 0,
            stream.videoCodecConfig,
            stream.pyroWaveBackend,
            stream.enableHdr ? 1 : 0,
            stream.enableYUV444 ? 1 : 0,
            stream.videoDecoderSelection,
            stream.windowMode,
            stream.audioConfig,
            stream.spatialAudioConfig,
            stream.spatialHeadTracking ? 1 : 0,
            stream.enableVsync ? 1 : 0,
            stream.framePacing ? 1 : 0,
        };
        for (std::size_t number = 0; number < sizeof(numbers) / sizeof(numbers[0]); number++) {
            char buffer[16];
            std::snprintf(buffer, sizeof(buffer), "%d", numbers[number]);
            blob.push_back('\x1f');
            blob += buffer;
        }
        blob.push_back('\n');
    }
    return blob;
}

bool ProfileBook::deserialize(const std::string& blob)
{
    ProfileBook loaded;
    std::size_t cursor = 0;
    bool sawHeader = false;
    while (cursor < blob.size()) {
        std::size_t end = blob.find('\n', cursor);
        if (end == std::string::npos) {
            end = blob.size();
        }
        std::string line = blob.substr(cursor, end - cursor);
        cursor = end + (end < blob.size() ? 1 : 0);
        if (!line.empty() && line[line.size() - 1] == '\r') {
            line.erase(line.size() - 1);
        }
        if (line.empty()) {
            continue;
        }
        if (!sawHeader) {
            if (trimCopy(line) != kHeader) {
                return false;
            }
            sawHeader = true;
            continue;
        }

        const std::vector<std::string> fields = splitFields(line);
        if (fields.size() != 22) {
            return false;
        }
        Profile profile;
        if (!unescapeField(fields[0], &profile.id) ||
                !unescapeField(fields[1], &profile.name) ||
                !unescapeField(fields[2], &profile.networkKey) ||
                !unescapeField(fields[3], &profile.networkLabel)) {
            return false;
        }
        if (profile.id.empty() || profile.name.empty()) {
            return false;
        }

        int binding = 0;
        int intent = 0;
        if (!parseInt(fields[4], &binding) || binding < 0 || binding > 2) {
            return false;
        }
        if (!parseInt(fields[5], &intent) || intent < 0 || intent > 3) {
            return false;
        }
        profile.bindingKind = static_cast<BindingKind>(binding);
        profile.displayIntent = static_cast<DisplayIntent>(intent);

        int numbers[16];
        for (int i = 0; i < 16; i++) {
            if (!parseInt(fields[static_cast<std::size_t>(6 + i)], &numbers[i])) {
                return false;
            }
        }
        StreamPreset& stream = profile.stream;
        stream.width = numbers[0];
        stream.height = numbers[1];
        stream.fps = numbers[2];
        stream.bitrateKbps = numbers[3];
        stream.unlockBitrate = numbers[4] != 0;
        stream.videoCodecConfig = numbers[5];
        stream.pyroWaveBackend = numbers[6];
        stream.enableHdr = numbers[7] != 0;
        stream.enableYUV444 = numbers[8] != 0;
        stream.videoDecoderSelection = numbers[9];
        stream.windowMode = numbers[10];
        stream.audioConfig = numbers[11];
        stream.spatialAudioConfig = numbers[12];
        stream.spatialHeadTracking = numbers[13] != 0;
        stream.enableVsync = numbers[14] != 0;
        stream.framePacing = numbers[15] != 0;
        if (!streamPresetValid(stream)) {
            return false;
        }
        // Bools were stored as general integers. Only 0 and 1 are accepted
        // for the flags so a corrupt row cannot look like a real profile.
        if (numbers[4] < 0 || numbers[4] > 1 || numbers[7] < 0 || numbers[7] > 1 ||
                numbers[8] < 0 || numbers[8] > 1 || numbers[13] < 0 || numbers[13] > 1 ||
                numbers[14] < 0 || numbers[14] > 1 || numbers[15] < 0 || numbers[15] > 1) {
            return false;
        }
        if (static_cast<int>(loaded.m_Profiles.size()) >= kMaxProfiles) {
            return false;
        }
        loaded.noteId(profile.id);
        loaded.m_Profiles.push_back(profile);
    }
    if (!sawHeader) {
        return false;
    }
    m_Profiles.swap(loaded.m_Profiles);
    m_NextId = loaded.m_NextId;
    return true;
}

} // namespace NetworkProfiles
