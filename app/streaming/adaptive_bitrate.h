#pragma once

#include <atomic>
#include <cstdint>
#include <string>

// Client-side adaptive bitrate. The host's /bitrate endpoint writes the
// encoder rate directly, so the value we send is about wire * 0.8 - audio - 500.
// This header does not call the network. A worker thread does that.

namespace AdaptiveBitrate {

constexpr int kFloorKbps = 5000;
constexpr int kHostEndpointCapKbps = 500000;
constexpr int kMinChangeIntervalMs = 1000;
constexpr int kCleanRaiseMs = 10000;
constexpr double kLossCut = 0.02;
constexpr double kLossClean = 0.005;
constexpr double kCutFactor = 0.70;
constexpr double kRaiseFactor = 1.05;
constexpr int kAudioCushionKbps = 500;

// Unlimited is capped by the host endpoint. A typed bitrate is capped there too.
inline int wireCeilingKbps(bool unlimited, int requestedWireKbps)
{
    if (unlimited || requestedWireKbps > kHostEndpointCapKbps) {
        return kHostEndpointCapKbps;
    }
    if (requestedWireKbps < 1) {
        return 1;
    }
    return requestedWireKbps;
}

inline int floorForCeiling(int ceilingKbps)
{
    if (ceilingKbps < kFloorKbps) {
        return ceilingKbps;
    }
    return kFloorKbps;
}

// GFE uses 512 kbps stereo on a local link and 96 kbps stereo remotely.
// Extra channels scale from that stereo pair.
inline int assumedAudioKbps(int channelCount, bool lan)
{
    if (channelCount < 1) {
        channelCount = 2;
    }
    const int stereo = lan ? 512 : 96;
    return stereo * ((channelCount + 1) / 2);
}

// Encoder kbps for /bitrate. The endpoint does not subtract FEC itself.
inline int encoderKbpsForWire(int wireKbps, int audioKbps)
{
    const double raw = static_cast<double>(wireKbps) * 0.80
            - static_cast<double>(audioKbps)
            - static_cast<double>(kAudioCushionKbps);
    int kbps = static_cast<int>(raw);
    if (kbps < 1) {
        kbps = 1;
    }
    if (kbps > kHostEndpointCapKbps) {
        kbps = kHostEndpointCapKbps;
    }
    return kbps;
}

// supported:false is normal. The feature name is what lets the client drive /bitrate.
inline bool hostOffersRuntimeBitrate(const std::string& json)
{
    return json.find("\"runtime_bitrate\"") != std::string::npos;
}

inline bool rttIsSpike(uint32_t rttMs, uint32_t varianceMs, uint32_t baselineMs, bool haveBaseline)
{
    if (!haveBaseline || baselineMs == 0) {
        return false;
    }
    if (rttMs > 0 && varianceMs > rttMs) {
        return true;
    }
    if (rttMs > baselineMs + 30 && rttMs * 2 > baselineMs * 3) {
        return true;
    }
    return false;
}

enum class Action {
    Hold,
    Cut,
    Raise,
};

struct Observation {
    int64_t nowMs;
    uint32_t totalFrames;
    uint32_t networkDroppedFrames;
    uint32_t fecFailures;
    bool rttKnown;
    uint32_t rttMs;
    uint32_t rttVarianceMs;
    bool poorConnection;
};

struct Decision {
    Action action;
    bool send;
    int wireKbps;
    int encoderKbps;
};

class Controller {
public:
    Controller(int ceilingWireKbps, int audioKbps)
        : m_Ceiling(ceilingWireKbps < 1 ? 1 : ceilingWireKbps),
          m_Floor(floorForCeiling(m_Ceiling)),
          m_Wire(m_Ceiling),
          m_Audio(audioKbps < 0 ? 0 : audioKbps),
          m_LastChangeMs(-1000000),
          m_CleanSinceMs(-1),
          // The first accepted sample is measured against zero, so loss during
          // the opening interval is not discarded as a baseline.
          m_HavePrev(true),
          m_PrevFrames(0),
          m_PrevDropped(0),
          m_PrevFec(0),
          m_PrevMs(-1000000),
          m_HaveRttBaseline(false),
          m_RttBaseline(0)
    {
    }

    int wireKbps() const { return m_Wire; }
    int ceilingKbps() const { return m_Ceiling; }
    int floorKbps() const { return m_Floor; }

    // Remember the counters already on the books so an earlier stream in this
    // process is not treated as loss. Does not change the bitrate.
    void prime(const Observation& obs)
    {
        m_HavePrev = true;
        m_PrevFrames = obs.totalFrames;
        m_PrevDropped = obs.networkDroppedFrames;
        m_PrevFec = obs.fecFailures;
        m_PrevMs = obs.nowMs;
        if (obs.rttKnown && obs.rttMs > 0) {
            m_HaveRttBaseline = true;
            m_RttBaseline = obs.rttMs;
        }
    }

