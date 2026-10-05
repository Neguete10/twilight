#include "updateversion.h"

#include <cctype>

namespace {

std::string trimSpace(const std::string& text)
{
    std::size_t begin = 0;
    while (begin < text.size() && (text[begin] == ' ' || text[begin] == '\t'))
        begin++;

    std::size_t end = text.size();
    while (end > begin && (text[end - 1] == ' ' || text[end - 1] == '\t'))
        end--;

    return text.substr(begin, end - begin);
}

std::string lowerCopy(const std::string& text)
{
    std::string out = text;
    for (std::size_t i = 0; i < out.size(); i++)
        out[i] = static_cast<char>(std::tolower(static_cast<unsigned char>(out[i])));
    return out;
}

bool endsWithDmg(const std::string& name)
{
    if (name.size() < 4)
        return false;
    return lowerCopy(name.substr(name.size() - 4)) == ".dmg";
}

bool containsToken(const std::string& lowerName, const char* token)
{
    return lowerName.find(token) != std::string::npos;
}

// 0 generic, 1 Apple silicon, 2 Intel, 3 universal.
int imageArch(const std::string& lowerName)
{
    if (containsToken(lowerName, "universal"))
        return 3;

    const bool arm = containsToken(lowerName, "arm64") || containsToken(lowerName, "aarch64");
    const bool intel = containsToken(lowerName, "x86_64") ||
                       containsToken(lowerName, "amd64") ||
                       containsToken(lowerName, "x64") ||
                       containsToken(lowerName, "intel");
    if (arm && !intel)
        return 1;
    if (intel && !arm)
        return 2;
    return 0;
}

int wantedArch(const std::string& cpuArch)
{
    const std::string arch = lowerCopy(cpuArch);
    if (arch == "arm64" || arch == "aarch64")
        return 1;
    if (arch == "x86_64" || arch == "amd64" || arch == "i386")
        return 2;
    return 0;
}

int imageScore(int kind, int want)
{
    if (kind == want && want != 0)
        return 4;
    if (kind == 3)
        return 3;
    if (kind == 0)
        return 2;
    return 0;
}

} // namespace

bool parseVersionQuad(const std::string& text, std::vector<int>& version)
{
    version.clear();

    std::string value = trimSpace(text);
    if (!value.empty() && (value[0] == 'v' || value[0] == 'V'))
        value.erase(0, 1);
    if (value.empty())
        return false;

    std::size_t index = 0;
    while (index < value.size()) {
        if (value[index] < '0' || value[index] > '9')
            return false;

        int component = 0;
        while (index < value.size() && value[index] >= '0' && value[index] <= '9') {
            component = component * 10 + (value[index] - '0');
            index++;
        }
        version.push_back(component);

        if (index == value.size())
            return true;
        if (value[index] != '.')
            return false;
        index++;
        if (index == value.size())
            return false;
    }

    return false;
}

int compareVersionQuad(const std::vector<int>& left, const std::vector<int>& right)
{
    for (std::size_t i = 0;; i++) {
        if (i >= left.size() && i >= right.size())
            return 0;

        const int leftValue = i < left.size() ? left[i] : 0;
        const int rightValue = i < right.size() ? right[i] : 0;
        if (leftValue < rightValue)
            return -1;
        if (leftValue > rightValue)
            return 1;
    }
}

int newerRelease(const std::string& currentVersion, const std::string& tag)
{
    std::vector<int> current;
    std::vector<int> latest;
    if (!parseVersionQuad(currentVersion, current) || !parseVersionQuad(tag, latest))
        return -1;
    return compareVersionQuad(current, latest) < 0 ? 1 : 0;
}

bool isTrustedTwilightReleaseUrl(const std::string& url)
{
    static const char prefix[] = "https://github.com/Neguete10/twilight/releases";
    const std::size_t prefixLength = sizeof(prefix) - 1;
    if (url.size() < prefixLength || url.compare(0, prefixLength, prefix) != 0)
        return false;
    if (url.size() > prefixLength) {
        const char next = url[prefixLength];
        if (next != '/' && next != '?' && next != '#')
            return false;
    }
    if (url.find('@') != std::string::npos ||
            url.find('\\') != std::string::npos ||
            url.find(' ') != std::string::npos ||
            url.find('\n') != std::string::npos ||
            url.find('\r') != std::string::npos) {
        return false;
    }
    return true;
}

std::string selectDmgDownloadUrl(const std::vector<std::string>& names,
                                 const std::vector<std::string>& urls,
                                 const std::string& cpuArch)
{
    const std::size_t count = names.size() < urls.size() ? names.size() : urls.size();
    const int want = wantedArch(cpuArch);
    std::string bestUrl;
    int bestScore = 0;

    for (std::size_t i = 0; i < count; i++) {
        if (!endsWithDmg(names[i]) || !isTrustedTwilightReleaseUrl(urls[i]))
            continue;

        const int score = imageScore(imageArch(lowerCopy(names[i])), want);
        if (score > bestScore) {
            bestScore = score;
            bestUrl = urls[i];
        }
    }

    return bestUrl;
}

std::string trimReleaseNotes(const std::string& body, std::size_t maxLen)
{
    std::string cleaned;
    cleaned.reserve(body.size());

    for (std::size_t i = 0; i < body.size(); i++) {
        const unsigned char c = static_cast<unsigned char>(body[i]);
        if (c == '\r')
            continue;
        if (c == '\n') {
            if (!cleaned.empty() && cleaned.back() != '\n')
                cleaned.push_back('\n');
            continue;
        }
        if (c == ' ' || c == '\t') {
            if (cleaned.empty() || cleaned.back() == '\n' || cleaned.back() == ' ')
                continue;
            cleaned.push_back(' ');
            continue;
        }
        cleaned.push_back(static_cast<char>(c));
    }

    while (!cleaned.empty() && (cleaned.back() == '\n' || cleaned.back() == ' '))
        cleaned.pop_back();

    if (maxLen == 0 || cleaned.size() <= maxLen)
        return cleaned;

    std::size_t cut = maxLen;
    while (cut > 0 && (static_cast<unsigned char>(cleaned[cut]) & 0xC0) == 0x80)
        cut--;

    const std::size_t space = cleaned.rfind(' ', cut);
    if (space != std::string::npos && space > cut / 2)
        cut = space;
    if (cut == 0)
        cut = maxLen;

    cleaned.resize(cut);
    while (!cleaned.empty() && (cleaned.back() == ' ' || cleaned.back() == '\n'))
        cleaned.pop_back();
    cleaned += "...";
    return cleaned;
}
