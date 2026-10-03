#!/usr/bin/env python3
"""Summarize a matched PyroWave Vulkan log and Metal log.

The table is steady-state frame time. "Received first video packet after
X ms" is printed under Context and is not a result column.

Quit each stream so the decoder writes "Global video stats" and the
"PyroWave metric:" lines. A log that only has the first-packet line has
no steady-state numbers.

Example (same host, resolution, codec, bitrate, and vsync; quit both):

    moonlight stream <host> <app> --video-codec PyroWave --pyrowave-backend vulkan
    moonlight stream <host> <app> --video-codec PyroWave --pyrowave-backend metal
    python3 scripts/pyrowave_ab_summary.py vulkan.log metal.log

Logs are Moonlight-<timestamp>.log. The script uses the backend named in
the log, not the order of the two files.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SAMPLE_VULKAN = ROOT / "scripts" / "testdata" / "pyrowave_vulkan_sample.log"
SAMPLE_METAL = ROOT / "scripts" / "testdata" / "pyrowave_metal_sample.log"

PERCENTILE = re.compile(
    r"PyroWave metric:\s+(\S+)\s+p50=(\S+)\s+p95=(\S+)\s+p99=(\S+)\s+n=(\d+)(?:\s+overflow=(\d+))?"
)
SIMPLE = re.compile(r"PyroWave metric:\s+([^=\s]+)=(.*)$")
FIRST_PACKET = re.compile(r"Received first video packet after (\d+) ms")
RECONFIGURE = re.compile(r"PyroWave reconfigure:\s*(.*)$")
SELECTED = re.compile(r"PyroWave backend selected:\s*(.*)$")
REQUEST = re.compile(r"PyroWave backend request:\s*(.*)$")

ROWS = [
    ("decode_submit_ms", "Decode submit p50/p95/p99 (ms)"),
    ("present_ms", "Present p50/p95/p99 (ms)"),
    ("decode_to_present_ms", "Decode-submit to present-return p50/p95/p99 (ms)"),
    ("rendered_fps", "Rendered FPS"),
    ("decoded_fps", "Decoded FPS"),
    ("received_fps", "Received FPS"),
    ("avg_decode_ms", "Average decode submit (ms)"),
    ("avg_present_ms", "Average present (ms)"),
    ("avg_reassembly_ms", "Average reassembly (ms)"),
    ("avg_mbps", "Average Mbps"),
    ("network_dropped", "Network-dropped frames"),
    ("stalled_presents", "Stalled presents"),
    ("replaced_before_present", "Frames replaced before present"),
    ("decoded_frames", "Decoded frames"),
    ("rendered_frames", "Rendered frames"),
    ("color", "Present color"),
    ("pixel_format", "Pixel format"),
    ("plane_format", "Plane format"),
    ("color_advertised", "Advertised color"),
    ("resolution", "Resolution"),
    ("video_format", "Video format"),
    ("vsync", "V-sync"),
    ("swapchain_depth", "Swapchain depth"),
    ("gpu", "GPU"),
    ("cpu", "CPU"),
]


class LogSummary:
    def __init__(self, path: Path):
        self.path = path
        self.metrics = {}
        self.percentiles = {}
        self.first_packet_ms = None
        self.reconfigure = []
        self.selected = []
        self.requests = []
        self.saw_context_note = False

    @property
    def backend(self) -> str:
        name = self.metrics.get("backend", "").strip()
        if name.lower() == "vulkan":
            return "Vulkan"
        if name.lower() == "metal":
            return "Metal"
        return self.path.name


def parse_log(path: Path) -> LogSummary:
    summary = LogSummary(path)
    text = path.read_text(errors="replace")
    for raw in text.splitlines():
        line = raw.strip()
        if "startup context only" in line:
            summary.saw_context_note = True
        match = FIRST_PACKET.search(line)
        if match:
            summary.first_packet_ms = int(match.group(1))
        match = RECONFIGURE.search(line)
        if match:
            summary.reconfigure.append(match.group(1).strip())
        match = SELECTED.search(line)
        if match:
            summary.selected.append(match.group(1).strip())
        match = REQUEST.search(line)
        if match:
            summary.requests.append(match.group(1).strip())
        match = PERCENTILE.search(line)
        if match:
            overflow = match.group(6) or "0"
            summary.percentiles[match.group(1)] = {
                "p50": match.group(2),
                "p95": match.group(3),
                "p99": match.group(4),
                "n": match.group(5),
                "overflow": overflow,
            }
            continue
        match = SIMPLE.search(line)
        if match:
            summary.metrics[match.group(1)] = match.group(2).strip()
    return summary


def cell(summary: LogSummary, key: str) -> str:
    if key in summary.percentiles:
        item = summary.percentiles[key]
        text = f"{item['p50']} / {item['p95']} / {item['p99']} (n={item['n']})"
        if item["overflow"] not in ("0", ""):
            text += f" overflow={item['overflow']}"
        return text
    if key in summary.metrics:
        return summary.metrics[key]
    return "n/a"


def column_title(summary: LogSummary, other: LogSummary) -> str:
    title = summary.backend
    if title == other.backend:
        return f"{title} ({summary.path.name})"
    return title


def render(left: LogSummary, right: LogSummary) -> str:
    left_title = column_title(left, right)
    right_title = column_title(right, left)
    lines = [
        "PyroWave Vulkan vs Metal — steady-state",
        "First-packet wait is context only. It is not a result in this table.",
        "",
        f"| Metric | {left_title} | {right_title} |",
        "| --- | --- | --- |",
    ]
    for key, label in ROWS:
        lines.append(f"| {label} | {cell(left, key)} | {cell(right, key)} |")

    mismatches = []
    for key, label in (("resolution", "resolution"), ("video_format", "video format"), ("vsync", "v-sync")):
        lv = left.metrics.get(key)
        rv = right.metrics.get(key)
        if lv and rv and lv != rv:
            mismatches.append(f"{label} differs ({left_title} {lv}, {right_title} {rv})")
    if mismatches:
        lines.append("")
        for note in mismatches:
            lines.append(f"Warning: {note}. These logs are not a matched pair.")

    note = left.metrics.get("timing_note") or right.metrics.get("timing_note")
    if note:
        lines.append("")
        lines.append(f"Timing: {note}")

    lines.append("")
    lines.append("Context")
    for summary, title in ((left, left_title), (right, right_title)):
        if summary.first_packet_ms is None:
            lines.append(f"- {title} first video packet: not in this log")
        else:
            lines.append(
                f"- {title} received first video packet after {summary.first_packet_ms} ms (startup context)"
            )
        if summary.requests:
            lines.append(f"- {title} backend request: {summary.requests[-1]}")
        if summary.selected:
            lines.append(f"- {title} backend selected: {'; '.join(summary.selected)}")
        if summary.reconfigure:
            shown = summary.reconfigure[-6:]
            lines.append(f"- {title} reconfigure ({len(summary.reconfigure)}):")
            for event in shown:
                lines.append(f"  - {event}")
    if not left.percentiles and not right.percentiles:
        lines.append("")
        lines.append(
            "No percentile lines were found. Quit the stream so Global video stats are written. "
            "The first-packet line is not a benchmark."
        )
    return "\n".join(lines) + "\n"


def self_test() -> int:
    vulkan = parse_log(SAMPLE_VULKAN)
    metal = parse_log(SAMPLE_METAL)
    text = render(vulkan, metal)
    errors = []
    first_line = text.splitlines()[0]
    if "steady-state" not in first_line:
        errors.append("title is not steady-state")
    if "first video packet" in first_line.lower():
        errors.append("first packet is the title")
    context_at = text.find("\nContext\n")
    decode_at = text.find("Decode submit")
    if decode_at < 0 or context_at < 0 or decode_at > context_at:
        errors.append("decode row is not ahead of Context")
    if "1.20 / 2.40 / 4.80" not in text:
        errors.append("vulkan decode percentiles missing")
    if "0.70 / 1.10 / 2.20" not in text:
        errors.append("metal decode percentiles missing")
    if "received first video packet after 900 ms" not in text:
        errors.append("vulkan first packet was dropped")
    if "received first video packet after 40 ms" not in text:
        errors.append("metal first packet was dropped")
    packet_at = text.find("after 900 ms")
    if packet_at >= 0 and packet_at < context_at:
        errors.append("first packet appears before Context")
    if "Warning:" in text:
        errors.append("matched samples should not warn")
    if "not glass-to-glass" not in text:
        errors.append("timing note missing")

    # A shorter first-packet wait must not become the headline just because
    # it is the smaller number. Metal's 40 ms is context; its present p50 is slower.
    if "8.30 / 16.70 / 33.40" not in text or "6.10 / 12.40 / 18.00" not in text:
        errors.append("present row missing")

    header = render(metal, vulkan).splitlines()[3]
    if header.find("Metal") < 0 or header.find("Vulkan") < 0 or header.find("Metal") > header.find("Vulkan"):
        errors.append("columns did not follow the log each file names")

    vulkan.metrics["resolution"] = "1280x720"
    mismatched = render(vulkan, metal)
    if "resolution differs" not in mismatched:
        errors.append("resolution mismatch was not reported")

    if errors:
        sys.stderr.write("pyrowave_ab_summary self-test failed:\n")
        for error in errors:
            sys.stderr.write(f"  {error}\n")
        return 1
    sys.stdout.write(text)
    sys.stdout.write("pyrowave_ab_summary self-test passed\n")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("logs", nargs="*", type=Path, help="two Moonlight logs, Vulkan and Metal")
    parser.add_argument("--self-test", action="store_true", help="parse the bundled sample logs and check the table")
    args = parser.parse_args()
    if args.self_test:
        return self_test()
    if len(args.logs) != 2:
        parser.error("pass two logs, or --self-test")
    for path in args.logs:
        if not path.is_file():
            sys.stderr.write(f"not a file: {path}\n")
            return 1
    sys.stdout.write(render(parse_log(args.logs[0]), parse_log(args.logs[1])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
