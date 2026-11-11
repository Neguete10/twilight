#!/usr/bin/env python3
"""Stream a matrix of settings against a real host, from a Mac .app you pass in.

This does not build Twilight and it does not touch /Applications. Preferences
in com.moonlight-stream.Moonlight are exported before the run and imported
again afterwards, including when a case fails.

    python3 scripts/e2e/stream_matrix.py \\
        --app build/Twilight.app \\
        --host 192.168.1.20 \\
        --game Desktop

The script reads the client's stderr. A launched .app with a live terminal
logs there instead of ~/Library/Logs/Moonlight. Crash reports are still
taken from ~/Library/Logs/DiagnosticReports.

Video quality, controller rumble, and microphone sound are not judged here.
A screenshot and the log excerpt are saved under the report directory.
"""

import argparse
import json
import os
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path

DOMAIN = "com.moonlight-stream.Moonlight"
CRASH_DIR = Path.home() / "Library" / "Logs" / "DiagnosticReports"


def fail(message):
    raise RuntimeError(message)


def crash_reports_since(started):
    if not CRASH_DIR.exists():
        return []
    found = []
    for path in CRASH_DIR.iterdir():
        name = path.name.lower()
        if "twilight" not in name and "moonlight" not in name:
            continue
        if path.stat().st_mtime >= started:
            found.append(str(path))
    return found


def launch(command, log_path):
    process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )
    log_path.parent.mkdir(parents=True, exist_ok=True)
    handle = log_path.open("w", encoding="utf-8")

    def pump():
        for line in process.stdout:
            handle.write(line)
            handle.flush()
        handle.close()

    threading.Thread(target=pump, daemon=True).start()
    return process


def wait_for_text(path, token, timeout):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if path.exists():
            text = path.read_text(encoding="utf-8", errors="replace")
            if token in text:
                return text
        time.sleep(0.4)
    fail("stream did not log %r within %ss" % (token, timeout))


def stop_process(process):
    if process.poll() is None:
        process.send_signal(signal.SIGTERM)
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)


