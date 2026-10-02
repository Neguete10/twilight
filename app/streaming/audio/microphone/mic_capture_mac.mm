#include "mic_capture.h"

#include "mic_permission.h"
#include "mic_resample.h"
#include "mic_wire.h"

#include <Limelight.h>

#include <opus/opus.h>

#include <SDL.h>

#import <AVFoundation/AVFoundation.h>

#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstring>
#include <thread>
#include <vector>

namespace {

constexpr uint32_t kRingCapacity = 65536;
constexpr uint32_t kRingMask = kRingCapacity - 1;

class MonoRing
{
public:
    MonoRing()
        : m_Write(0),
          m_Read(0)
    {
    }

    void reset()
    {
        m_Write.store(0, std::memory_order_relaxed);
        m_Read.store(0, std::memory_order_relaxed);
    }

    void push(const float* samples, uint32_t count)
    {
        const uint32_t write = m_Write.load(std::memory_order_relaxed);
        const uint32_t read = m_Read.load(std::memory_order_acquire);
        const uint32_t used = write - read;
        uint32_t freeSlots = (kRingCapacity - 1) - used;
        if (count > freeSlots) {
            count = freeSlots;
        }
        for (uint32_t i = 0; i < count; i++) {
            m_Samples[(write + i) & kRingMask] = samples[i];
        }
        m_Write.store(write + count, std::memory_order_release);
    }

    uint32_t pop(float* destination, uint32_t maxCount)
    {
        const uint32_t read = m_Read.load(std::memory_order_relaxed);
        const uint32_t write = m_Write.load(std::memory_order_acquire);
        uint32_t count = write - read;
        if (count > maxCount) {
            count = maxCount;
        }
        for (uint32_t i = 0; i < count; i++) {
            destination[i] = m_Samples[(read + i) & kRingMask];
        }
        m_Read.store(read + count, std::memory_order_release);
        return count;
    }

private:
    float m_Samples[kRingCapacity];
    std::atomic<uint32_t> m_Write;
    std::atomic<uint32_t> m_Read;
};

void sleepUntil(std::chrono::steady_clock::time_point deadline, const std::atomic<bool>& stopRequested)
{
    while (!stopRequested.load(std::memory_order_acquire)) {
        const auto now = std::chrono::steady_clock::now();
        if (now >= deadline) {
            return;
        }
        auto remaining = std::chrono::duration_cast<std::chrono::milliseconds>(deadline - now);
        if (remaining.count() > 5) {
            remaining = std::chrono::milliseconds(5);
        }
        if (remaining.count() < 1) {
            remaining = std::chrono::milliseconds(1);
        }
        std::this_thread::sleep_for(remaining);
    }
}

} // namespace

struct MicrophoneCapture::Impl {
    AVAudioEngine* engine;
    bool tapInstalled;
    OpusEncoder* opus;
    MonoRing ring;
    MicResampler resampler;
    std::vector<int16_t> pcm48;
    std::thread encoder;
    std::atomic<bool> stopRequested;
    std::atomic<bool> muted;
    std::atomic<bool> running;
    std::atomic<bool> unsupportedFormat;
    std::atomic<uint32_t> sampleRate;
    uint16_t sequence;

    Impl()
        : engine(nil),
          tapInstalled(false),
          opus(nullptr),
          stopRequested(false),
          muted(false),
          running(false),
          unsupportedFormat(false),
          sampleRate(0),
          sequence(0)
    {
    }
};

