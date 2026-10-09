#include "utils.h"

#if !defined(Q_OS_WIN32)

#define SDL_MAIN_HANDLED
#include <SDL.h>

#include <csignal>
#include <cstring>

static volatile sig_atomic_t s_StreamLoopAcceptsQuit = 0;

static void quitSignalHandler(int sig)
{
    if (s_StreamLoopAcceptsQuit) {
        SDL_Event event;
        SDL_zero(event);
        event.type = SDL_QUIT;
        SDL_PushEvent(&event);
        return;
    }

    struct sigaction action;
    std::memset(&action, 0, sizeof(action));
    action.sa_handler = SIG_DFL;
    sigemptyset(&action.sa_mask);
    sigaction(sig, &action, nullptr);
    raise(sig);
}

static void installOne(int sig)
{
    struct sigaction action;
    std::memset(&action, 0, sizeof(action));
    action.sa_handler = quitSignalHandler;
    sigemptyset(&action.sa_mask);
    // Leave interrupted calls running. The stream loop wakes because the
    // quit event is already queued.
    action.sa_flags = SA_RESTART;
    sigaction(sig, &action, nullptr);
}

void installQuitSignals()
{
    installOne(SIGTERM);
    installOne(SIGINT);
}

void setStreamLoopAcceptsQuit(bool active)
{
    s_StreamLoopAcceptsQuit = active ? 1 : 0;
}

#else

void installQuitSignals()
{
}

void setStreamLoopAcceptsQuit(bool)
{
}

#endif
