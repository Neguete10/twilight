#include "network_profile_logic.h"

#include <cstdio>
#include <string>

using namespace NetworkProfiles;

static int g_Failures = 0;

static void expect(bool condition, const char* label)
{
    if (!condition) {
        std::printf("FAIL %s\n", label);
        g_Failures++;
    }
}

static StreamPreset validStream()
{
    StreamPreset preset = emptyStreamPreset();
    preset.width = 1920;
    preset.height = 1080;
    preset.fps = 60;
    preset.bitrateKbps = 20000;
    preset.enableVsync = true;
    return preset;
}

static Profile makeProfile(const std::string& name, const std::string& key, DisplayIntent intent)
{
    Profile profile;
    profile.name = name;
    profile.networkKey = key;
    profile.networkLabel = key.empty() ? "Any network" : key;
    profile.bindingKind = key.empty() ? BindingKind::Unbound : BindingKind::Ssid;
    profile.displayIntent = intent;
    profile.stream = validStream();
    return profile;
}

static Ipv4Iface iface(const char* name, unsigned address, int prefix, bool up, bool loopback)
{
    Ipv4Iface row;
    row.name = name;
    row.addressHostOrder = address;
    row.prefixLength = prefix;
    row.isUp = up;
    row.isLoopback = loopback;
    return row;
}

