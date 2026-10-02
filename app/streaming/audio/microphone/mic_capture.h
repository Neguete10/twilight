#pragma once

// Opens the default Mac input, encodes 20 ms Opus frames, and sends them
// on the active Moonlight control stream. start() returns false when this
// platform has no capture, permission is missing, the control stream is
// not encrypted, or the device cannot be opened. A false return must not
// fail the stream.

class MicrophoneCapture
{
public:
    MicrophoneCapture();
    ~MicrophoneCapture();

    MicrophoneCapture(const MicrophoneCapture&) = delete;
    MicrophoneCapture& operator=(const MicrophoneCapture&) = delete;

    bool start();
    void stop();

    void setMuted(bool muted);
    bool isMuted() const;
    bool isRunning() const;

public:
    // Visible to mic_capture_mac.mm free functions (onInputBuffer/encodeLoop).
    struct Impl;
private:
    Impl* m_Impl;
};
