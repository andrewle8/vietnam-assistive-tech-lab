#!/usr/bin/env python
"""
readmate_web.py - minimal HTTP server that exposes Readmate's EPUB library
through Firefox + foliate-js so NVDA browse mode can read the books.

Mirrors the kiwix-serve / SilverDict pattern. Reads books in-place from
%APPDATA%\\SaoMai\\SM Readmate\\file\\<publisher>\\*.epub. SM Readmate
stays installed and untouched; this is a parallel, NVDA-friendly entry
point.

Routes:
    GET /                  -> book list (HTML, server-rendered)
    GET /read?b=<rel>      -> reader page wrapping <foliate-view>
    GET /epub?b=<rel>      -> EPUB byte stream (Range-aware)
    GET /static/<path>     -> foliate-js, CSS, fonts

Library root and port are constants below; READMATE_WEB_LIBRARY env var
overrides for tests.
"""
import html
import mimetypes
import os
import re
import sys
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

PORT = 21810
HOST = "127.0.0.1"

ROOT = Path(__file__).resolve().parent
LIBRARY_ROOT = Path(r"C:\Users\Student\AppData\Roaming\SaoMai\SM Readmate\file")
TEMPLATES = ROOT / "templates"
STATIC_ROOT = ROOT  # foliate-js + style.css served from here

if os.environ.get("READMATE_WEB_LIBRARY"):
    LIBRARY_ROOT = Path(os.environ["READMATE_WEB_LIBRARY"]).resolve()

mimetypes.add_type("application/javascript", ".js")
mimetypes.add_type("application/javascript", ".mjs")
mimetypes.add_type("application/wasm", ".wasm")
mimetypes.add_type("application/epub+zip", ".epub")
mimetypes.add_type("font/woff2", ".woff2")
mimetypes.add_type("font/woff", ".woff")


def title_from_filename(name: str) -> str:
    base = name[:-5] if name.lower().endswith(".epub") else name
    return base.replace("_", " ")


def list_books():
    """Walk LIBRARY_ROOT one level deep. Returns dict {publisher: [(rel_path, title), ...]}."""
    if not LIBRARY_ROOT.is_dir():
        return {}
    out = {}
    for pub_dir in sorted(LIBRARY_ROOT.iterdir(), key=lambda p: p.name.lower()):
        if not pub_dir.is_dir():
            continue
        books = []
        for f in sorted(pub_dir.glob("*.epub"), key=lambda p: p.name.lower()):
            rel = f.relative_to(LIBRARY_ROOT).as_posix()
            books.append((rel, title_from_filename(f.name)))
        if books:
            out[pub_dir.name] = books
    return out


def resolve_book(rel_path: str):
    """Return absolute Path if rel_path is a valid book under LIBRARY_ROOT, else None."""
    if not rel_path:
        return None
    try:
        full = (LIBRARY_ROOT / rel_path).resolve()
    except (ValueError, OSError):
        return None
    try:
        full.relative_to(LIBRARY_ROOT.resolve())
    except ValueError:
        return None
    if full.suffix.lower() != ".epub" or not full.is_file():
        return None
    return full


def render_template(name: str, **kwargs) -> bytes:
    text = (TEMPLATES / name).read_text(encoding="utf-8")
    for k, v in kwargs.items():
        text = text.replace("{{" + k + "}}", v)
    return text.encode("utf-8")


def render_index() -> bytes:
    parts = []
    books = list_books()
    if not books:
        parts.append(
            '<p>Không tìm thấy sách trong thư viện. '
            'Hãy kiểm tra thư mục SM Readmate.</p>'
        )
    else:
        total = sum(len(b) for b in books.values())
        parts.append(f'<p class="meta">{total} cuốn sách trong {len(books)} bộ.</p>')
        for publisher, items in books.items():
            parts.append(f'<section aria-labelledby="pub-{html.escape(publisher)}">')
            parts.append(
                f'<h2 id="pub-{html.escape(publisher)}">{html.escape(publisher)}</h2>'
            )
            parts.append('<ul class="books">')
            for rel, title in items:
                href = "/read?b=" + urllib.parse.quote(rel)
                parts.append(
                    f'<li><a lang="vi" href="{html.escape(href)}">'
                    f'{html.escape(title)}</a></li>'
                )
            parts.append('</ul></section>')
    return render_template("index.html", PUBLISHERS="\n".join(parts))