namespace {

void configureEncoder(OpusEncoder* encoder)
{
    // OPUS_SET_* macros expand to a request id plus a value, so each call
    // has to be written out. They cannot be stored in a single int.
    struct Control {
        int result;
        const char* name;
    };
    const Control controls[] = {
        {opus_encoder_ctl(encoder, OPUS_SET_BITRATE(MicWire::kOpusBitrate)), "BITRATE"},
        {opus_encoder_ctl(encoder, OPUS_SET_VBR(1)), "VBR"},
        {opus_encoder_ctl(encoder, OPUS_SET_COMPLEXITY(10)), "COMPLEXITY"},
        {opus_encoder_ctl(encoder, OPUS_SET_SIGNAL(OPUS_SIGNAL_VOICE)), "SIGNAL"},
        {opus_encoder_ctl(encoder, OPUS_SET_LSB_DEPTH(16)), "LSB_DEPTH"},
        {opus_encoder_ctl(encoder, OPUS_SET_DTX(1)), "DTX"},
        {opus_encoder_ctl(encoder, OPUS_SET_INBAND_FEC(1)), "INBAND_FEC"},
        {opus_encoder_ctl(encoder, OPUS_SET_PACKET_LOSS_PERC(5)), "PACKET_LOSS_PERC"},
        {opus_encoder_ctl(encoder, OPUS_SET_EXPERT_FRAME_DURATION(OPUS_FRAMESIZE_20_MS)), "FRAME_DURATION"},
    };

    for (size_t i = 0; i < sizeof(controls) / sizeof(controls[0]); i++) {
        if (controls[i].result != OPUS_OK) {
            SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                        "Microphone opus_encoder_ctl %s failed: %s",
                        controls[i].name,
                        opus_strerror(controls[i].result));
        }
    }
}

void onInputBuffer(MicrophoneCapture::Impl* impl, AVAudioPCMBuffer* buffer)
{
    if (impl->stopRequested.load(std::memory_order_acquire) || buffer == nil) {
        return;
    }
    if (buffer.format.commonFormat != AVAudioPCMFormatFloat32 || buffer.floatChannelData == nullptr) {
        impl->unsupportedFormat.store(true, std::memory_order_release);
        return;
    }

    const int channels = (int)buffer.format.channelCount;
    const AVAudioFrameCount frames = buffer.frameLength;
    if (channels < 1 || channels > 32 || frames == 0) {
        return;
    }

    const uint32_t rate = (uint32_t)(buffer.format.sampleRate + 0.5);
    if (rate > 0) {
        impl->sampleRate.store(rate, std::memory_order_relaxed);
    }

    float mono[512];
    AVAudioFrameCount offset = 0;
    while (offset < frames) {
        const AVAudioFrameCount chunk = frames - offset > 512 ? 512 : frames - offset;
        const float* planar[32];
        for (int channel = 0; channel < channels; channel++) {
            planar[channel] = buffer.floatChannelData[channel] + offset;
        }
        for (AVAudioFrameCount i = 0; i < chunk; i++) {
            mono[i] = micDownmix(planar, channels, (int)i);
        }
        impl->ring.push(mono, (uint32_t)chunk);
        offset += chunk;
    }
}

