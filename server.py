"""Team2 local dev server — static files with caching disabled.

Production will run on Vercel at https://team2.carloo.in; this is only for local editing.

Own port so Mono 1.0 (8123), Mono 2.0 (8124), Muthu's (8125) and Asset (8126)
can stay up alongside it.
"""
import http.server
import os

PORT = 8127
ROOT = os.path.dirname(os.path.abspath(__file__))


class NoCacheHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=ROOT, **kwargs)

    def end_headers(self):
        self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        super().end_headers()


if __name__ == "__main__":
    with http.server.ThreadingHTTPServer(("", PORT), NoCacheHandler) as httpd:
        print(f"Team2 serving {ROOT} at http://127.0.0.1:{PORT}/")
        httpd.serve_forever()
