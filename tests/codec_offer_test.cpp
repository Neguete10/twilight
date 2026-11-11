#include "streaming/codec_offer.h"

#include <cstdio>
#include <map>

static int g_Failures = 0;

static void expect(bool condition, const char* label)
{
    if (!condition) {
        std::printf("FAIL %s\n", label);
        g_Failures++;
    }
}

static std::vector<int> offer(const CodecOffer::Request& request, const std::map<int, int>& probes, int* calls = nullptr)
{
    return CodecOffer::build(request, [&](int format) {
        if (calls) {
            *calls += 1;
        }
        const auto found = probes.find(format);
        return found == probes.end() ? CodecOffer::DecodeNone : found->second;
    });
}

static CodecOffer::Request macSdr()
{
    CodecOffer::Request request;
    request.sdrDeprioritizesAv1 = true;
    request.darwin = true;
    return request;
}

int main()
{
    {
        const std::vector<int> formats = offer(macSdr(), {{CodecOffer::H265, CodecOffer::DecodeHardware}});
        expect(!formats.empty() && formats.front() == CodecOffer::H265, "HEVC hardware on a Mac keeps HEVC first");
        expect(!CodecOffer::containsMask(formats, CodecOffer::MaskPyroWave), "Automatic does not offer PyroWave");
        expect(CodecOffer::containsMask(formats, CodecOffer::Av1Main8), "AV1 remains as a lower priority");
    }

    {
        CodecOffer::Request request = macSdr();
        request.hdr = true;
        const std::vector<int> formats = offer(request, {
            {CodecOffer::H265Main10, CodecOffer::DecodeNone},
            {CodecOffer::Av1Main10, CodecOffer::DecodeHardware},
        });
        expect(!formats.empty() && formats.front() == CodecOffer::Av1Main10, "HDR without HEVC hardware keeps 10-bit AV1 first");
        expect(!CodecOffer::containsMask(formats, CodecOffer::MaskPyroWave), "HDR Automatic still excludes PyroWave");
    }

    {
        CodecOffer::Request request;
        request.codec = CodecOffer::ForceH264;
        const std::vector<int> formats = offer(request, {});
        expect(formats.size() == 1 && formats.front() == CodecOffer::H264, "H.264 forces the 8-bit 4:2:0 profile");
    }

    {
        CodecOffer::Request request;
        request.codec = CodecOffer::ForceAv1;
        const std::vector<int> formats = offer(request, {});
        expect(!formats.empty() && formats.front() == CodecOffer::Av1Main8, "AV1 forces AV1 ahead of the HEVC fallback");
        expect(!CodecOffer::containsMask(formats, CodecOffer::MaskH264), "AV1 does not fall through to H.264 in the offer");
        expect(!CodecOffer::containsMask(formats, CodecOffer::MaskPyroWave), "AV1 does not offer PyroWave");
    }

    {
        CodecOffer::Request request;
        request.codec = CodecOffer::ForceHevc;
        request.hdr = true;
        const std::vector<int> formats = offer(request, {});
        expect(!formats.empty() && formats.front() == CodecOffer::H265Main10, "HEVC with HDR prefers Main10");
        expect(!CodecOffer::containsMask(formats, CodecOffer::MaskAv1), "forced HEVC drops AV1");
    }

    {
        CodecOffer::Request request;
        request.codec = CodecOffer::ForcePyroWave;
        const std::vector<int> formats = offer(request, {});
        expect(formats.size() == 1 && formats.front() == CodecOffer::PyroWave, "PyroWave SDR 4:2:0 is the 8-bit profile");
    }

    {
        CodecOffer::Request request;
        request.codec = CodecOffer::ForcePyroWave;
        request.hdr = true;
        request.yuv444 = true;
        const std::vector<int> formats = offer(request, {});
        expect(!formats.empty() && formats.front() == CodecOffer::PyroWave10_444, "PyroWave HDR 4:4:4 stays first");
    }

    {
        CodecOffer::Request request = macSdr();
        request.oldGfe = true;
        const std::vector<int> formats = offer(request, {{CodecOffer::H265, CodecOffer::DecodeHardware}});
        expect(!CodecOffer::containsMask(formats, CodecOffer::MaskH265), "old GFE on macOS drops HEVC");
        expect(!formats.empty() && formats.front() == CodecOffer::H264, "old GFE falls through to H.264");
    }

    {
        int calls = 0;
        CodecOffer::Request request;
        request.codec = CodecOffer::ForceH264;
        offer(request, {}, &calls);
        expect(calls == 0, "a forced codec does not probe decoders");
    }

    {
        CodecOffer::Request request;
        request.hdr = true;
        request.forceSoftware = true;
        request.sdrDeprioritizesAv1 = true;
        const std::vector<int> formats = offer(request, {{CodecOffer::H265Main10, CodecOffer::DecodeSoftware}});
        expect(CodecOffer::containsMask(formats, CodecOffer::H265Main10), "forced software HDR keeps HEVC in the offer");
    }

    if (g_Failures != 0) {
        std::printf("%d failure(s)\n", g_Failures);
        return 1;
    }
    std::printf("ok\n");
    return 0;
}
