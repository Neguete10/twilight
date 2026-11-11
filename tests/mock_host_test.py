#!/usr/bin/env python3
"""Exercise the local GameStream stand-in. No GPU and no real host."""

import sys
import urllib.request
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))

import mock_host

FAILURES = 0


def expect(condition, label):
    global FAILURES
    if not condition:
        print("FAIL", label)
        FAILURES += 1


def body(port, path):
    with urllib.request.urlopen("http://127.0.0.1:%d%s" % (port, path), timeout=5) as response:
        return response.status, response.read().decode("utf-8")


def main():
    httpd = mock_host.serve(0)
    port = httpd.server_address[1]
    try:
        status, info = body(port, "/serverinfo")
        expect(status == 200, "serverinfo status")
        expect("<PairStatus>1</PairStatus>" in info, "serverinfo starts paired")
        expect("SUNSHINE_SERVER_FREE" in info, "serverinfo is idle")
        expect("<currentgame>0</currentgame>" in info, "no game is current")

        status, apps = body(port, "/applist")
        expect(status == 200 and "<AppTitle>Desktop</AppTitle>" in apps, "applist contains Desktop")
        expect("<ID>881448767</ID>" in apps, "Desktop keeps the Sunshine id")

        status, launch = body(port, "/launch?appid=881448767")
        expect(status == 200 and 'status_code="200"' in launch, "launch is accepted")
        _, busy = body(port, "/serverinfo")
        expect("SUNSHINE_SERVER_BUSY" in busy, "launch marks the host busy")
        expect("<currentgame>881448767</currentgame>" in busy, "launch records the current game")

        status, cancel = body(port, "/cancel")
        expect(status == 200, "cancel is accepted")
        _, idle = body(port, "/serverinfo")
        expect("SUNSHINE_SERVER_FREE" in idle, "cancel returns the host to idle")
        expect(mock_host.STATE.cancels == 1, "cancel was counted")
    finally:
        httpd.shutdown()

    if FAILURES:
        print("%d failure(s)" % FAILURES)
        return 1
    print("ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