class Matrix:
    def __init__(self, args):
        self.args = args
        self.app = Path(args.app).resolve()
        self.binary = self.app / "Contents" / "MacOS" / "Twilight"
        self.report_dir = Path(args.report).resolve()
        self.results = []
        self.backup = None
        self.had_prefs = False

    def check_app(self):
        if sys.platform != "darwin":
            fail("this script drives a Mac .app and only runs on macOS")
        resolved = str(self.app)
        if resolved == "/Applications" or resolved.startswith("/Applications/"):
            fail("refusing to touch an app under /Applications; pass the build product")
        if not self.binary.is_file():
            fail("missing executable %s" % self.binary)

    def save_prefs(self):
        self.report_dir.mkdir(parents=True, exist_ok=True)
        self.backup = self.report_dir / "preferences-backup.plist"
        exported = subprocess.run(
            ["defaults", "export", DOMAIN, str(self.backup)],
            text=True, capture_output=True)
        self.had_prefs = exported.returncode == 0
        if not self.had_prefs and self.backup.exists():
            self.backup.unlink()

    def restore_prefs(self):
        if self.had_prefs and self.backup and self.backup.exists():
            subprocess.run(["defaults", "import", DOMAIN, str(self.backup)], check=False)
        elif not self.had_prefs:
            subprocess.run(["defaults", "delete", DOMAIN], check=False)

    def write_metal_fx(self, enabled):
        subprocess.run(
            ["defaults", "write", DOMAIN, "metalfxupscaling", "-bool", "true" if enabled else "false"],
            check=True)

    def cases(self):
        return [
            {"name": "hevc-sdr-vsync", "args": ["--1080", "--video-codec", "HEVC", "--vsync", "--no-hdr"], "metalfx": False, "need": ["format 0x100", "Using Metal renderer"]},
            {"name": "hevc-sdr-metalfx-720", "args": ["--720", "--video-codec", "HEVC", "--no-vsync", "--no-hdr"], "metalfx": True, "need": ["format 0x100", "Using Metal renderer", "MetalFX spatial upscaling active"]},
            {"name": "hevc-hdr", "args": ["--1080", "--video-codec", "HEVC", "--hdr", "--vsync"], "metalfx": False, "need": ["format 0x200", "Using Metal renderer"]},
            {"name": "h264-sdr", "args": ["--1080", "--video-codec", "H.264", "--no-hdr"], "metalfx": False, "need": ["format 0x1", "Using Metal renderer"]},
            {"name": "av1-sdr", "args": ["--1080", "--video-codec", "AV1", "--no-hdr"], "metalfx": False, "need": ["format 0x1000"]},
            {"name": "quit-app-on-host", "args": ["--1080", "--video-codec", "HEVC", "--quit-after", "--no-hdr"], "metalfx": False, "need": ["Video stream is "]},
            {"name": "sigterm", "args": ["--1080", "--video-codec", "HEVC", "--no-hdr"], "metalfx": False, "need": ["Video stream is "], "sigterm": True},
        ]

    def finish(self, process, case, log_path, started):
        shot = self.report_dir / ("%s.png" % case["name"])
        subprocess.run(["screencapture", "-x", str(shot)], check=False)
        if case.get("sigterm"):
            process.send_signal(signal.SIGTERM)
        elif case.get("host_end"):
            subprocess.run(self.args.host_end_command, shell=True, check=True, timeout=30)
        else:
            subprocess.run([str(self.binary), "quit", self.args.host], check=False, timeout=30)
        try:
            code = process.wait(timeout=30)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=5)
            fail("stream process did not exit")
        text = log_path.read_text(encoding="utf-8", errors="replace") if log_path.exists() else ""
        missing = [token for token in case["need"] if token not in text]
        crashes = crash_reports_since(started)
        if missing:
            fail("log missing: %s" % ", ".join(missing))
        if crashes:
            fail("crash reports: %s" % ", ".join(crashes))
        if not case.get("sigterm") and code != 0:
            fail("exit code %s" % code)
        perf = "\n".join(
            line for line in text.splitlines()
            if "bitrate" in line.lower() or "GPU" in line or "MetalFX" in line or "Video stream is" in line
        )
        (self.report_dir / ("%s.log.txt" % case["name"])).write_text(perf, encoding="utf-8")
        return {"name": case["name"], "status": "pass", "exit": code, "screenshot": str(shot)}

    def one(self, case):
        started = time.time()
        self.write_metal_fx(case["metalfx"])
        log_path = self.report_dir / ("%s.stderr" % case["name"])
        command = [str(self.binary), "stream", self.args.host, self.args.game] + case["args"]
        process = launch(command, log_path)
        try:
            wait_for_text(log_path, "Video stream is ", self.args.start_timeout)
            time.sleep(self.args.seconds)
            return self.finish(process, case, log_path, started)
        finally:
            stop_process(process)

    def host_ended(self):
        if not self.args.host_end_command:
            return {
                "name": "host-ended",
                "status": "skip",
                "note": "pass --host-end-command to stop the stream from the host",
            }
        case = {
            "name": "host-ended",
            "args": ["--1080", "--video-codec", "HEVC", "--no-hdr"],
            "metalfx": False,
            "need": ["Video stream is "],
            "host_end": True,
        }
        return self.one(case)

    def execute(self):
        self.check_app()
        self.save_prefs()
        try:
            for case in self.cases():
                try:
                    self.results.append(self.one(case))
                    print("PASS", case["name"])
                except Exception as error:
                    self.results.append({"name": case["name"], "status": "fail", "note": str(error)})
                    print("FAIL", case["name"], error)
            try:
                result = self.host_ended()
                self.results.append(result)
                print(result["status"].upper(), result["name"], result.get("note", ""))
            except Exception as error:
                self.results.append({"name": "host-ended", "status": "fail", "note": str(error)})
                print("FAIL host-ended", error)
        finally:
            self.restore_prefs()
        summary = {
            "app": str(self.app),
            "host": self.args.host,
            "game": self.args.game,
            "results": self.results,
        }
        (self.report_dir / "report.json").write_text(json.dumps(summary, indent=2), encoding="utf-8")
        lines = ["# Stream matrix", "", "| Case | Result | Note |", "| --- | --- | --- |"]
        for result in self.results:
            lines.append("| %s | %s | %s |" % (
                result["name"], result["status"], result.get("note", "").replace("|", "/")))
        (self.report_dir / "report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
        failed = [result for result in self.results if result["status"] == "fail"]
        print("%d passed, %d failed, %d skipped" % (
            sum(1 for result in self.results if result["status"] == "pass"),
            len(failed),
            sum(1 for result in self.results if result["status"] == "skip")))
        return 1 if failed else 0


def main(argv):
    parser = argparse.ArgumentParser(description="Run a Twilight stream matrix against a LAN host")
    parser.add_argument("--app", required=True, help="Path to Twilight.app (not under /Applications)")
    parser.add_argument("--host", required=True, help="Host name, UUID, or IP already paired on this Mac")
    parser.add_argument("--game", default="Desktop", help="App name on the host")
    parser.add_argument("--seconds", type=int, default=8, help="How long to leave each stream up")
    parser.add_argument("--start-timeout", type=int, default=45, dest="start_timeout")
    parser.add_argument("--report", default="build/e2e-report")
    parser.add_argument(
        "--host-end-command",
        default=os.environ.get("TWILIGHT_HOST_END_COMMAND", ""),
        help="Shell command that makes the host end the current stream",
    )
    args = parser.parse_args(argv)
    try:
        return Matrix(args).execute()
    except RuntimeError as error:
        print("FAIL", error)
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
