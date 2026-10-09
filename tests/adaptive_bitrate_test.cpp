#include "adaptive_bitrate.h"

#include <cstdio>
#include <string>

using namespace AdaptiveBitrate;

static int g_Failures = 0;

static void expect(bool condition, const char* label)
{
    if (!condition) {
        std::printf("FAIL %s\n", label);
        g_Failures++;
    }
}

static Observation at(int64_t nowMs, uint32_t frames, uint32_t dropped, uint32_t fec,
                      uint32_t rttMs, uint32_t varianceMs, bool poor)
{
    Observation obs{};
    obs.nowMs = nowMs;
    obs.totalFrames = frames;
    obs.networkDroppedFrames = dropped;
    obs.fecFailures = fec;
    obs.rttKnown = true;
    obs.rttMs = rttMs;
    obs.rttVarianceMs = varianceMs;
    obs.poorConnection = poor;
    return obs;
}

int main()
{
    expect(wireCeilingKbps(1000000) == 500000, "a 1 Gbps request is capped at the host endpoint");
    expect(wireCeilingKbps(20000) == 20000, "typed ceiling is the user bitrate");
    expect(wireCeilingKbps(800000) == 500000, "typed bitrate above the endpoint is capped");
    expect(wireCeilingKbps(0) == 1, "a zero request still has a positive ceiling");

    expect(assumedAudioKbps(2, true) == 512, "local stereo audio budget");
    expect(assumedAudioKbps(2, false) == 96, "remote stereo audio budget");
    expect(assumedAudioKbps(6, true) == 1536, "local 5.1 audio budget");
    expect(assumedAudioKbps(0, false) == 96, "missing channel count uses stereo");

    expect(encoderKbpsForWire(20000, 512) == 14988, "encoder request removes FEC, audio, and 500 kbps");
    expect(encoderKbpsForWire(1000000, 0) == 500000, "encoder request stops at the host cap");
    expect(encoderKbpsForWire(5000, 512) == 2988, "a low wire budget still sends a positive encoder rate");

    expect(hostOffersRuntimeBitrate("{\"supported\":false,\"version\":1,\"features\":[\"runtime_bitrate\"]}"),
           "supported false still offers runtime_bitrate");
    expect(!hostOffersRuntimeBitrate("{\"supported\":true,\"features\":[]}"), "empty features do not offer it");
    expect(!hostOffersRuntimeBitrate(""), "empty body does not offer it");
    expect(!hostOffersRuntimeBitrate("{\"features\":[\"other\"]}"), "a different feature is not enough");

    expect(!rttIsSpike(20, 1, 20, false), "the first RTT is not a spike");
    expect(rttIsSpike(80, 1, 20, true), "a jump well above the baseline is a spike");
    expect(rttIsSpike(40, 50, 40, true), "variance larger than the RTT is a spike");
    expect(!rttIsSpike(28, 2, 20, true), "a small rise is not a spike");

    {
        Controller controller(20000, 512);
        const Decision cut = controller.tick(at(0, 1000, 30, 0, 20, 1, false));
        expect(cut.action == Action::Cut && cut.send, "3 percent loss cuts");
        expect(cut.wireKbps == 14000, "cut is about 0.7x");
        expect(cut.encoderKbps == 10188, "cut sends the encoder rate, not the wire rate");

        const Decision ignored = controller.tick(at(500, 1100, 80, 0, 20, 1, false));
        expect(!ignored.send && ignored.wireKbps == 14000, "a second change inside one second is ignored");

        const Decision again = controller.tick(at(1000, 1200, 80, 0, 20, 1, false));
        expect(again.action == Action::Cut && again.wireKbps == 9800, "loss still present cuts again after one second");
    }

    {
        Controller controller(20000, 512);
        const Decision fec = controller.tick(at(0, 100, 0, 1, 20, 1, false));
        expect(fec.action == Action::Cut && fec.wireKbps == 14000, "an FEC failure cuts");
    }

    {
        Controller controller(20000, 512);
        const Decision baseline = controller.tick(at(0, 100, 0, 0, 20, 1, false));
        expect(!baseline.send && baseline.wireKbps == 20000, "a clean opening sample holds");
        const Decision spike = controller.tick(at(1500, 200, 0, 0, 80, 1, false));
        expect(spike.action == Action::Cut && spike.wireKbps == 14000, "an RTT spike cuts");
    }

    {
        Controller controller(20000, 512);
        const Decision poor = controller.tick(at(0, 100, 0, 0, 20, 1, true));
        expect(poor.action == Action::Cut && poor.wireKbps == 14000, "a poor-connection flag cuts");
    }

    {
        Controller controller(20000, 512);
        const Decision middle = controller.tick(at(0, 1000, 10, 0, 20, 1, false));
        expect(!middle.send && middle.wireKbps == 20000, "1 percent loss does not cut");
        const Decision still = controller.tick(at(12000, 2000, 20, 0, 20, 1, false));
        expect(!still.send && still.wireKbps == 20000, "loss between the thresholds does not raise");
    }

    {
        Controller controller(20000, 512);
        expect(controller.tick(at(0, 1000, 30, 0, 20, 1, false)).wireKbps == 14000, "cut before the raise window");
        expect(controller.tick(at(1500, 1100, 30, 0, 20, 1, false)).action == Action::Hold, "clean sample starts the raise timer");
        const Decision early = controller.tick(at(10500, 2000, 30, 0, 20, 1, false));
        expect(!early.send && early.wireKbps == 14000, "nine clean seconds do not raise");
        const Decision raised = controller.tick(at(11500, 3000, 30, 0, 20, 1, false));
        expect(raised.action == Action::Raise && raised.send, "ten clean seconds raise");
        expect(raised.wireKbps == 14700, "raise is about 5 percent");
        expect(raised.wireKbps < controller.ceilingKbps(), "raise stays under the user's bitrate");
    }

    {
        Controller controller(5200, 0);
        const Decision cut = controller.tick(at(0, 1000, 40, 0, 20, 1, false));
        expect(cut.wireKbps == 5000, "a cut stops at 5 Mb/s");
        expect(controller.tick(at(1500, 1100, 40, 0, 20, 1, false)).action == Action::Hold, "clean time starts after the cut");
        const Decision raised = controller.tick(at(11500, 2000, 40, 0, 20, 1, false));
        expect(raised.action == Action::Raise && raised.wireKbps == 5200, "a raise stops at the user's ceiling");
    }

    {
        Controller controller(5000, 0);
        const Decision stuck = controller.tick(at(0, 1000, 50, 0, 20, 1, false));
        expect(!stuck.send && stuck.wireKbps == 5000, "already at the floor does not send another cut");
    }

    {
        Controller controller(20000, 0);
        controller.prime(at(0, 5000, 4000, 9, 20, 1, false));
        const Decision kept = controller.tick(at(1500, 5100, 4000, 9, 20, 1, false));
        expect(!kept.send && kept.wireKbps == 20000, "counters from before this stream do not cut");
        const Decision fresh = controller.tick(at(3000, 6100, 4030, 9, 20, 1, false));
        expect(fresh.action == Action::Cut && fresh.wireKbps == 14000, "new loss after the prime still cuts");
    }

    {
        Controller controller(20000, 0);
        expect(controller.tick(at(0, 100, 0, 0, 20, 1, false)).action == Action::Hold, "opening clean sample");
        const Decision backwards = controller.tick(at(-10, 200, 0, 0, 20, 1, false));
        expect(!backwards.send && backwards.wireKbps == 20000, "time going backwards is ignored");
    }

    if (g_Failures != 0) {
        std::printf("%d failed\n", g_Failures);
        return 1;
    }
    std::printf("ok\n");
    return 0;
}