int main()
{
    const StreamPreset couch = presetForIntent(DisplayIntent::CouchTv);
    expect(couch.width == 1920 && couch.height == 1080 && couch.fps == 60, "couch picture");
    expect(couch.videoCodecConfig == 2 && couch.enableHdr && !couch.enableYUV444, "couch codec");
    expect(couch.windowMode == 1 && couch.audioConfig == 1, "couch window and audio");
    expect(couch.bitrateKbps == 0 && couch.enableVsync && !couch.framePacing, "couch bitrate filled later");
    expect(!couch.unlockBitrate && !couch.spatialHeadTracking, "couch extras off");

    const StreamPreset desk = presetForIntent(DisplayIntent::DeskMonitor);
    expect(desk.width == 2560 && desk.height == 1440 && desk.fps == 60, "desk picture");
    expect(desk.videoCodecConfig == 0 && !desk.enableHdr && desk.windowMode == 2, "desk codec and window");
    expect(desk.audioConfig == 0 && !desk.enableYUV444, "desk audio");

    const StreamPreset battery = presetForIntent(DisplayIntent::BatterySaver);
    expect(battery.width == 1280 && battery.height == 720 && battery.fps == 30, "battery picture");
    expect(battery.videoCodecConfig == 1 && battery.windowMode == 2 && battery.audioConfig == 0, "battery codec");
    expect(!battery.enableHdr && !battery.enableYUV444, "battery extras off");

    expect(presetForIntent(DisplayIntent::Custom).width == 0, "custom does not overwrite");
    expect(std::string(intentLabel(DisplayIntent::CouchTv)) == "Couch TV", "couch label");
    expect(std::string(intentDescription(DisplayIntent::CouchTv)).find("1080p60") != std::string::npos, "couch description");
    expect(std::string(intentDescription(DisplayIntent::DeskMonitor)).find("1440p60") != std::string::npos, "desk description");
    expect(std::string(intentDescription(DisplayIntent::BatterySaver)).find("720p30") != std::string::npos, "battery description");
    expect(std::string(intentDescription(DisplayIntent::Custom)).find("already chosen") != std::string::npos, "custom description");

    StreamPreset summaryPreset = couch;
    summaryPreset.bitrateKbps = 20000;
    expect(streamSummary(summaryPreset) == "1920x1080 · 60 FPS · 20.0 Mbps · HEVC", "summary");

    std::vector<Ipv4Iface> ethernet;
    ethernet.push_back(iface("lo", 0x7f000001u, 8, true, true));
    ethernet.push_back(iface("en0", 0xc0a80132u, 24, true, false)); // 192.168.1.50/24
    ethernet.push_back(iface("en1", 0xa9fe0101u, 16, true, false)); // 169.254.1.1
    ethernet.push_back(iface("eth0", 0x0a000005u, 8, false, false)); // down

    Identity fallback = identityFromProbe("", "CoreWLAN did not return a Wi-Fi name.", ethernet);
    expect(fallback.kind == BindingKind::Fallback, "fallback kind");
    expect(!fallback.ssidAvailable, "fallback has no ssid");
    expect(fallback.key == "fallback:en0:192.168.1.0/24", "fallback key");
    expect(fallback.label == "en0 192.168.1.0/24", "fallback label");
    expect(fallback.detail.find("en0 192.168.1.0/24") != std::string::npos, "fallback detail");

    Identity ssid = identityFromProbe("  Home Wi-Fi  ", "CoreWLAN reported this Wi-Fi name.", ethernet);
    expect(ssid.kind == BindingKind::Ssid && ssid.ssidAvailable, "ssid wins");
    expect(ssid.key == "ssid:Home Wi-Fi" && ssid.label == "Home Wi-Fi", "ssid key");
    expect(ssid.detail.find("CoreWLAN reported") != std::string::npos, "ssid note kept");

    std::vector<Ipv4Iface> ranked;
    ranked.push_back(iface("eth0", 0x08080808u, 24, true, false)); // 8.8.8.8 public
    ranked.push_back(iface("en1", 0x0a000005u, 8, true, false));   // 10.0.0.5/8
    Identity preferred = identityFromProbe("", "", ranked);
    expect(preferred.key == "fallback:en1:10.0.0.0/8", "prefer private en* interface");

    std::vector<Ipv4Iface> none;
    none.push_back(iface("lo", 0x7f000001u, 8, true, true));
    Identity unbound = identityFromProbe("   ", "", none);
    expect(unbound.kind == BindingKind::Unbound && unbound.key.empty(), "no iface stays unbound");
    expect(!networkKeysMatch("", ""), "empty keys never match");
    expect(!networkKeysMatch(unbound.key, "ssid:Home Wi-Fi"), "unbound does not match ssid");

    expect(networkKeysMatch("ssid:Home Wi-Fi", "ssid:home wi-fi"), "ssid match ignores ascii case");
    expect(!networkKeysMatch("ssid:Home Wi-Fi", "ssid:Work"), "different ssid");
    expect(networkKeysMatch(fallback.key, "fallback:en0:192.168.1.0/24"), "fallback exact match");
    expect(!networkKeysMatch(fallback.key, "fallback:en0:192.168.0.0/24"), "different subnet");
    expect(!networkKeysMatch("ssid:Home Wi-Fi", fallback.key), "ssid is not a fallback key");

    ProfileBook book;
    std::string error;
    bool replaced = false;
    expect(book.upsertByName(makeProfile("Home Wi-Fi", "ssid:Home Wi-Fi", DisplayIntent::CouchTv), &error, &replaced), "save home");
    expect(!replaced && book.all().size() == 1 && book.all()[0].id == "p1", "first id");

    Profile updated = makeProfile("home wi-fi", "ssid:Home Wi-Fi", DisplayIntent::DeskMonitor);
    updated.stream.bitrateKbps = 40000;
    updated.stream.width = 2560;
    updated.stream.height = 1440;
    expect(book.upsertByName(updated, &error, &replaced), "update home");
    expect(replaced && book.all().size() == 1 && book.all()[0].id == "p1", "update keeps id");
    expect(book.all()[0].name == "home wi-fi" && book.all()[0].stream.bitrateKbps == 40000, "update stores new settings");
    expect(book.all()[0].displayIntent == DisplayIntent::DeskMonitor, "update stores intent");

    expect(book.upsertByName(makeProfile("Work", "ssid:Work", DisplayIntent::DeskMonitor), &error, &replaced), "save work");
    expect(!replaced && book.all().size() == 2 && book.all()[1].id == "p2", "second id");
    expect(book.uniqueName("Home Wi-Fi") == "Home Wi-Fi 2", "suggested name avoids collision");

    std::string blob = book.serialize();
    ProfileBook restored;
    expect(restored.deserialize(blob), "round trip");
    expect(restored.all().size() == 2, "round trip count");
    expect(restored.all()[0].id == "p1" && restored.all()[0].stream.width == 2560, "round trip picture");
    expect(restored.all()[0].stream.framePacing == false && restored.all()[0].stream.enableVsync, "round trip flags");
    expect(restored.upsertByName(makeProfile("Hotspot", "", DisplayIntent::BatterySaver), &error, &replaced), "id continues");
    expect(restored.all()[2].id == "p3", "next id after load");

    Profile special = makeProfile("Cafe", std::string("ssid:a\nb\x1f\\c"), DisplayIntent::Custom);
    special.networkLabel = "a\rlabel";
    special.bindingKind = BindingKind::Ssid;
    ProfileBook specialBook;
    expect(specialBook.upsertByName(special, &error, &replaced), "save special");
    ProfileBook specialRestored;
    expect(specialRestored.deserialize(specialBook.serialize()), "special round trip");
    expect(specialRestored.all().size() == 1, "special count");
    expect(specialRestored.all()[0].networkKey == special.networkKey, "special key");
    expect(specialRestored.all()[0].networkLabel == special.networkLabel, "special label");

    expect(!book.deserialize("not-a-profile-blob"), "reject unknown version");
    expect(book.all().size() == 2, "failed load keeps profiles");
    expect(!book.deserialize("twilight-net-profiles/1\nbad line\n"), "reject short row");
    expect(book.all().size() == 2, "failed row keeps profiles");

    std::string removed;
    expect(book.remove("p2", &removed) && removed == "Work", "delete work");
    expect(book.all().size() == 1 && book.find("p2") == 0 && book.find("p1") != 0, "delete leaves home");
    expect(!book.remove("p2", &removed), "delete missing");

    std::vector<const Profile*> matches = book.matching("ssid:HOME WI-FI");
    expect(matches.size() == 1 && matches[0]->id == "p1", "match current ssid");
    expect(book.matching("ssid:Other").empty(), "no match on another network");

    Profile invalid = makeProfile("Tiny", "ssid:Tiny", DisplayIntent::Custom);
    invalid.stream.width = 10;
    expect(!book.upsertByName(invalid, &error, &replaced), "reject tiny resolution");
    expect(error.find("outside the range") != std::string::npos, "range error");

    ProfileBook full;
    for (int i = 0; i < 32; i++) {
        char name[16];
        std::snprintf(name, sizeof(name), "N%d", i);
        expect(full.upsertByName(makeProfile(name, "", DisplayIntent::Custom), &error, &replaced), "fill book");
    }
    expect(!full.upsertByName(makeProfile("One more", "", DisplayIntent::Custom), &error, &replaced), "cap at 32");

    if (g_Failures != 0) {
        std::printf("%d network profile tests failed\n", g_Failures);
        return 1;
    }
    std::printf("network profile tests passed\n");
    return 0;
}
