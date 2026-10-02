#!/usr/bin/env python3
"""Teach moonlight-common-c the Sunshine adaptive-trigger control packet.

The spatial-mixer pin (583754fc) stops at setControllerLED. Upstream
moonlight-common-c e95feaf (PR 102) adds ConnListenerSetAdaptiveTriggers
and control type 0x5503. Retargeting the submodule would drop the macOS
clock and high-res stat fixes on this pin, so qmake applies the delta
here. The script is idempotent and is the source of the change: do not
commit the patched submodule tree.

Packet layout matches Sunshine control_adaptive_triggers_t after the
v2 header is stripped:

    uint16 controllerNumber
    uint8  eventFlags     bit 0x04 right, bit 0x08 left
    uint8  typeLeft
    uint8  typeRight
    uint8  left[10]
    uint8  right[10]

Shorter packet-type tables gain an explicit -1 at index 12. Upstream
reads packetTypes[IDX_DS_ADAPTIVE_TRIGGERS] on every async callback
check; without that slot, GFE generations walk off the array.
"""

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "moonlight-common-c" / "moonlight-common-c" / "src"


def ensure(path: Path, old: str, new: str, marker: str) -> None:
    text = path.read_text()
    if marker in text:
        return
    if old not in text:
        sys.stderr.write(f"{path}: expected text not found and {marker!r} is absent\n")
        sys.exit(1)
    path.write_text(text.replace(old, new, 1))
    print(f"patched {path.name} ({marker})")


