#pragma once

#include <cstddef>
#include <string>
#include <vector>

// Version and download-link decisions for AutoUpdateChecker.
// Twilight does not install an update here. A newer GitHub release is
// only an offer: the app opens a trusted release URL after the user agrees.

// "v7.0.0" and "7.0.0" become {7, 0, 0}. A missing number, a leading
// empty component, or a non-numeric suffix is rejected.
bool parseVersionQuad(const std::string& text, std::vector<int>& version);

// Missing components compare as 0. Returns -1, 0, or 1.
int compareVersionQuad(const std::vector<int>& left, const std::vector<int>& right);

// 1 when tag is a newer numeric release, 0 when it is the same or older,
// -1 when either string is not a version.
int newerRelease(const std::string& currentVersion, const std::string& tag);

// True for https://github.com/Neguete10/twilight/releases and paths under it.
bool isTrustedTwilightReleaseUrl(const std::string& url);

// Picks one https disk-image URL. A name with no architecture token, such as
// Twilight-7.0.0.dmg, matches every Mac. A wrong-architecture image is skipped
// when another image matches. Empty when nothing qualifies.
std::string selectDmgDownloadUrl(const std::vector<std::string>& names,
                                 const std::vector<std::string>& urls,
                                 const std::string& cpuArch);

// Collapses blank lines and caps the length on a UTF-8 boundary.
std::string trimReleaseNotes(const std::string& body, std::size_t maxLen);
