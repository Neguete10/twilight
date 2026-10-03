#include "streaming/audio/renderers/coreaudio/coreaudio_playback.h"

#include <cstdio>

static int g_Failures = 0;

static void expectTrue(bool value, const char* label)
{
    if (!value) {
        std::printf("FAIL %s\n", label);
        g_Failures++;
    }
}

static CoreAudioPlaybackState runningState()
{
    CoreAudioPlaybackState state = {};
    state.instance = true;
    state.initialized = true;
    state.started = true;
    state.ring = true;
    state.listeners = true;
    state.deviceName = true;
    return state;
}

static void testSampleCounts()
{
    expectTrue(coreAudioFloatSampleCount(0) == 0, "empty buffer has no samples");
    expectTrue(coreAudioFloatSampleCount(-4) == 0, "negative byte count has no samples");
    expectTrue(coreAudioFloatSampleCount(3) == 0, "a short tail is not a float");
    expectTrue(coreAudioFloatSampleCount((int)sizeof(float)) == 1, "one float is one sample");

    // Stereo 48 kHz, 5 ms: 240 frames * 2 channels * 4 bytes.
    const int stereo5ms = 240 * 2 * (int)sizeof(float);
    expectTrue(coreAudioFloatSampleCount(stereo5ms) == 480, "5 ms stereo is 480 samples");

    const uint32_t frames = 256;
    expectTrue(coreAudioPlanarSampleCount(frames) == frames, "planar length is one sample per frame");
    expectTrue(coreAudioFloatSampleCount((int)frames * (int)sizeof(float)) == (int)frames,
               "planar byte length converts back to the frame count");
}

static void testNeverStarted()
{
    CoreAudioPlaybackState created = {};
    created.instance = true;

    const CoreAudioTeardownStep stopped = coreAudioStop(created);
    expectTrue(!stopped.stop, "stop skips a unit that was never started");
    expectTrue(stopped.after.instance, "stop leaves the instance in place");
    expectTrue(!stopped.after.started, "stop leaves started clear");

    const CoreAudioTeardownStep cleaned = coreAudioCleanup(created);
    expectTrue(!cleaned.stop, "cleanup does not stop a unit that was never started");
    expectTrue(!cleaned.uninitialize, "cleanup does not uninitialize a unit that was never initialized");
    expectTrue(cleaned.dispose, "cleanup still disposes the instance");
    expectTrue(!cleaned.cleanupRing, "cleanup skips a ring that was never created");
    expectTrue(!cleaned.after.instance, "cleanup clears the instance");

    const CoreAudioTeardownStep again = coreAudioCleanup(cleaned.after);
    expectTrue(!again.stop && !again.uninitialize && !again.dispose && !again.cleanupRing
                   && !again.removeListeners && !again.freeDeviceName,
               "cleanup a second time is a no-op");
}

static void testInitializedButNotStarted()
{
    CoreAudioPlaybackState state = runningState();
    state.started = false;

    const CoreAudioTeardownStep cleaned = coreAudioCleanup(state);
    expectTrue(!cleaned.stop, "a failed start is not stopped");
    expectTrue(cleaned.uninitialize, "initialize without start is still uninitialized");
    expectTrue(cleaned.dispose, "failed start still disposes the instance");
    expectTrue(cleaned.cleanupRing && cleaned.removeListeners && cleaned.freeDeviceName,
               "failed start still releases the buffers it created");
}

static void testStopTwiceThenCleanup()
{
    const CoreAudioPlaybackState running = runningState();

    const CoreAudioTeardownStep first = coreAudioStop(running);
    expectTrue(first.stop, "the first stop stops a started unit");
    expectTrue(!first.uninitialize && !first.dispose, "stop does not tear the unit down");
    expectTrue(!first.after.started, "the first stop clears started");
    expectTrue(first.after.initialized && first.after.instance, "the first stop leaves the unit initialized");

    const CoreAudioTeardownStep second = coreAudioStop(first.after);
    expectTrue(!second.stop, "the second stop does not call AudioOutputUnitStop");
    expectTrue(!second.after.started, "the second stop stays stopped");

    const CoreAudioTeardownStep cleaned = coreAudioCleanup(second.after);
    expectTrue(!cleaned.stop, "cleanup after stop does not stop again");
    expectTrue(cleaned.uninitialize, "cleanup after stop still uninitializes");
    expectTrue(cleaned.dispose && cleaned.cleanupRing && cleaned.removeListeners && cleaned.freeDeviceName,
               "cleanup after stop releases the instance and buffers");

    const CoreAudioTeardownStep again = coreAudioCleanup(cleaned.after);
    expectTrue(!again.stop && !again.uninitialize && !again.dispose,
               "cleanup after a full teardown does not uninitialize again");
}

static void testRunningCleanupIsIdempotent()
{
    const CoreAudioTeardownStep cleaned = coreAudioCleanup(runningState());
    expectTrue(cleaned.stop, "stream teardown stops a running unit");
    expectTrue(cleaned.uninitialize, "stream teardown uninitializes a running unit");
    expectTrue(cleaned.dispose && cleaned.cleanupRing && cleaned.removeListeners && cleaned.freeDeviceName,
               "stream teardown releases every resource it owns");
    expectTrue(!cleaned.after.started && !cleaned.after.initialized && !cleaned.after.instance,
               "stream teardown clears the playback state");

    const CoreAudioTeardownStep again = coreAudioCleanup(cleaned.after);
    expectTrue(!again.stop && !again.uninitialize && !again.dispose && !again.cleanupRing
                   && !again.removeListeners && !again.freeDeviceName,
               "a second stream teardown does nothing");
}

int main()
{
    testSampleCounts();
    testNeverStarted();
    testInitializedButNotStarted();
    testStopTwiceThenCleanup();
    testRunningCleanupIsIdempotent();

    if (g_Failures != 0) {
        std::printf("%d coreaudio playback tests failed\n", g_Failures);
        return 1;
    }
    std::printf("coreaudio playback tests passed\n");
    return 0;
}