class Handler(BaseHTTPRequestHandler):
    server_version = "ReadmateWeb/1.0"

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    def _send(self, status, body=b"", content_type="text/html; charset=utf-8"):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        if body:
            self.wfile.write(body)

    def _send_stream(self, path, content_type):
        size = path.stat().st_size
        range_hdr = self.headers.get("Range")
        if range_hdr:
            m = re.match(r"bytes=(\d+)-(\d+)?", range_hdr)
            if m:
                start = int(m.group(1))
                end = int(m.group(2)) if m.group(2) else size - 1
                end = min(end, size - 1)
                if start > end or start >= size:
                    self.send_response(416)
                    self.send_header("Content-Range", f"bytes */{size}")
                    self.end_headers()
                    return
                length = end - start + 1
                self.send_response(206)
                self.send_header("Content-Type", content_type)
                self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
                self.send_header("Accept-Ranges", "bytes")
                self.send_header("Content-Length", str(length))
                self.end_headers()
                with path.open("rb") as f:
                    f.seek(start)
                    remaining = length
                    while remaining > 0:
                        chunk = f.read(min(65536, remaining))
                        if not chunk:
                            break
                        self.wfile.write(chunk)
                        remaining -= len(chunk)
                return
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(size))
        self.send_header("Accept-Ranges", "bytes")
        self.end_headers()
        with path.open("rb") as f:
            while True:
                chunk = f.read(65536)
                if not chunk:
                    break
                self.wfile.write(chunk)

    def do_GET(self):
        try:
            parsed = urllib.parse.urlparse(self.path)
            path = parsed.path
            qs = urllib.parse.parse_qs(parsed.query)

            if path == "/":
                return self._send(200, render_index())

            if path == "/read":
                rel = (qs.get("b") or [""])[0]
                book = resolve_book(rel)
                if not book:
                    return self._send(400, b"Bad book reference",
                                      "text/plain; charset=utf-8")
                title = title_from_filename(book.name)
                epub_url = "/epub?b=" + urllib.parse.quote(rel)
                body = render_template(
                    "read.html",
                    BOOK_TITLE=html.escape(title),
                    EPUB_URL=html.escape(epub_url, quote=True),
                )
                return self._send(200, body)

            if path == "/epub":
                rel = (qs.get("b") or [""])[0]
                book = resolve_book(rel)
                if not book:
                    return self._send(400, b"Bad book reference",
                                      "text/plain; charset=utf-8")
                return self._send_stream(book, "application/epub+zip")

            if path.startswith("/static/"):
                sub = path[len("/static/"):]
                if not sub or ".." in sub.split("/"):
                    return self._send(404, b"Not found",
                                      "text/plain; charset=utf-8")
                try:
                    target = (STATIC_ROOT / sub).resolve()
                    target.relative_to(STATIC_ROOT.resolve())
                except (ValueError, OSError):
                    return self._send(404, b"Not found",
                                      "text/plain; charset=utf-8")
                if not target.is_file():
                    return self._send(404, b"Not found",
                                      "text/plain; charset=utf-8")
                ctype, _ = mimetypes.guess_type(target.name)
                return self._send_stream(target, ctype or "application/octet-stream")

            return self._send(404, b"Not found",
                              "text/plain; charset=utf-8")
        except (BrokenPipeError, ConnectionResetError):
            # Client disconnected mid-stream (Firefox cancels Range requests
            # when the user navigates away). Not actionable.
            pass


def main():
    server = ThreadingHTTPServer((HOST, PORT), Handler)
    sys.stderr.write(f"readmate-web listening on http://{HOST}:{PORT}/\n")
    sys.stderr.write(f"library: {LIBRARY_ROOT}\n")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        sys.stderr.write("shutting down\n")
        server.shutdown()


if __name__ == "__main__":
    main()
