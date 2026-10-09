#pragma once

#include <atomic>

#include <QThread>

class NvComputer;

// Runs on its own thread. It must not be started on the render thread or the
// input thread: NvHTTP blocks in a nested event loop.
class AdaptiveBitrateThread : public QThread
{
public:
    AdaptiveBitrateThread(NvComputer* computer,
                          int ceilingWireKbps,
                          int audioKbps,
                          std::atomic<bool>* poorConnection,
                          std::atomic<bool>* poorConnectionEdge);

    void requestStop();

protected:
    void run() override;

private:
    NvComputer* m_Computer;
    int m_CeilingWireKbps;
    int m_AudioKbps;
    std::atomic<bool>* m_PoorConnection;
    std::atomic<bool>* m_PoorConnectionEdge;
    std::atomic<bool> m_Stop;
};