    Decision tick(const Observation& obs)
    {
        Decision held{Action::Hold, false, m_Wire, encoderKbpsForWire(m_Wire, m_Audio)};
        if (m_HavePrev && obs.nowMs < m_PrevMs) {
            return held;
        }
        if (m_HavePrev && obs.nowMs - m_PrevMs < kMinChangeIntervalMs) {
            return held;
        }

        uint32_t frameDelta = 0;
        uint32_t droppedDelta = 0;
        uint32_t fecDelta = 0;
        if (m_HavePrev) {
            frameDelta = obs.totalFrames - m_PrevFrames;
            droppedDelta = obs.networkDroppedFrames - m_PrevDropped;
            fecDelta = obs.fecFailures - m_PrevFec;
        }

        const bool haveInterval = m_HavePrev;
        m_HavePrev = true;
        m_PrevFrames = obs.totalFrames;
        m_PrevDropped = obs.networkDroppedFrames;
        m_PrevFec = obs.fecFailures;
        m_PrevMs = obs.nowMs;

        if (!haveInterval) {
            if (obs.rttKnown && obs.rttMs > 0) {
                m_HaveRttBaseline = true;
                m_RttBaseline = obs.rttMs;
            }
            return held;
        }

        const bool fecBad = fecDelta > 0;
        const bool haveLoss = frameDelta > 0;
        double loss = 0.0;
        if (haveLoss) {
            loss = static_cast<double>(droppedDelta) / static_cast<double>(frameDelta);
            if (loss > 1.0) {
                loss = 1.0;
            }
        }
        const bool lossCut = haveLoss && loss > kLossCut;
        const bool rttBad = obs.rttKnown && rttIsSpike(obs.rttMs, obs.rttVarianceMs, m_RttBaseline, m_HaveRttBaseline);
        if (obs.rttKnown && obs.rttMs > 0 && !rttBad) {
            if (!m_HaveRttBaseline || obs.rttMs < m_RttBaseline) {
                m_RttBaseline = obs.rttMs;
                m_HaveRttBaseline = true;
            }
        }

        const bool shouldCut = lossCut || fecBad || rttBad || obs.poorConnection;
        const bool clean = !obs.poorConnection && !fecBad && !rttBad && haveLoss && loss <= kLossClean;
        const bool canChange = obs.nowMs - m_LastChangeMs >= kMinChangeIntervalMs;

        if (shouldCut && canChange && m_Wire > m_Floor) {
            int next = static_cast<int>(static_cast<double>(m_Wire) * kCutFactor);
            if (next >= m_Wire) {
                next = m_Wire - 1;
            }
            if (next < m_Floor) {
                next = m_Floor;
            }
            m_Wire = next;
            m_LastChangeMs = obs.nowMs;
            m_CleanSinceMs = -1;
            return Decision{Action::Cut, true, m_Wire, encoderKbpsForWire(m_Wire, m_Audio)};
        }

        if (!clean) {
            m_CleanSinceMs = -1;
            return held;
        }
        if (m_CleanSinceMs < 0) {
            m_CleanSinceMs = obs.nowMs;
            return held;
        }
        if (obs.nowMs - m_CleanSinceMs >= kCleanRaiseMs && canChange && m_Wire < m_Ceiling) {
            int next = static_cast<int>(static_cast<double>(m_Wire) * kRaiseFactor);
            if (next <= m_Wire) {
                next = m_Wire + 1;
            }
            if (next > m_Ceiling) {
                next = m_Ceiling;
            }
            m_Wire = next;
            m_LastChangeMs = obs.nowMs;
            m_CleanSinceMs = obs.nowMs;
            return Decision{Action::Raise, true, m_Wire, encoderKbpsForWire(m_Wire, m_Audio)};
        }
        return held;
    }

private:
    int m_Ceiling;
    int m_Floor;
    int m_Wire;
    int m_Audio;
    int64_t m_LastChangeMs;
    int64_t m_CleanSinceMs;
    bool m_HavePrev;
    uint32_t m_PrevFrames;
    uint32_t m_PrevDropped;
    uint32_t m_PrevFec;
    int64_t m_PrevMs;
    bool m_HaveRttBaseline;
    uint32_t m_RttBaseline;
};

// 0 hides the adaptive figure on the overlay.
inline std::atomic<int>& overlayTargetSlot()
{
    static std::atomic<int> value{0};
    return value;
}

inline void setOverlayTargetKbps(int kbps)
{
    overlayTargetSlot().store(kbps, std::memory_order_relaxed);
}

inline int overlayTargetKbps()
{
    const int value = overlayTargetSlot().load(std::memory_order_relaxed);
    return value > 0 ? value : 0;
}

} // namespace AdaptiveBitrate