void encodeLoop(MicrophoneCapture::Impl* impl)
{
    uint8_t encoded[MicWire::kMaxOpusBytes];
    int16_t frame[MicWire::kFrameSamples];
    bool loggedSendFailure = false;
    bool loggedFirstPacket = false;
    bool loggedFormat = false;
    uint32_t packetsSent = 0;
    uint32_t configuredRate = 0;
    bool pacing = false;
    auto nextDeadline = std::chrono::steady_clock::now();
    const std::chrono::milliseconds frameDuration(MicWire::kFrameDurationMs);

    while (!impl->stopRequested.load(std::memory_order_acquire)) {
        if (impl->unsupportedFormat.load(std::memory_order_acquire)) {
            if (!loggedFormat) {
                SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                            "Microphone input is not float32; capture stopped");
                loggedFormat = true;
            }
            impl->running.store(false, std::memory_order_release);
            break;
        }

        const uint32_t rate = impl->sampleRate.load(std::memory_order_relaxed);
        if (rate == 0) {
            std::this_thread::sleep_for(std::chrono::milliseconds(2));
            continue;
        }
        if (rate != configuredRate) {
            impl->resampler.reset((double)rate);
            impl->pcm48.clear();
            configuredRate = rate;
            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                        "Microphone input rate %u Hz, encoding %d Hz mono",
                        rate,
                        MicWire::kSampleRate);
        }

        float chunk[1024];
        const uint32_t popped = impl->ring.pop(chunk, 1024);
        if (popped > 0) {
            const float* planes[1] = {chunk};
            impl->resampler.process(planes, 1, (int)popped, impl->pcm48);
        }

        if (impl->pcm48.size() < (size_t)MicWire::kFrameSamples) {
            std::this_thread::sleep_for(std::chrono::milliseconds(2));
            continue;
        }

        // Keep at most two frames queued so a large hardware buffer cannot
        // add hundreds of milliseconds of voice delay.
        const size_t maxQueued = (size_t)MicWire::kFrameSamples * 2;
        if (impl->pcm48.size() > maxQueued) {
            const size_t extraFrames = impl->pcm48.size() / (size_t)MicWire::kFrameSamples;
            if (extraFrames > 2) {
                impl->pcm48.erase(impl->pcm48.begin(),
                                  impl->pcm48.begin() + (extraFrames - 2) * (size_t)MicWire::kFrameSamples);
            }
        }

        const auto now = std::chrono::steady_clock::now();
        if (!pacing) {
            nextDeadline = now;
            pacing = true;
        }
        else if (now > nextDeadline + frameDuration * 2) {
            nextDeadline = now;
        }
        if (nextDeadline > now) {
            sleepUntil(nextDeadline, impl->stopRequested);
        }
        if (impl->stopRequested.load(std::memory_order_acquire)) {
            break;
        }
        nextDeadline += frameDuration;

        if (impl->pcm48.size() < (size_t)MicWire::kFrameSamples) {
            continue;
        }
        std::memcpy(frame, impl->pcm48.data(), sizeof(frame));
        impl->pcm48.erase(impl->pcm48.begin(), impl->pcm48.begin() + MicWire::kFrameSamples);

        // Mute still sends a frame so the host plays silence instead of
        // packet-loss concealment. The capture device stays open.
        if (impl->muted.load(std::memory_order_acquire)) {
            std::memset(frame, 0, sizeof(frame));
        }

        const int encodedBytes = opus_encode(impl->opus,
                                              frame,
                                              MicWire::kFrameSamples,
                                              encoded,
                                              (opus_int32)sizeof(encoded));
        if (encodedBytes <= 0) {
            SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                        "Microphone opus_encode failed: %s",
                        opus_strerror(encodedBytes));
            continue;
        }

        MicWire::Packet packet;
        if (!MicWire::buildPacket(impl->sequence, encoded, encodedBytes, packet)) {
            SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                        "Microphone frame of %d bytes does not fit the control packet",
                        encodedBytes);
            continue;
        }
        impl->sequence++;

        const int sent = LiSendRawControlStreamPacket(packet.type, packet.bytes, packet.length);
        if (sent != 0) {
            if (!loggedSendFailure) {
                SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                            "Microphone control send failed (%d); further failures are not logged",
                            sent);
                loggedSendFailure = true;
            }
            continue;
        }

        packetsSent++;
        if (!loggedFirstPacket) {
            loggedFirstPacket = true;
            SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                        "Sent first microphone packet (type 0x%04x, %d opus bytes)",
                        packet.type,
                        encodedBytes);
        }
        else if (packetsSent % 50 == 0) {
            SDL_LogDebug(SDL_LOG_CATEGORY_APPLICATION,
                         "Microphone packets sent: %u, sequence %u, muted %d",
                         packetsSent,
                         (unsigned)impl->sequence,
                         impl->muted.load(std::memory_order_relaxed) ? 1 : 0);
        }
    }
}

} // namespace

MicrophoneCapture::MicrophoneCapture()
    : m_Impl(new Impl())
{
}

MicrophoneCapture::~MicrophoneCapture()
{
    stop();
    delete m_Impl;
    m_Impl = nullptr;
}

