#!/usr/bin/env python3
"""Stream a matrix of settings against a real host, from a Mac .app you pass in.

This does not build Twilight and it does not touch /Applications. Preferences
in com.moonlight-stream.Moonlight are exported before the run and imported
again afterwards, including when a case fails. A failed export aborts before
any preference is written, and the domain is never deleted.

The stream is ended with SIGTERM. During the stream loop that signal is the
client's own quit and the process should exit 0. `Twilight quit` is a second
process that tells the host to cancel; the stream then logs
"Connection terminated: -1" and the CLI exits 1. That is a host drop, not a
client disconnect, so this script does not use it while the stream is up.

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


class CaseFailure(RuntimeError):
    def __init__(self, message, screenshot="", exit_code=None):
        super().__init__(message)
        self.screenshot = screenshot or ""
        self.exit_code = exit_code


def fail(message, screenshot="", exit_code=None):
    raise CaseFailure(message, screenshot, exit_code)


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


def running_twilight():
    """Return (pid, executable path) for each Twilight binary already running."""
    result = subprocess.run(["ps", "-ax", "-o", "pid=,command="], capture_output=True, text=True)
    found = []
    for line in result.stdout.splitlines():
        text = line.strip()
        if not text:
            continue
        pid, _, command = text.partition(" ")
        command = command.strip()
        if not pid.isdigit() or not command:
            continue
        executable = command.split()[0]
        if executable.rsplit("/", 1)[-1] == "Twilight":
            found.append((int(pid), executable))
    return found


def host_port_open(host):
    import socket
    for port in (47989, 47984):
        try:
            with socket.create_connection((host, port), timeout=3):
                return port
        except OSError:
            continue
    return None


def main_display_pixels():
    source = """
import AppKit
guard let screen = NSScreen.main else { exit(1) }
let scale = screen.backingScaleFactor
print(Int((screen.frame.width * scale).rounded()))
print(Int((screen.frame.height * scale).rounded()))
"""
    result = subprocess.run(["swift", "-e", source], capture_output=True, text=True, timeout=120)
    if result.returncode != 0:
        return None
    numbers = [int(line) for line in result.stdout.split() if line.isdigit()]
    if len(numbers) < 2:
        return None
    return numbers[0], numbers[1]


def window_id_for_pid(pid):
    source = """
