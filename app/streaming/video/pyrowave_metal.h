#pragma once

#ifdef HAVE_PYROWAVE_METAL

#include "decoder.h"
#include "overlaymanager.h"

// Native Metal PyroWave decode and present. The wavelet library is
// libpyrowave-metal (dlopen), not the MoltenVK libpyrowave-shared linked
// into PyroWaveVideoDecoder. Present is a CAMetalLayer draw of the three
// decode planes, the same YUV->RGB shader VideoToolbox already uses.
class PyroWaveMetalVideoDecoder : public IVideoDecoder, public Overlay::IOverlayRenderer {
public:
    explicit PyroWaveMetalVideoDecoder(bool testOnly);
    ~PyroWaveMetalVideoDecoder() override;

    // dylib loaded, API 0.5.x, and an Apple7-class MTLDevice. Does not
    // compile the decode pipelines; initialize() does that.
    static bool runtimeAvailable();

    bool initialize(PDECODER_PARAMETERS params) override;
    bool isHardwareAccelerated() override;
    bool isAlwaysFullScreen() override;
    bool isHdrSupported() override;
    int getDecoderCapabilities() override;
    int getDecoderColorspace() override;
    int getDecoderColorRange() override;
    QSize getDecoderMaxResolution() override;
    int submitDecodeUnit(PDECODE_UNIT du) override;
    void renderFrameOnMainThread() override;
    void setHdrMode(bool enabled) override;
    bool notifyWindowChanged(PWINDOW_STATE_CHANGE_INFO info) override;

    void notifyOverlayUpdated(Overlay::OverlayType type) override;

private:
    struct Impl;
    Impl* m_Impl;
    bool m_TestOnly;
};

#endif  // HAVE_PYROWAVE_METAL
