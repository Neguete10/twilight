#pragma once

// Automatic video codec policy for Twilight.
//
// PyroWave is never offered. It remains an explicit selection
// (VCC_FORCE_PYROWAVE). The host's supported set is applied later by
// dropping families it does not advertise; this order is what remains.
//
// Hardware AV1 (Apple silicon M3 and later, via the decoder probe) stays
// ahead of HEVC and H.264. Without it, HEVC is next when that decoder is
// hardware, otherwise H.264. Software AV1 is never preferred over those.

enum AutoCodecFamily
{
    AutoCodecAv1 = 1,
    AutoCodecHevc = 2,
    AutoCodecH264 = 3,
};

inline bool automaticOffersPyroWave()
{
    return false;
}

// True when Automatic should move every AV1 profile behind the other
// codecs. Hardware AV1 keeps its place at the front of the list.
inline bool automaticDeprioritizesAv1(bool av1Hardware)
{
    return !av1Hardware;
}

// Family order after the same deprioritize steps Session::initialize()
// applies for VCC_AUTO. `keepHevcDespiteNoHardware` is the existing HDR +
// forced-software exception: H.264 cannot carry 10-bit, so HEVC stays up.
inline void automaticCodecPriority(bool av1Hardware,
                                   bool hevcHardware,
                                   bool keepHevcDespiteNoHardware,
                                   int out[3])
{
    int list[3] = { AutoCodecAv1, AutoCodecHevc, AutoCodecH264 };

    auto deprioritize = [&](int family) {
        int kept[3];
        int dep[3];
        int keptCount = 0;
        int depCount = 0;
        for (int i = 0; i < 3; i++) {
            if (list[i] == family) {
                dep[depCount++] = list[i];
            }
            else {
                kept[keptCount++] = list[i];
            }
        }
        int n = 0;
        for (int i = 0; i < keptCount; i++) {
            list[n++] = kept[i];
        }
        for (int i = 0; i < depCount; i++) {
            list[n++] = dep[i];
        }
    };

    if (!hevcHardware && !keepHevcDespiteNoHardware) {
        deprioritize(AutoCodecHevc);
    }
    if (automaticDeprioritizesAv1(av1Hardware)) {
        deprioritize(AutoCodecAv1);
    }

    out[0] = list[0];
    out[1] = list[1];
    out[2] = list[2];
}
