#!/usr/bin/env python3
"""A tiny GameStream HTTP stand-in for serverinfo, applist, launch, and cancel.

This speaks the unencrypted discovery port only. It does not perform the
pairing handshake, and it does not send video. The Qt tests parse the same
XML shape the client reads. Run it when you want to poke those endpoints
without a Windows host:

    python3 tests/mock_host.py --port 47989
"""

import argparse
import json
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse


SERVERINFO = """<?xml version="1.0"?>
<root status_code="200">
<hostname>MockHost</hostname>
<appversion>7.1.0</appversion>
<GfeVersion>3.23.0.74</GfeVersion>
<uniqueid>0123456789ABCDEF</uniqueid>
<HttpsPort>47984</HttpsPort>
<ExternalPort>{port}</ExternalPort>
<PairStatus>{paired}</PairStatus>
<state>{state}</state>
<currentgame>{game}</currentgame>
<LocalIP>127.0.0.1</LocalIP>
</root>
"""

APPLIST = """<?xml version="1.0"?>
<root status_code="200">
<App><AppTitle>Desktop</AppTitle><ID>881448767</ID><IsHdrSupported>1</IsHdrSupported></App>
<App><AppTitle>Game</AppTitle><ID>42</ID><IsHdrSupported>0</IsHdrSupported></App>
</root>
"""

OK = '<?xml version="1.0"?><root status_code="200"></root>'


class State:
    def __init__(self):
        self.paired = "1"
        self.game = 0
        self.port = 47989
        self.launches = []
        self.cancels = 0


STATE = State()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        return

    def _send(self, body, code=200):
        data = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/xml")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/serverinfo":
            state = "SUNSHINE_SERVER_BUSY" if STATE.game else "SUNSHINE_SERVER_FREE"
            self._send(SERVERINFO.format(port=STATE.port, paired=STATE.paired, state=state, game=STATE.game))
        elif path == "/applist":
            self._send(APPLIST)
        elif path == "/launch":
            STATE.game = 881448767
            STATE.launches.append(self.path)
            self._send(OK)
        elif path in ("/cancel", "/resume"):
            if path == "/cancel":
                STATE.cancels += 1
                STATE.game = 0
            self._send(OK)
        elif path == "/pair":
            STATE.paired = "1"
            self._send(OK)
        else:
            self._send('<?xml version="1.0"?><root status_code="404" status_message="Not found"></root>', 404)


def serve(port):
    STATE.port = port
    httpd = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    thread.start()
    return httpd


def main(argv):
    parser = argparse.ArgumentParser(description="GameStream HTTP stand-in")
    parser.add_argument("--port", type=int, default=47989)
    args = parser.parse_args(argv)
    httpd = serve(args.port)
    print(json.dumps({"host": "127.0.0.1", "port": args.port}))
    try:
        threading.Event().wait()
    except KeyboardInterrupt:
        httpd.shutdown()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
