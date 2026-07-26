#!/usr/bin/env python3
"""Simple HTTP server that dumps all request variables as JSON for /auth/callback."""

import json
import os
import sys
import urllib.parse
from datetime import datetime
from http.server import BaseHTTPRequestHandler, HTTPServer
from socketserver import ThreadingMixIn


class CallbackHandler(BaseHTTPRequestHandler):
    """Handles /auth/callback and prints all request variables as JSON."""

    def _build_response_dict(self):
        """Parse request and return a dict with all variables."""
        query_params = {}
        parsed = urllib.parse.urlparse(self.path)
        if parsed.query:
            for k, v in urllib.parse.parse_qsl(parsed.query):
                query_params.setdefault(k, []).append(v)

        cookies = {}
        raw_cookies = self.headers.get("Cookie", "")
        for part in raw_cookies.split(";"):
            part = part.strip()
            if "=" in part:
                k, v = part.split("=", 1)
                cookies[k.strip()] = v.strip()

        body_str = None
        content_length = self.headers.get("Content-Length")
        if content_length:
            try:
                length = int(content_length)
                if length > 0:
                    raw_body = self.rfile.read(length)
                    body_str = raw_body.decode("utf-8", errors="replace")
            except (ValueError, OSError):
                pass

        return {
            "method": self.command,
            "path": parsed.path,
            "query_string": parsed.query,
            "query_params": query_params,
            "headers": dict(self.headers),
            "cookies": cookies,
            "body": body_str,
            "client_address": self.client_address,
        }

    def _save_to_disk(self, data):
        """Save JSON data to a timestamped file in auth_logs/."""
        log_dir = "auth_logs"
        os.makedirs(log_dir, exist_ok=True)
        ts = datetime.now().strftime("%Y%m%d_%H%M%S_%f")
        filename = os.path.join(log_dir, f"callback_{ts}.json")
        with open(filename, "w") as f:
            json.dump(data, f, indent=2, ensure_ascii=False)
            f.write("\n")

    def _respond_json(self, data, status_code=200):
        """Send data as JSON HTTP response."""
        body = json.dumps(data, indent=2, ensure_ascii=False).encode("utf-8") + b"\n"
        self.send_response(status_code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path.startswith("/auth/callback"):
            data = self._build_response_dict()
            self._save_to_disk(data)
            # Redirect browser/client to the teslahorn:// deep link with the original query params
            parsed = urllib.parse.urlparse(self.path)
            redirect_url = "teslahorn://callback"
            if parsed.query:
                redirect_url += "?" + parsed.query
            self.send_response(302)
            self.send_header("Location", redirect_url)
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
        else:
            self.send_error(404)

    def do_POST(self):
        if self.path.startswith("/auth/callback"):
            data = self._build_response_dict()
            self._save_to_disk(data)
            self._respond_json(data)
        else:
            self.send_error(404)

    def do_OPTIONS(self):
        if self.path.startswith("/auth/callback"):
            self.send_response(204)
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
            self.send_header("Access-Control-Allow-Headers", "*")
            self.end_headers()
        else:
            self.send_error(404)

    def log_message(self, format, *args):
        sys.stderr.write("[auth_callback] %s - %s\n" % (self.client_address[0], format % args))


class ThreadedHTTPServer(ThreadingMixIn, HTTPServer):
    """Handle requests in separate threads."""
    allow_reuse_address = True
    daemon_threads = True


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 9000
    server = ThreadedHTTPServer(("127.0.0.1", port), CallbackHandler)
    print("auth_callback server listening on 127.0.0.1:%d" % port, flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down...")
        server.server_close()


if __name__ == "__main__":
    main()
