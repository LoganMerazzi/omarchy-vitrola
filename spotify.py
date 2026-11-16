#!/usr/bin/env python3
"""Spotify Web API helper for the Vitrola shell plugin.

Talks to the Web API with the user's own app (Authorization Code + PKCE, no
client secret) and prints JSON for Panel.qml. Standard library only.

  spotify.py login <client_id>        one-time browser login
  spotify.py status                   {"ok", "user"}
  spotify.py shelf <section> [query]  playlists | albums | foryou | search
  spotify.py tracks <type> <id>       album | playlist | artist
  spotify.py play <context_uri> [track_uri]
"""

import base64
import hashlib
import html
import http.server
import json
import os
import secrets
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

STATE_DIR = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "vitrola")
TOKEN_FILE = os.path.join(STATE_DIR, "token.json")
REDIRECT_PORT = 8977
REDIRECT_URI = f"http://127.0.0.1:{REDIRECT_PORT}/callback"
API = "https://api.spotify.com/v1"
ACCOUNTS = "https://accounts.spotify.com"
SCOPES = " ".join([
    "playlist-read-private",
    "playlist-read-collaborative",
    "user-library-read",
    "user-top-read",
    "user-read-recently-played",
    "user-read-playback-state",
    "user-modify-playback-state",
])
TIMEOUT = 12
MAX_BYTES = 4 * 1024 * 1024
MAX_TEXT = 200


class ApiError(Exception):
    def __init__(self, message, status=0):
        super().__init__(message)
        self.status = status


def out(obj):
    sys.stdout.write(json.dumps(obj, ensure_ascii=False))
    sys.stdout.write("\n")


def text(value):
    return str(value or "")[:MAX_TEXT]


# ── Token storage ───────────────────────────────────────────────────────────