bool MicrophoneCapture::start()
{
    if (m_Impl == nullptr) {
        return false;
    }

    stop();

    if (MacMicrophonePermission::status() != MacMicrophonePermission::Status::Granted) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "Microphone permission is not granted; streaming without microphone audio");
        return false;
    }
    if (!LiIsControlStreamEncrypted()) {
        SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                    "Microphone audio is not sent because the control stream is not encrypted");
        return false;
    }

    @autoreleasepool {
        int opusError = OPUS_OK;
        m_Impl->opus = opus_encoder_create(MicWire::kSampleRate,
                                            MicWire::kWireChannels,
                                            OPUS_APPLICATION_VOIP,
                                            &opusError);
        if (m_Impl->opus == nullptr || opusError != OPUS_OK) {
            SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                        "Microphone opus_encoder_create failed: %s",
                        opus_strerror(opusError));
            m_Impl->opus = nullptr;
            return false;
        }
        configureEncoder(m_Impl->opus);

        AVAudioEngine* engine = [[AVAudioEngine alloc] init];
        AVAudioInputNode* input = [engine inputNode];
        if (input == nil) {
            SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                        "Microphone input node is unavailable");
            [engine release];
            opus_encoder_destroy(m_Impl->opus);
            m_Impl->opus = nullptr;
            return false;
        }

        m_Impl->engine = engine;
        m_Impl->ring.reset();
        m_Impl->pcm48.clear();
        m_Impl->resampler.reset(0);
        m_Impl->sampleRate.store(0, std::memory_order_relaxed);
        m_Impl->unsupportedFormat.store(false, std::memory_order_relaxed);
        m_Impl->sequence = 0;
        m_Impl->muted.store(false, std::memory_order_relaxed);
        m_Impl->stopRequested.store(false, std::memory_order_release);

        Impl* impl = m_Impl;
        [input installTapOnBus:0 bufferSize:4096 format:nil block:^(AVAudioPCMBuffer* buffer, AVAudioTime* when) {
            (void)when;
            onInputBuffer(impl, buffer);
        }];
        m_Impl->tapInstalled = true;

        NSError* error = nil;
        if (![engine startAndReturnError:&error]) {
            const char* message = error != nil ? error.localizedDescription.UTF8String : "unknown error";
            SDL_LogWarn(SDL_LOG_CATEGORY_APPLICATION,
                        "AVAudioEngine microphone start failed: %s",
                        message != nullptr ? message : "unknown error");
            stop();
            return false;
        }

        m_Impl->running.store(true, std::memory_order_release);
        m_Impl->encoder = std::thread(encodeLoop, m_Impl);
    }

    SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION,
                "Microphone capture started (Opus %d Hz mono, %d ms, control type 0x%04x)",
                MicWire::kSampleRate,
                MicWire::kFrameDurationMs,
                MicWire::kPacketType);
    return true;
}

void MicrophoneCapture::stop()
{
    if (m_Impl == nullptr) {
        return;
    }

    m_Impl->stopRequested.store(true, std::memory_order_release);
    @autoreleasepool {
        if (m_Impl->tapInstalled && m_Impl->engine != nil) {
            [[m_Impl->engine inputNode] removeTapOnBus:0];
            m_Impl->tapInstalled = false;
        }
        if (m_Impl->engine != nil) {
            [m_Impl->engine stop];
            [m_Impl->engine release];
            m_Impl->engine = nil;
        }
    }
    if (m_Impl->encoder.joinable()) {
        m_Impl->encoder.join();
    }
    if (m_Impl->opus != nullptr) {
        opus_encoder_destroy(m_Impl->opus);
        m_Impl->opus = nullptr;
    }
    if (m_Impl->running.exchange(false)) {
        SDL_LogInfo(SDL_LOG_CATEGORY_APPLICATION, "Microphone capture stopped");
    }
}

void MicrophoneCapture::setMuted(bool muted)
{
    if (m_Impl != nullptr) {
        m_Impl->muted.store(muted, std::memory_order_release);
    }
}

bool MicrophoneCapture::isMuted() const
{
    return m_Impl != nullptr && m_Impl->muted.load(std::memory_order_acquire);
}

bool MicrophoneCapture::isRunning() const
{
    return m_Impl != nullptr && m_Impl->running.load(std::memory_order_acquire);
}
