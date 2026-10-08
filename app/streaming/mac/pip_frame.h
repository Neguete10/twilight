#pragma once

#include <stdint.h>

// Picture-in-picture placement for the stream window.
//
// Coordinates match SDL: origin at the top-left of the display, y grows
// downward. `usable` is the work area (menu bar and Dock already removed).
// A non-positive video size is treated as 16:9.
//
// The result is a bottom-right mini player. Bottom-right stays clear of
// Stage Manager's thumbnail strip, which sits on the left. The target is
// 640 points wide, capped at two fifths of the usable width and 45% of
// the usable height so the window the user is actually working in keeps
// the screen.

struct PipDisplayBounds {
    int x;
    int y;
    int w;
    int h;
};

struct PipFrame {
    int x;
    int y;
    int w;
    int h;
};

inline PipFrame suggestPictureInPictureFrame(PipDisplayBounds usable, int videoW, int videoH)
{
    PipFrame frame = {0, 0, 0, 0};
    if (usable.w <= 0 || usable.h <= 0) {
        return frame;
    }

    if (videoW <= 0 || videoH <= 0) {
        videoW = 16;
        videoH = 9;
    }

    const int kMargin = 20;
    const int kTargetWidth = 640;

    int padX = kMargin;
    int padY = kMargin;
    int availW = usable.w - kMargin * 2;
    int availH = usable.h - kMargin * 2;
    if (availW < 1 || availH < 1) {
        padX = 0;
        padY = 0;
        availW = usable.w;
        availH = usable.h;
    }

    int maxW = usable.w * 2 / 5;
    int maxH = usable.h * 45 / 100;
    if (maxW < 1) {
        maxW = 1;
    }
    if (maxH < 1) {
        maxH = 1;
    }
    if (maxW > availW) {
        maxW = availW;
    }
    if (maxH > availH) {
        maxH = availH;
    }

    int w = kTargetWidth;
    if (w > maxW) {
        w = maxW;
    }
    int h = (int)((int64_t)w * videoH / videoW);
    if (h < 1) {
        h = 1;
    }
    if (h > maxH) {
        h = maxH;
        w = (int)((int64_t)h * videoW / videoH);
        if (w < 1) {
            w = 1;
        }
        if (w > maxW) {
            w = maxW;
        }
    }

    if (w > availW) {
        w = availW;
    }
    if (h > availH) {
        h = availH;
    }
    if (w < 1) {
        w = 1;
    }
    if (h < 1) {
        h = 1;
    }

    frame.w = w;
    frame.h = h;
    frame.x = usable.x + usable.w - padX - w;
    frame.y = usable.y + usable.h - padY - h;
    return frame;
}