def main() -> None:
    if not SRC.is_dir():
        sys.stderr.write(f"moonlight-common-c sources not checked out: {SRC}\n")
        sys.exit(1)

    ensure(
        SRC / "Limelight.h",
        """// If reportRateHz is 0, the host is asking for motion event reporting to stop.
typedef void(*ConnListenerSetMotionEventState)(uint16_t controllerNumber, uint8_t motionType, uint16_t reportRateHz);

// This callback is invoked to set a controller's RGB LED (if present).
typedef void(*ConnListenerSetControllerLED)(uint16_t controllerNumber, uint8_t r, uint8_t g, uint8_t b);
""",
        """// If reportRateHz is 0, the host is asking for motion event reporting to stop.
typedef void(*ConnListenerSetMotionEventState)(uint16_t controllerNumber, uint8_t motionType, uint16_t reportRateHz);

// This callback is invoked to notify the client of a DualSense adaptive
// trigger configuration. eventFlags bit 0x04 selects the right trigger and
// bit 0x08 selects the left. typeLeft/typeRight are the effect mode bytes.
// left/right are the 10 parameter bytes that follow the mode (11 bytes on
// the HID report: mode + payload). Sunshine sends this as control type
// 0x5503 when the host virtual pad is a DualSense. GFE does not.
#define DS_EFFECT_PAYLOAD_SIZE 10
#define DS_EFFECT_RIGHT_TRIGGER 0x04
#define DS_EFFECT_LEFT_TRIGGER 0x08
typedef void(*ConnListenerSetAdaptiveTriggers)(uint16_t controllerNumber, uint8_t eventFlags, uint8_t typeLeft, uint8_t typeRight, uint8_t *left, uint8_t *right);

// This callback is invoked to set a controller's RGB LED (if present).
typedef void(*ConnListenerSetControllerLED)(uint16_t controllerNumber, uint8_t r, uint8_t g, uint8_t b);
""",
        "ConnListenerSetAdaptiveTriggers",
    )
    ensure(
        SRC / "Limelight.h",
        """    ConnListenerSetMotionEventState setMotionEventState;
    ConnListenerSetControllerLED setControllerLED;
} CONNECTION_LISTENER_CALLBACKS, *PCONNECTION_LISTENER_CALLBACKS;
""",
        """    ConnListenerSetMotionEventState setMotionEventState;
    ConnListenerSetControllerLED setControllerLED;
    ConnListenerSetAdaptiveTriggers setAdaptiveTriggers;
} CONNECTION_LISTENER_CALLBACKS, *PCONNECTION_LISTENER_CALLBACKS;
""",
        "setAdaptiveTriggers;",
    )
    ensure(
        SRC / "FakeCallbacks.c",
        """static void fakeClSetMotionEventState(uint16_t controllerNumber, uint8_t motionType, uint16_t reportRateHz) {}
static void fakeClSetControllerLED(uint16_t controllerNumber, uint8_t r, uint8_t g, uint8_t b) {}
""",
        """static void fakeClSetMotionEventState(uint16_t controllerNumber, uint8_t motionType, uint16_t reportRateHz) {}
static void fakeClSetAdaptiveTriggers(uint16_t controllerNumber, uint8_t eventFlags, uint8_t typeLeft, uint8_t typeRight, uint8_t *left, uint8_t *right) {}
static void fakeClSetControllerLED(uint16_t controllerNumber, uint8_t r, uint8_t g, uint8_t b) {}
""",
        "fakeClSetAdaptiveTriggers",
    )
    ensure(
        SRC / "FakeCallbacks.c",
        """    .setMotionEventState = fakeClSetMotionEventState,
    .setControllerLED = fakeClSetControllerLED,
};
""",
        """    .setMotionEventState = fakeClSetMotionEventState,
    .setControllerLED = fakeClSetControllerLED,
    .setAdaptiveTriggers = fakeClSetAdaptiveTriggers,
};
""",
        ".setAdaptiveTriggers = fakeClSetAdaptiveTriggers",
    )
    ensure(
        SRC / "FakeCallbacks.c",
        """        if ((*clCallbacks)->setControllerLED == NULL) {
            (*clCallbacks)->setControllerLED = fakeClSetControllerLED;
        }
    }
}
""",
        """        if ((*clCallbacks)->setControllerLED == NULL) {
            (*clCallbacks)->setControllerLED = fakeClSetControllerLED;
        }
        if ((*clCallbacks)->setAdaptiveTriggers == NULL) {
            (*clCallbacks)->setAdaptiveTriggers = fakeClSetAdaptiveTriggers;
        }
    }
}
""",
        "(*clCallbacks)->setAdaptiveTriggers",
    )
    ensure(
        SRC / "ControlStream.c",
        """        struct {
            uint16_t controllerNumber;
            uint8_t r;
            uint8_t g;
            uint8_t b;
        } setControllerLed;
    } data;
""",
        """        struct {
            uint16_t controllerNumber;
            uint8_t r;
            uint8_t g;
            uint8_t b;
        } setControllerLed;
        struct {
            uint16_t controllerNumber;
            // 0x04 right trigger, 0x08 left trigger.
            uint8_t eventFlags;
            uint8_t typeLeft;
            uint8_t typeRight;
            uint8_t left[DS_EFFECT_PAYLOAD_SIZE];
            uint8_t right[DS_EFFECT_PAYLOAD_SIZE];
        } dsAdaptiveTrigger;
    } data;
""",
        "dsAdaptiveTrigger",
    )
    ensure(
        SRC / "ControlStream.c",
        """#define IDX_SET_MOTION_EVENT 10
#define IDX_SET_RGB_LED 11
""",
        """#define IDX_SET_MOTION_EVENT 10
#define IDX_SET_RGB_LED 11
#define IDX_DS_ADAPTIVE_TRIGGERS 12
""",
        "IDX_DS_ADAPTIVE_TRIGGERS",
    )
    # Four pre-Sunshine tables share this closing entry. replace() once is
    # not enough; the marker stops a second qmake run from growing them again.
    control = (SRC / "ControlStream.c").read_text()
    unused = "    -1,     // Set RGB LED (unused)\n};"
    unused_new = "    -1,     // Set RGB LED (unused)\n    -1,     // Adaptive triggers (unused)\n};"
    if "Adaptive triggers (unused)" not in control:
        count = control.count(unused)
        if count != 4:
            sys.stderr.write(f"ControlStream.c: expected 4 unused RGB LED entries, found {count}\n")
            sys.exit(1)
        control = control.replace(unused, unused_new)
        (SRC / "ControlStream.c").write_text(control)
        print("patched ControlStream.c (Adaptive triggers unused slots)")
    ensure(
        SRC / "ControlStream.c",
        """    0x5502, // Set RGB LED (Sunshine protocol extension)
};
""",
        """    0x5502, // Set RGB LED (Sunshine protocol extension)
    0x5503, // Set Adaptive Triggers (Sunshine protocol extension)
};
""",
        "0x5503",
    )
    ensure(
        SRC / "ControlStream.c",
        """            ListenerCallbacks.setMotionEventState(queuedCb->data.setMotionEventState.controllerNumber,
                                                  queuedCb->data.setMotionEventState.motionType,
                                                  queuedCb->data.setMotionEventState.reportRateHz);
            break;
        default:
""",
        """            ListenerCallbacks.setMotionEventState(queuedCb->data.setMotionEventState.controllerNumber,
                                                  queuedCb->data.setMotionEventState.motionType,
                                                  queuedCb->data.setMotionEventState.reportRateHz);
            break;
        case IDX_DS_ADAPTIVE_TRIGGERS:
            ListenerCallbacks.setAdaptiveTriggers(queuedCb->data.dsAdaptiveTrigger.controllerNumber,
                                                  queuedCb->data.dsAdaptiveTrigger.eventFlags,
                                                  queuedCb->data.dsAdaptiveTrigger.typeLeft,
                                                  queuedCb->data.dsAdaptiveTrigger.typeRight,
                                                  queuedCb->data.dsAdaptiveTrigger.left,
                                                  queuedCb->data.dsAdaptiveTrigger.right);
            break;
        default:
""",
        "case IDX_DS_ADAPTIVE_TRIGGERS:",
    )
    ensure(
        SRC / "ControlStream.c",
        """           packetType == packetTypes[IDX_SET_RGB_LED] ||
           packetType == packetTypes[IDX_HDR_INFO];
""",
        """           packetType == packetTypes[IDX_SET_RGB_LED] ||
           packetType == packetTypes[IDX_HDR_INFO] ||
           packetType == packetTypes[IDX_DS_ADAPTIVE_TRIGGERS];
""",
        "packetTypes[IDX_DS_ADAPTIVE_TRIGGERS]",
    )
    ensure(
        SRC / "ControlStream.c",
        """    else if (ctlHdr->type == packetTypes[IDX_HDR_INFO]) {
        queuedCb->typeIndex = IDX_HDR_INFO;
    }
    else {
        // Unhandled packet type from needsAsyncCallback()
        LC_ASSERT(false);
        free(queuedCb);
        return;
    }
""",
        """    else if (ctlHdr->type == packetTypes[IDX_HDR_INFO]) {
        queuedCb->typeIndex = IDX_HDR_INFO;
    }
    else if (ctlHdr->type == packetTypes[IDX_DS_ADAPTIVE_TRIGGERS]) {
        int i;

        BbGet16(&bb, &queuedCb->data.dsAdaptiveTrigger.controllerNumber);
        BbGet8(&bb, &queuedCb->data.dsAdaptiveTrigger.eventFlags);
        BbGet8(&bb, &queuedCb->data.dsAdaptiveTrigger.typeLeft);
        BbGet8(&bb, &queuedCb->data.dsAdaptiveTrigger.typeRight);
        for (i = 0; i < DS_EFFECT_PAYLOAD_SIZE; i++) {
            BbGet8(&bb, &queuedCb->data.dsAdaptiveTrigger.left[i]);
        }
        for (i = 0; i < DS_EFFECT_PAYLOAD_SIZE; i++) {
            BbGet8(&bb, &queuedCb->data.dsAdaptiveTrigger.right[i]);
        }
        queuedCb->typeIndex = IDX_DS_ADAPTIVE_TRIGGERS;
    }
    else {
        // Unhandled packet type from needsAsyncCallback()
        LC_ASSERT(false);
        free(queuedCb);
        return;
    }
""",
        "queuedCb->typeIndex = IDX_DS_ADAPTIVE_TRIGGERS",
    )


if __name__ == "__main__":
    main()
