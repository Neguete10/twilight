#pragma once

#include <cstdint>
#include <vector>

// Downmix to mono and linearly resample to 48 kHz. Voice capture does not
// need a production sample-rate converter. The first emitted sample equals
// the first input sample. Later samples are linear interpolations.

inline float micDownmix(const float* const* planar, int channels, int frameIndex)
{
    float sum = 0.f;
    for (int channel = 0; channel < channels; channel++) {
        sum += planar[channel][frameIndex];
    }
    return channels > 0 ? sum / (float)channels : 0.f;
}

inline int16_t micFloatToS16(float sample)
{
    if (sample > 1.f) {
        sample = 1.f;
    }
    if (sample < -1.f) {
        sample = -1.f;
    }
    const float scaled = sample * 32767.f;
    const int rounded = (int)(scaled + (scaled >= 0.f ? 0.5f : -0.5f));
    if (rounded > 32767) {
        return 32767;
    }
    if (rounded < -32768) {
        return -32768;
    }
    return (int16_t)rounded;
}

class MicResampler
{
public:
    MicResampler()
        : m_Step(0.0),
          m_Cursor(0.0),
          m_Last(0.f),
          m_Primed(false)
    {
    }

    void reset(double sourceRateHz)
    {
        m_Step = sourceRateHz > 0.0 ? sourceRateHz / 48000.0 : 0.0;
        m_Cursor = 0.0;
        m_Last = 0.f;
        m_Primed = false;
    }

    // planar is channel-major: planar[channel][frame].
    void process(const float* const* planar, int channels, int frames, std::vector<int16_t>& out)
    {
        if (m_Step <= 0.0 || planar == nullptr || channels < 1 || frames < 1) {
            return;
        }

        for (int frame = 0; frame < frames; frame++) {
            push(micDownmix(planar, channels, frame), out);
        }
    }

private:
    void push(float sample, std::vector<int16_t>& out)
    {
        if (!m_Primed) {
            out.push_back(micFloatToS16(sample));
            m_Last = sample;
            m_Cursor = m_Step;
            m_Primed = true;
            return;
        }

        // sample sits one input period after m_Last. Emit every output
        // whose input-time falls inside this period, then carry the
        // fractional remainder forward.
        while (m_Cursor <= 1.0) {
            const float mixed = m_Last + (sample - m_Last) * (float)m_Cursor;
            out.push_back(micFloatToS16(mixed));
            m_Cursor += m_Step;
        }
        m_Cursor -= 1.0;
        m_Last = sample;
    }

    double m_Step;
    double m_Cursor;
    float m_Last;
    bool m_Primed;
};
