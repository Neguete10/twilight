#include "backend/updateversion.h"

#include <cstdio>
#include <string>
#include <vector>

static int g_Failures = 0;

static void expect(bool ok, const char* label)
{
    if (!ok) {
        std::printf("FAIL %s\n", label);
        g_Failures++;
    }
}

static std::vector<int> parsed(const char* text)
{
    std::vector<int> version;
    expect(parseVersionQuad(text, version), text);
    return version;
}

static void testParse()
{
    const std::vector<int> release = parsed("v7.0.0");
    expect(release.size() == 3 && release[0] == 7 && release[1] == 0 && release[2] == 0, "v7.0.0");

    const std::vector<int> plain = parsed("7.0.0");
    expect(compareVersionQuad(release, plain) == 0, "v prefix matches the numeric version");

    const std::vector<int> shortForm = parsed("7.0");
    expect(compareVersionQuad(shortForm, plain) == 0, "missing component is zero");

    std::vector<int> rejected;
    expect(!parseVersionQuad("", rejected), "empty is not a version");
    expect(!parseVersionQuad("nightly", rejected), "word is not a version");
    expect(!parseVersionQuad("v7.0.0-beta", rejected), "suffix is not a stable version");
    expect(!parseVersionQuad("7.", rejected), "trailing dot is not a version");
}

static void testOrder()
{
    expect(newerRelease("7.0.0", "v7.1.0") == 1, "7.1.0 is newer than 7.0.0");
    expect(newerRelease("7.0.0", "v7.0.0") == 0, "the same release is not an update");
    expect(newerRelease("7.2.0", "v7.1.0") == 0, "a newer local build is not offered a downgrade");
    expect(newerRelease("7.0.9", "v7.0.10") == 1, "10 is newer than 9");
    expect(newerRelease("7.0.0", "nightly") == -1, "unreadable tag is not an update");
}

static void testDownloadChoice()
{
    const std::string dmg = "https://github.com/Neguete10/twilight/releases/download/v7.0.0/Twilight-7.0.0.dmg";
    const std::string arm = "https://github.com/Neguete10/twilight/releases/download/v7.1.0/Twilight-7.1.0-arm64.dmg";
    const std::string intel = "https://github.com/Neguete10/twilight/releases/download/v7.1.0/Twilight-7.1.0-x86_64.dmg";
    const std::string zip = "https://github.com/Neguete10/twilight/releases/download/v7.0.0/Twilight-7.0.0.zip";
    const std::string otherRepo = "https://github.com/other/twilight/releases/download/v7.0.0/Twilight-7.0.0.dmg";
    const std::string insecure = "http://github.com/Neguete10/twilight/releases/download/v7.0.0/Twilight-7.0.0.dmg";

    expect(isTrustedTwilightReleaseUrl(dmg), "release asset url is trusted");
    expect(isTrustedTwilightReleaseUrl("https://github.com/Neguete10/twilight/releases/tag/v7.0.0"), "release page is trusted");
    expect(isTrustedTwilightReleaseUrl("https://github.com/Neguete10/twilight/releases"), "releases index is trusted");
    expect(!isTrustedTwilightReleaseUrl("https://github.com/Neguete10/twilight"), "repo home is not a release url");
    expect(!isTrustedTwilightReleaseUrl(otherRepo), "another repo is not trusted");
    expect(!isTrustedTwilightReleaseUrl(insecure), "http is not trusted");
    expect(!isTrustedTwilightReleaseUrl("https://user@github.com/Neguete10/twilight/releases/download/v7.0.0/Twilight-7.0.0.dmg"), "userinfo is not trusted");
    expect(!isTrustedTwilightReleaseUrl("https://github.com/Neguete10/twilight/releases.attacker.com/Twilight-7.0.0.dmg"), "lookalike host is not trusted");

    std::vector<std::string> names;
    names.push_back("Twilight-7.0.0.zip");
    names.push_back("Twilight-7.0.0.dmg");
    std::vector<std::string> urls;
    urls.push_back(zip);
    urls.push_back(dmg);
    expect(selectDmgDownloadUrl(names, urls, "arm64") == dmg, "the notarized disk image is chosen");

    names.clear();
    urls.clear();
    names.push_back("Twilight-7.1.0-x86_64.dmg");
    names.push_back("Twilight-7.1.0-arm64.dmg");
    urls.push_back(intel);
    urls.push_back(arm);
    expect(selectDmgDownloadUrl(names, urls, "arm64") == arm, "arm64 build picks the arm64 disk image");
    expect(selectDmgDownloadUrl(names, urls, "x86_64") == intel, "intel build picks the intel disk image");

    names.clear();
    urls.clear();
    names.push_back("Twilight-7.1.0-x86_64.dmg");
    urls.push_back(intel);
    expect(selectDmgDownloadUrl(names, urls, "arm64").empty(), "a mismatched disk image is not offered");

    names.clear();
    urls.clear();
    names.push_back("Twilight-7.0.0.dmg");
    urls.push_back(otherRepo);
    expect(selectDmgDownloadUrl(names, urls, "arm64").empty(), "an untrusted disk image is not offered");

    names.clear();
    urls.clear();
    names.push_back("Twilight-7.0.0.dmg");
    urls.push_back(insecure);
    expect(selectDmgDownloadUrl(names, urls, "arm64").empty(), "an http disk image is not offered");
}

static void testNotes()
{
    expect(trimReleaseNotes("  Hello\r\n\r\nthere  ", 80) == "Hello\nthere", "notes keep one break between lines");
    const std::string longNotes(400, 'a');
    const std::string trimmed = trimReleaseNotes(longNotes, 20);
    expect(trimmed.size() > 20 && trimmed.size() < 30 && trimmed.compare(trimmed.size() - 3, 3, "...") == 0, "long notes are capped");
}

int main()
{
    testParse();
    testOrder();
    testDownloadChoice();
    testNotes();

    if (g_Failures != 0) {
        std::printf("%d update version tests failed\n", g_Failures);
        return 1;
    }

    std::printf("update version tests passed\n");
    return 0;
}
