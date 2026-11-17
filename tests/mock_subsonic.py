#!/usr/bin/env python3
"""A small Subsonic server for tests: it checks the token like Navidrome does (md5(password + salt)) and answers the calls
the hi-fi makes with canned data. No real music: stream and cover art are a few bytes.

    python3 tests/mock_subsonic.py [port]     # user "u", password "pw"
"""
import hashlib
import json
import sys
import urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer

USER, PASSWORD = "u", "pw"
ALBUMS = [{"id": "al1", "name": "Arrival", "artist": "ABBA", "artistId": "ar1", "coverArt": "al1", "year": 1976, "songCount": 2}]
SONGS = [{"id": "s1", "title": "Knowing Me", "artist": "ABBA", "album": "Arrival", "track": 1, "duration": 240, "suffix": "mp3", "size": 5, "coverArt": "al1"},
         {"id": "s2", "title": "Dancing Queen", "artist": "ABBA", "album": "Arrival", "track": 2, "duration": 231, "suffix": "mp3", "size": 5, "coverArt": "al1"}]


def ok(body):
    return {"subsonic-response": dict({"status": "ok", "version": "1.16.1"}, **body)}


def fail(code, msg):
    return {"subsonic-response": {"status": "failed", "version": "1.16.1", "error": {"code": code, "message": msg}}}


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        q = {k: v[0] for k, v in urllib.parse.parse_qs(u.query).items()}
        if not u.path.startswith("/rest/"):
            self.send_response(404); self.end_headers(); return
        ep = u.path[len("/rest/"):].removesuffix(".view")
        good = q.get("u") == USER and q.get("t") == hashlib.md5((PASSWORD + q.get("s", "")).encode()).hexdigest()
        if not good:
            return self.send(fail(40, "Wrong username or password"))
        b = {
            "ping": {},
            "getArtists": {"artists": {"index": [{"name": "A", "artist": [{"id": "ar1", "name": "ABBA", "albumCount": 1}]}]}},
            "getArtist": {"artist": {"id": "ar1", "name": "ABBA", "album": ALBUMS}},
            "getAlbumList2": {"albumList2": {"album": ALBUMS}},
            "getAlbum": {"album": dict(ALBUMS[0], song=SONGS)},
            "getPlaylists": {"playlists": {"playlist": []}},
            "search3": {"searchResult3": {"artist": [], "album": ALBUMS, "song": SONGS}},
            "getInternetRadioStations": {"internetRadioStations": {"internetRadioStation": [{"id": "r1", "name": "Mock FM", "streamUrl": "http://127.0.0.1:9/live.mp3"}]}},
        }.get(ep)
        if ep in ("stream", "getCoverArt", "download"):
            self.send_response(200); self.send_header("Content-Type", "application/octet-stream"); self.end_headers(); self.wfile.write(b"x" * 20000); return
        if b is None:
            return self.send(fail(70, "not found"))
        self.send(ok(b))

    def send(self, obj):
        data = json.dumps(obj).encode()
        self.send_response(200); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(data))); self.end_headers(); self.wfile.write(data)


if __name__ == "__main__":
    HTTPServer(("127.0.0.1", int(sys.argv[1]) if len(sys.argv) > 1 else 4533), H).serve_forever()