def load_token():
    try:
        with open(TOKEN_FILE, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def save_token(tok):
    os.makedirs(STATE_DIR, mode=0o700, exist_ok=True)
    tmp = TOKEN_FILE + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(tok, f)
    os.replace(tmp, TOKEN_FILE)


def post_form(url, data):
    body = urllib.parse.urlencode(data).encode()
    req = urllib.request.Request(url, data=body, method="POST",
                                 headers={"Content-Type": "application/x-www-form-urlencoded"})
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            return json.loads(r.read(MAX_BYTES).decode())
    except urllib.error.HTTPError as e:
        detail = e.read(4096).decode(errors="replace")
        raise ApiError(f"token request failed ({e.code}): {detail[:200]}", e.code)


def access_token():
    tok = load_token()
    if not tok or not tok.get("refresh_token") or not tok.get("client_id"):
        raise ApiError("login", 401)
    if tok.get("expires_at", 0) - 60 > time.time():
        return tok["access_token"]
    fresh = post_form(ACCOUNTS + "/api/token", {
        "grant_type": "refresh_token",
        "refresh_token": tok["refresh_token"],
        "client_id": tok["client_id"],
    })
    tok["access_token"] = fresh["access_token"]
    tok["expires_at"] = time.time() + int(fresh.get("expires_in", 3600))
    if fresh.get("refresh_token"):
        tok["refresh_token"] = fresh["refresh_token"]
    save_token(tok)
    return tok["access_token"]


# ── Login (PKCE) ────────────────────────────────────────────────────────────

def login(client_id):
    if not client_id or not client_id.isalnum() or len(client_id) > 64:
        raise ApiError("invalid client id")
    verifier = secrets.token_urlsafe(64)[:96]
    challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
    state = secrets.token_urlsafe(16)
    url = ACCOUNTS + "/authorize?" + urllib.parse.urlencode({
        "response_type": "code",
        "client_id": client_id,
        "scope": SCOPES,
        "redirect_uri": REDIRECT_URI,
        "code_challenge_method": "S256",
        "code_challenge": challenge,
        "state": state,
    })
    result = {}

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
            if not self.path.startswith("/callback"):
                self.send_response(404)
                self.end_headers()
                return
            if q.get("state", [""])[0] != state:
                result["error"] = "state mismatch"
            elif "error" in q:
                result["error"] = q["error"][0]
            else:
                result["code"] = q.get("code", [""])[0]
            ok = "code" in result
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            msg = "Vitrola conectada ao Spotify. Pode fechar esta aba." if ok else "Falha no login: " + text(result.get("error"))
            self.wfile.write(f"<html><body style='font-family:sans-serif;padding:3em'><h2>{html.escape(msg)}</h2></body></html>".encode())

        def log_message(self, *args):
            pass

    server = http.server.HTTPServer(("127.0.0.1", REDIRECT_PORT), Handler)
    server.timeout = 1
    print("Abrindo o navegador para o login do Spotify...\nSe não abrir, acesse:\n" + url, file=sys.stderr)
    subprocess.Popen(["xdg-open", url], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    deadline = time.time() + 300
    while not result and time.time() < deadline:
        server.handle_request()
    server.server_close()
    if "code" not in result:
        raise ApiError("login failed: " + text(result.get("error", "timeout")))

    tok = post_form(ACCOUNTS + "/api/token", {
        "grant_type": "authorization_code",
        "code": result["code"],
        "redirect_uri": REDIRECT_URI,
        "client_id": client_id,
        "code_verifier": verifier,
    })
    save_token({
        "client_id": client_id,
        "access_token": tok["access_token"],
        "refresh_token": tok["refresh_token"],
        "expires_at": time.time() + int(tok.get("expires_in", 3600)),
        "scope": tok.get("scope", ""),
    })
    me = api("GET", "/me")
    return {"ok": True, "user": text(me.get("display_name") or me.get("id"))}


# ── Web API ─────────────────────────────────────────────────────────────────

def api(method, path, params=None, body=None, retry=True):
    url = path if path.startswith("http") else API + path
    if not url.startswith(API):
        raise ApiError("unexpected url")
    if params:
        url += ("&" if "?" in url else "?") + urllib.parse.urlencode(params)
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers={
        "Authorization": "Bearer " + access_token(),
        "Content-Type": "application/json",
    })
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
            raw = r.read(MAX_BYTES)
            return json.loads(raw.decode()) if raw.strip() else {}
    except urllib.error.HTTPError as e:
        if e.code == 401 and retry:
            tok = load_token() or {}
            tok["expires_at"] = 0
            save_token(tok)
            return api(method, path, params, body, retry=False)
        detail = ""
        try:
            detail = json.loads(e.read(4096).decode()).get("error", {}).get("message", "")
        except Exception:
            pass
        raise ApiError(f"{e.code} {detail}".strip(), e.code)
    except urllib.error.URLError as e:
        raise ApiError("network: " + text(e.reason))


def pages(path, params, limit_total):
    items, url, first = [], path, True
    while url and len(items) < limit_total:
        page = api("GET", url, params if first else None)
        first = False
        items.extend(page.get("items") or [])
        url = page.get("next")
    return items[:limit_total]


def image(images):
    imgs = [i for i in (images or []) if i and i.get("url", "").startswith("https://")]
    if not imgs:
        return ""
    # Smallest that is still at least 300px, else the largest there is.
    imgs.sort(key=lambda i: i.get("width") or 0)
    for i in imgs:
        if (i.get("width") or 0) >= 300:
            return i["url"]
    return imgs[-1]["url"]


def card(kind, obj, subtitle, group=""):
    return {
        "type": kind,
        "id": text(obj.get("id")),
        "uri": text(obj.get("uri")),
        "name": text(obj.get("name")),
        "subtitle": text(subtitle),
        "image": image(obj.get("images")),
        "group": group,
    }


def artists_of(obj):
    return ", ".join(a.get("name", "") for a in (obj.get("artists") or []))


def shelf(section, query=""):
    items = []
    if section == "playlists":
        for p in pages("/me/playlists", {"limit": 50}, 200):
            if not p:
                continue
            owner = (p.get("owner") or {}).get("display_name") or ""
            items.append(card("playlist", p, owner))
    elif section == "albums":
        for s in pages("/me/albums", {"limit": 50}, 200):
            a = (s or {}).get("album") or {}
            if a:
                items.append(card("album", a, artists_of(a)))
    elif section == "foryou":
        seen = set()
        for a in api("GET", "/me/top/artists", {"limit": 12, "time_range": "short_term"}).get("items") or []:
            items.append(card("artist", a, "Artista que você mais ouve", "top"))
        recent = api("GET", "/me/player/recently-played", {"limit": 50}).get("items") or []
        for r in recent:
            a = ((r or {}).get("track") or {}).get("album") or {}
            if a.get("id") and a["id"] not in seen:
                seen.add(a["id"])
                items.append(card("album", a, artists_of(a), "recent"))
        for t in api("GET", "/me/top/tracks", {"limit": 30, "time_range": "medium_term"}).get("items") or []:
            a = (t or {}).get("album") or {}
            if a.get("id") and a["id"] not in seen:
                seen.add(a["id"])
                items.append(card("album", a, artists_of(a), "top-tracks"))
    elif section == "search":
        query = query.strip()[:100]
        if query:
            res = api("GET", "/search", {"q": query, "type": "album,artist,playlist", "limit": 10})
            for a in (res.get("artists") or {}).get("items") or []:
                if a:
                    items.append(card("artist", a, "Artista"))
            for a in (res.get("albums") or {}).get("items") or []:
                if a:
                    items.append(card("album", a, artists_of(a)))
            for p in (res.get("playlists") or {}).get("items") or []:
                if p:
                    items.append(card("playlist", p, (p.get("owner") or {}).get("display_name") or ""))
    else:
        raise ApiError("unknown section")
    return {"ok": True, "section": section, "items": items}


def track_row(t, number=0):
    return {
        "uri": text(t.get("uri")),
        "name": text(t.get("name")),
        "artists": text(artists_of(t)),
        "duration": int(t.get("duration_ms") or 0) // 1000,
        "number": number or int(t.get("track_number") or 0),
    }


def tracks(kind, item_id):
    if not item_id.isalnum() or len(item_id) > 64:
        raise ApiError("invalid id")
    rows = []
    if kind == "album":
        info = api("GET", f"/albums/{item_id}")
        for t in pages(f"/albums/{item_id}/tracks", {"limit": 50}, 200):
            if t:
                rows.append(track_row(t))
        return {"ok": True, "name": text(info.get("name")), "subtitle": text(artists_of(info)),
                "image": image(info.get("images")), "uri": text(info.get("uri")), "tracks": rows}
    if kind == "playlist":
        info = api("GET", f"/playlists/{item_id}", {"fields": "name,uri,images,owner(display_name)"})
        # Development-mode apps may only list the items of playlists the
        # user owns; someone else's playlist still plays as a whole.
        locked = False
        try:
            entries = pages(f"/playlists/{item_id}/items", {"limit": 50}, 200)
        except ApiError as e:
            if e.status != 403:
                raise
            entries, locked = [], True
        n = 0
        for e in entries:
            t = (e or {}).get("item") or (e or {}).get("track") or {}
            if t.get("uri", "").startswith("spotify:track:"):
                n += 1
                rows.append(track_row(t, n))
        return {"ok": True, "name": text(info.get("name")),
                "subtitle": text((info.get("owner") or {}).get("display_name")),
                "image": image(info.get("images")), "uri": text(info.get("uri")), "tracks": rows,
                "locked": locked}
    if kind == "artist":
        # Top tracks are closed to new apps; show the discography instead.
        # Each row is an album that opens its own back cover.
        info = api("GET", f"/artists/{item_id}")
        for a in pages(f"/artists/{item_id}/albums", {"include_groups": "album,single", "limit": 10}, 60):
            if not a:
                continue
            rows.append({
                "uri": text(a.get("uri")),
                "id": text(a.get("id")),
                "type": "album",
                "name": text(a.get("name")),
                "artists": text(str(a.get("release_date") or "")[:4] + (" · single" if a.get("album_type") == "single" else "")),
                "duration": 0,
                "number": 0,
                "image": image(a.get("images")),
            })
        return {"ok": True, "name": text(info.get("name")), "subtitle": "Discografia",
                "image": image(info.get("images")), "uri": text(info.get("uri")), "tracks": rows}
    raise ApiError("unknown type")


def pick_device():
    devices = api("GET", "/me/player/devices").get("devices") or []
    for d in devices:
        if d.get("is_active"):
            return d
    host = os.uname().nodename.lower()
    for d in devices:
        if (d.get("type") or "").lower() == "computer" and host in (d.get("name") or "").lower():
            return d
    for d in devices:
        if (d.get("type") or "").lower() == "computer":
            return d
    return devices[0] if devices else None


def play(context_uri, track_uri=""):
    for u in (context_uri, track_uri):
        if u and not u.startswith("spotify:"):
            raise ApiError("invalid uri")
    device = pick_device()
    if not device:
        raise ApiError("no-device")
    body = {}
    if context_uri.startswith("spotify:artist:"):
        body = {"uris": [track_uri]} if track_uri else {"context_uri": context_uri}
    elif context_uri:
        body = {"context_uri": context_uri}
        if track_uri:
            body["offset"] = {"uri": track_uri}
    elif track_uri:
        body = {"uris": [track_uri]}
    api("PUT", "/me/player/play", {"device_id": device["id"]}, body)
    return {"ok": True, "device": text(device.get("name"))}


def main(argv):
    if not argv:
        print(__doc__, file=sys.stderr)
        return 2
    cmd, args = argv[0], argv[1:]
    try:
        if cmd == "login":
            out(login(args[0] if args else ""))
        elif cmd == "status":
            me = api("GET", "/me")
            out({"ok": True, "user": text(me.get("display_name") or me.get("id"))})
        elif cmd == "shelf":
            out(shelf(args[0] if args else "playlists", " ".join(args[1:])))
        elif cmd == "tracks":
            out(tracks(args[0], args[1]))
        elif cmd == "play":
            out(play(args[0] if args else "", args[1] if len(args) > 1 else ""))
        else:
            raise ApiError("unknown command")
    except ApiError as e:
        out({"ok": False, "error": str(e), "status": e.status})
        return 1
    except (IndexError, KeyError) as e:
        out({"ok": False, "error": "bad request: " + text(e)})
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
