#pragma once

// Cocoa placement for the Twilight HUD. The stream rectangle and the HUD
// size are in points. The returned origin is the HUD window's bottom-left,
// which is what NSWindow setFrameOrigin expects. A degenerate stream frame
// or a zero HUD size is refused so the caller can keep the previous origin
// instead of parking the chips off-screen.

struct TwilightHudPlace {
    double x;
    double y;
    bool ok;
};

inline TwilightHudPlace twilightPlaceHud(double streamX, double streamY,
                                         double streamW, double streamH,
                                         double hudW, double hudH)
{
    TwilightHudPlace place = {0, 0, false};
    if (!(streamW >= 2.0 && streamH >= 2.0 && hudW >= 1.0 && hudH >= 1.0)) {
        return place;
    }

    // A short window is the mini player. Sit closer to its top edge.
    const double margin = streamH < 520.0 ? 8.0 : 28.0;
    double x = streamX + (streamW * 0.5) - (hudW * 0.5);
    double y = streamY + streamH - hudH - margin;

    if (hudW <= streamW) {
        const double minX = streamX;
        const double maxX = streamX + streamW - hudW;
        if (x < minX) {
            x = minX;
        }
        if (x > maxX) {
            x = maxX;
        }
    }
    else {
        // Wider than the stream. Pin to the stream's left edge. Clamping
        // to (right - hudW) would push the origin off the left of the screen.
        x = streamX;
    }

    if (hudH <= streamH) {
        const double minY = streamY;
        const double maxY = streamY + streamH - hudH;
        if (y < minY) {
            y = minY;
        }
        if (y > maxY) {
            y = maxY;
        }
    }
    else {
        y = streamY;
    }

    place.x = x;
    place.y = y;
    place.ok = true;
    return place;
}
