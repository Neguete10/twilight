#include "mic_capture.h"

// Non-macOS stub. app.pro compiles this file only outside macx.
// mic_capture_mac.mm provides the same functions on macOS.

MicrophoneCapture::MicrophoneCapture()
    : m_Impl(nullptr)
{
}

MicrophoneCapture::~MicrophoneCapture()
{
}

bool MicrophoneCapture::start()
{
    return false;
}

void MicrophoneCapture::stop()
{
}

void MicrophoneCapture::setMuted(bool)
{
}

bool MicrophoneCapture::isMuted() const
{
    return false;
}

bool MicrophoneCapture::isRunning() const
{
    return false;
}
