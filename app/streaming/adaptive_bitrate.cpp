#include "adaptive_bitrate_worker.h"

#include "adaptive_bitrate.h"
#include "stats.h"
#include "backend/nvhttp.h"

#include <Limelight.h>

#include <QDebug>
#include <QThread>

#include <chrono>

namespace {

int64_t steadyNowMs()
{
    return std::chrono::duration_cast<std::chrono::milliseconds>(
                std::chrono::steady_clock::now().time_since_epoch()).count();
}

}

AdaptiveBitrateThread::AdaptiveBitrateThread(NvComputer* computer,
                                             int ceilingWireKbps,
                                             int audioKbps,
                                             std::atomic<bool>* poorConnection,
                                             std::atomic<bool>* poorConnectionEdge)
    : m_Computer(computer),
      m_CeilingWireKbps(ceilingWireKbps),
      m_AudioKbps(audioKbps),
      m_PoorConnection(poorConnection),
      m_PoorConnectionEdge(poorConnectionEdge),
      m_Stop(false)
{
}

void AdaptiveBitrateThread::requestStop()
{
    m_Stop.store(true, std::memory_order_relaxed);
}

void AdaptiveBitrateThread::run()
{
    // This thread is neither the video renderer nor the SDL input loop.
    NvHTTP http(m_Computer);
    NvHTTP::AbrCapabilities caps;
    try {
        caps = http.getAbrCapabilities();
    } catch (const GfeHttpResponseException& e) {
        qInfo() << "Adaptive bitrate: capability check failed:" << e.toQString()
                << "- leaving the stream bitrate alone";
        return;
    } catch (const QtNetworkReplyException& e) {
        qInfo() << "Adaptive bitrate: capability check failed:" << e.toQString()
                << "- leaving the stream bitrate alone";
        return;
    }

    if (!caps.runtimeBitrate) {
        qInfo() << "Adaptive bitrate: host does not list runtime_bitrate; leaving the stream bitrate alone";
        return;
    }

    AdaptiveBitrate::Controller controller(m_CeilingWireKbps, m_AudioKbps);
    AdaptiveBitrate::setOverlayTargetKbps(controller.wireKbps());
    qInfo() << "Adaptive bitrate: host allows runtime changes, ceiling"
            << controller.ceilingKbps() << "kbps";

    AdaptiveBitrate::Observation baseline{};
    baseline.nowMs = steadyNowMs();
    Stats::instance().abrFrameTotals(&baseline.totalFrames, &baseline.networkDroppedFrames);
    if (const RTP_VIDEO_STATS* rtp = LiGetRTPVideoStats()) {
        baseline.fecFailures = rtp->packetCountFecFailed;
    }
    uint32_t baselineRtt = 0;
    uint32_t baselineVariance = 0;
    baseline.rttKnown = LiGetEstimatedRttInfo(&baselineRtt, &baselineVariance);
    baseline.rttMs = baselineRtt;
    baseline.rttVarianceMs = baselineVariance;
    controller.prime(baseline);

    while (!m_Stop.load(std::memory_order_relaxed)) {
        for (int step = 0; step < 15 && !m_Stop.load(std::memory_order_relaxed); ++step) {
            QThread::msleep(100);
        }
        if (m_Stop.load(std::memory_order_relaxed)) {
            break;
        }

        AdaptiveBitrate::Observation obs{};
        obs.nowMs = steadyNowMs();
        uint32_t frames = 0;
        uint32_t dropped = 0;
        Stats::instance().abrFrameTotals(&frames, &dropped);
        obs.totalFrames = frames;
        obs.networkDroppedFrames = dropped;
        if (const RTP_VIDEO_STATS* rtp = LiGetRTPVideoStats()) {
            obs.fecFailures = rtp->packetCountFecFailed;
        }
        uint32_t rtt = 0;
        uint32_t variance = 0;
        obs.rttKnown = LiGetEstimatedRttInfo(&rtt, &variance);
        obs.rttMs = rtt;
        obs.rttVarianceMs = variance;
        const bool poorNow = m_PoorConnection != nullptr && m_PoorConnection->load(std::memory_order_relaxed);
        const bool poorEdge = m_PoorConnectionEdge != nullptr && m_PoorConnectionEdge->exchange(false, std::memory_order_relaxed);
        obs.poorConnection = poorNow || poorEdge;

        const AdaptiveBitrate::Decision decision = controller.tick(obs);
        AdaptiveBitrate::setOverlayTargetKbps(decision.wireKbps);
        if (!decision.send) {
            continue;
        }

        try {
            const int applied = http.setBitrate(decision.encoderKbps);
            qInfo() << "Adaptive bitrate:"
                    << (decision.action == AdaptiveBitrate::Action::Cut ? "cut" : "raise")
                    << "wire" << decision.wireKbps
                    << "kbps, encoder request" << decision.encoderKbps
                    << "kbps, host applied" << applied;
        } catch (const GfeHttpResponseException& e) {
            qWarning() << "Adaptive bitrate: host rejected the change:" << e.toQString();
        } catch (const QtNetworkReplyException& e) {
            qWarning() << "Adaptive bitrate: request failed:" << e.toQString();
        }
    }

    AdaptiveBitrate::setOverlayTargetKbps(0);
}
