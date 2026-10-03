#pragma once

#include <stdint.h>

// Playback sizing and teardown decisions for CoreAudioRenderer.
// This header has no Apple SDK types so a Linux test can cover it.

// vDSP_vclr and vDSP_mmov count float samples. Core Audio reports
// buffer sizes in bytes. Passing the byte count writes four times past
// the ExtendedAudioBufferList; the guarded allocator notices when
// AudioUnitUninitialize frees that list.
inline int coreAudioFloatSampleCount(int byteCount)
{
    if (byteCount <= 0) {
        return 0;
    }
    return byteCount / (int)sizeof(float);
}

// A planar float buffer holds one sample per frame. The byte length of
// that buffer is frames * sizeof(float), which is not a vDSP length.
inline uint32_t coreAudioPlanarSampleCount(uint32_t frames)
{
    return frames;
}

struct CoreAudioPlaybackState {
    bool instance;
    bool initialized;
    bool started;
    bool ring;
    bool listeners;
    bool deviceName;
};

struct CoreAudioTeardownStep {
    bool stop;
    bool uninitialize;
    bool dispose;
    bool cleanupRing;
    bool removeListeners;
    bool freeDeviceName;
    CoreAudioPlaybackState after;
};

// AudioOutputUnitStop only if start succeeded. A second call is a no-op,
// including when the unit was never started.
inline CoreAudioTeardownStep coreAudioStop(CoreAudioPlaybackState state)
{
    CoreAudioTeardownStep step = {};
    step.stop = state.started;
    state.started = false;
    step.after = state;
    return step;
}

// Stop if needed, then uninitialize only if AudioUnitInitialize succeeded,
// then release the instance and the buffers it borrowed.
inline CoreAudioTeardownStep coreAudioCleanup(CoreAudioPlaybackState state)
{
    CoreAudioTeardownStep step = coreAudioStop(state);
    step.uninitialize = step.after.initialized;
    step.dispose = step.after.instance;
    step.cleanupRing = step.after.ring;
    step.removeListeners = step.after.listeners;
    step.freeDeviceName = step.after.deviceName;
    step.after.initialized = false;
    step.after.instance = false;
    step.after.ring = false;
    step.after.listeners = false;
    step.after.deviceName = false;
    step.after.started = false;
    return step;
}