import CoreGraphics
let pid = Int32(%d)
let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as! [[String: Any]]
var best = 0
var bestArea = 0
for window in info {
    guard let owner = window[kCGWindowOwnerPID as String] as? Int32, owner == pid else { continue }
    let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
    let width = bounds["Width"] ?? 0
    let height = bounds["Height"] ?? 0
    let area = Int(width * height)
    let number = window[kCGWindowNumber as String] as? Int ?? 0
    if area > bestArea && number != 0 {
        bestArea = area
        best = number
    }
}
if best == 0 { exit(1) }
print(best)
""" % pid
    result = subprocess.run(["swift", "-e", source], capture_output=True, text=True, timeout=120)
    if result.returncode != 0:
        return None
    token = result.stdout.strip().split()
    if not token or not token[-1].isdigit():
        return None
    return int(token[-1])


def plist_xml(path):
    result = subprocess.run(
        ["plutil", "-convert", "xml1", "-o", "-", str(path)],
        check=True, capture_output=True)
    return result.stdout


class Matrix:
    def __init__(self, args):
        self.args = args
        self.app = Path(args.app).resolve()
        self.binary = self.app / "Contents" / "MacOS" / "Twilight"
        self.report_dir = Path(args.report).resolve()
        self.results = []
        self.backup = None
        self.backup_xml = None
        self.prefs_changed = False
        self.screen = None

    def check_app(self):
        if sys.platform != "darwin":
            fail("this script drives a Mac .app and only runs on macOS")
        resolved = str(self.app)
        if resolved == "/Applications" or resolved.startswith("/Applications/"):
            fail("refusing to touch an app under /Applications; pass the build product")
        if not self.binary.is_file():
            fail("missing executable %s" % self.binary)

    def check_not_running(self):
        running = running_twilight()
        if running:
            details = ", ".join("pid %d %s" % (pid, path) for pid, path in running)
            fail("Twilight is already running (%s). Quit it before this matrix so two copies do not share one preferences file." % details)

    def check_host(self):
        for attempt in range(1, 4):
            port = host_port_open(self.args.host)
            if port is not None:
                print("Host %s accepts TCP %d" % (self.args.host, port))
                return
            if attempt < 3:
                print("Host %s did not accept TCP 47989 or 47984 (try %d of 3). Retrying in 10s." % (self.args.host, attempt))
                time.sleep(10)
        fail("Cannot reach %s on TCP 47989 or 47984 after 3 tries. Those are the GameStream ports. Preferences were not changed." % self.args.host)

    def save_prefs(self):
        self.report_dir.mkdir(parents=True, exist_ok=True)
        self.backup = self.report_dir / "preferences-backup.plist"
        exported = subprocess.run(
            ["defaults", "export", DOMAIN, str(self.backup)],
            text=True, capture_output=True)
        if exported.returncode != 0 or not self.backup.is_file() or self.backup.stat().st_size == 0:
            if self.backup.exists():
                self.backup.unlink()
            self.backup = None
            fail("Could not export %s. Preferences were not changed.\n%s" % (DOMAIN, exported.stderr.strip()))
        subprocess.run(["plutil", "-lint", str(self.backup)], check=True)
        self.backup_xml = plist_xml(self.backup)
        print("Preference backup kept at %s" % self.backup)

    def restore_prefs(self):
        if not self.prefs_changed:
            return
        if self.backup is None or not self.backup.is_file() or self.backup_xml is None:
            fail("Preferences were changed but there is no verified backup. %s was not deleted." % DOMAIN)
        if plist_xml(self.backup) != self.backup_xml:
            fail("The backup at %s no longer matches what was exported. %s was not imported or deleted." % (self.backup, DOMAIN))
        subprocess.run(["defaults", "import", DOMAIN, str(self.backup)], check=True)
        restored = self.report_dir / "preferences-restored.plist"
        subprocess.run(["defaults", "export", DOMAIN, str(restored)], check=True)
        if plist_xml(restored) != self.backup_xml:
            fail("Restored preferences do not match %s. That backup file was left on disk." % self.backup)
        print("Preferences restored from %s" % self.backup)

    def write_metal_fx(self, enabled):
        self.prefs_changed = True
        subprocess.run(
            ["defaults", "write", DOMAIN, "metalfxupscaling", "-bool", "true" if enabled else "false"],
            check=True)

    def cases(self):
        metal = {
            "name": "hevc-sdr-metalfx",
            "args": ["--720", "--video-codec", "HEVC", "--no-vsync", "--no-hdr"],
            "metalfx": True,
            "need": ["format 0x100", "Using Metal renderer"],
            "forbid": ["MetalFX spatial upscaling active", "Connection terminated:"],
            "note": "display size was not detected; MetalFX activation is not required",
        }
        if self.screen:
            width, height = self.screen
            stream_w = (width * 2 // 3) // 2 * 2
            stream_h = (height * 2 // 3) // 2 * 2
            if stream_w >= 640 and stream_h >= 360 and stream_w < width and stream_h < height:
                metal["args"] = ["--resolution", "%dx%d" % (stream_w, stream_h), "--video-codec", "HEVC", "--no-vsync", "--no-hdr"]
                metal["need"] = ["format 0x100", "Using Metal renderer", "MetalFX spatial upscaling active"]
                metal["forbid"] = ["Connection terminated:"]
                metal["note"] = "stream %dx%d is smaller than the %dx%d display" % (stream_w, stream_h, width, height)
            else:
                metal["note"] = "display %dx%d is not larger than a usable stream in both dimensions" % (width, height)
        return [
            {"name": "hevc-sdr-vsync", "args": ["--1080", "--video-codec", "HEVC", "--vsync", "--no-hdr"], "metalfx": False, "need": ["format 0x100", "Using Metal renderer"], "forbid": ["MetalFX spatial upscaling active", "Connection terminated:"]},
            metal,
            {"name": "hevc-hdr", "args": ["--1080", "--video-codec", "HEVC", "--hdr", "--vsync"], "metalfx": False, "need": ["format 0x200", "Using Metal renderer"], "forbid": ["MetalFX spatial upscaling active", "Connection terminated:"]},
            {"name": "h264-sdr", "args": ["--1080", "--video-codec", "H.264", "--no-hdr"], "metalfx": False, "need": ["format 0x1", "Using Metal renderer"], "forbid": ["MetalFX spatial upscaling active", "Connection terminated:"]},
            {"name": "av1-sdr", "args": ["--1080", "--video-codec", "AV1", "--no-hdr"], "metalfx": False, "need": ["format 0x1000"], "forbid": ["MetalFX spatial upscaling active", "Connection terminated:"]},
            {"name": "quit-app-on-host", "args": ["--1080", "--video-codec", "HEVC", "--quit-after", "--no-hdr"], "metalfx": False, "need": ["Video stream is ", "Quit response:"], "forbid": ["Connection terminated:"], "quit_host": True},
            {"name": "sigterm", "args": ["--1080", "--video-codec", "HEVC", "--no-hdr"], "metalfx": False, "need": ["Video stream is "], "forbid": ["Connection terminated:"]},
        ]

    def host_running_game(self):
        result = subprocess.run(
            [str(self.binary), "list", self.args.host],
            capture_output=True, text=True, timeout=40)
        if result.returncode != 0:
            fail("list exited %s\n%s" % (result.returncode, result.stderr.strip()))
        for line in result.stdout.splitlines():
            if line.startswith("Running:"):
                return line.split(":", 1)[1].strip()
        fail("list did not print a Running: line")

    def stop_host_app(self):
        # The stream process has already exited. This only clears the host
        # app so the next case is a fresh launch.
        result = subprocess.run(
            [str(self.binary), "quit", self.args.host],
            capture_output=True, text=True, timeout=40)
        if result.returncode != 0:
            detail = (result.stderr or result.stdout).strip()
            fail("Twilight quit exited %s after the stream process had already ended.\n%s" % (result.returncode, detail))

    def finish(self, process, case, log_path, started):
        shot = self.report_dir / ("%s.png" % case["name"])
        shot_path = ""
        code = None
        try:
            window_id = window_id_for_pid(process.pid)
            if window_id is None:
                fail("Could not find the Twilight window to screenshot")
            subprocess.run(["screencapture", "-x", "-l", str(window_id), str(shot)], check=True)
            shot_path = str(shot)
            if case.get("host_end"):
                subprocess.run(self.args.host_end_command, shell=True, check=True, timeout=30)
            else:
                # SIGTERM during the stream loop posts SDL_QUIT. That is the
                # client's own quit, so the CLI should exit 0. Twilight quit
                # while this process is still connected cancels the host
                # session instead, and the client exits 1.
                process.send_signal(signal.SIGTERM)
            try:
                code = process.wait(timeout=30)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
                fail("stream process did not exit", screenshot=shot_path)
            text = log_path.read_text(encoding="utf-8", errors="replace") if log_path.exists() else ""
            missing = [token for token in case.get("need", []) if token not in text]
            forbidden = [token for token in case.get("forbid", []) if token in text]
            crashes = crash_reports_since(started)
            if missing:
                fail("log missing: %s" % ", ".join(missing), screenshot=shot_path, exit_code=code)
            if forbidden:
                fail("log should not contain: %s" % ", ".join(forbidden), screenshot=shot_path, exit_code=code)
            if crashes:
                fail("crash reports: %s" % ", ".join(crashes), screenshot=shot_path, exit_code=code)
            if not case.get("host_end") and code != 0:
                fail("exit code %s" % code, screenshot=shot_path, exit_code=code)
            if case.get("quit_host"):
                running = self.host_running_game()
                if running != "none":
                    fail("host app list still shows a running game: %s" % running, screenshot=shot_path, exit_code=code)
            else:
                self.stop_host_app()
            perf = "\n".join(
                line for line in text.splitlines()
                if "bitrate" in line.lower() or "GPU" in line or "MetalFX" in line or "Video stream is" in line or "Quit response:" in line
            )
            (self.report_dir / ("%s.log.txt" % case["name"])).write_text(perf, encoding="utf-8")
            return {"name": case["name"], "status": "pass", "exit": code, "screenshot": shot_path, "note": case.get("note", "")}
        except CaseFailure as error:
            if not error.screenshot:
                error.screenshot = shot_path
            if error.exit_code is None:
                error.exit_code = code
            raise

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
                "exit": None,
                "screenshot": "",
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
        self.check_not_running()
        self.check_host()
        self.screen = main_display_pixels()
        if self.screen:
            print("Main display %dx%d" % self.screen)
        self.save_prefs()
        try:
            for case in self.cases():
                try:
                    self.results.append(self.one(case))
                    print("PASS", case["name"])
                except Exception as error:
                    self.results.append(self.failure_row(case["name"], error))
                    print("FAIL", case["name"], error)
            try:
                result = self.host_ended()
                self.results.append(result)
                print(result["status"].upper(), result["name"], result.get("note", ""))
            except Exception as error:
                self.results.append(self.failure_row("host-ended", error))
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

    def failure_row(self, name, error):
        screenshot = ""
        exit_code = None
        if isinstance(error, CaseFailure):
            screenshot = error.screenshot
            exit_code = error.exit_code
        return {
            "name": name,
            "status": "fail",
            "note": str(error),
            "exit": exit_code,
            "screenshot": screenshot,
        }


def main(argv):
    parser = argparse.ArgumentParser(description="Run a Twilight stream matrix against a LAN host")
    parser.add_argument("--app", required=True, help="Path to Twilight.app (not under /Applications)")
    parser.add_argument("--host", required=True, help="Paired host name or IP that accepts TCP 47989 or 47984")
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
