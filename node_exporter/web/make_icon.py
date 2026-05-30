#!/usr/bin/env python3
"""Generate the app icon (128x128 PNG) using only the Python standard library.

A dark tile with a small bar chart in Prometheus orange — a non-trademarked nod
to a metrics exporter. Run: ``python3 make_icon.py [out.png]``.
"""

import struct
import sys
import zlib

WIDTH = HEIGHT = 128
BG = (38, 40, 48)          # dark slate
BAR = (230, 82, 44)        # prometheus orange
BASELINE = (90, 94, 104)   # muted axis line


def _png_chunk(tag, data):
    body = tag + data
    return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)


def make_png(width, height, pixels):
    """Encode an RGB pixel list (length width*height) as PNG bytes."""
    raw = bytearray()
    for y in range(height):
        raw.append(0)  # filter type 0 (None) for this scanline
        for x in range(width):
            raw += bytes(pixels[y * width + x])
    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)  # 8-bit, color type 2 (RGB)
    idat = zlib.compress(bytes(raw), 9)
    return sig + _png_chunk(b"IHDR", ihdr) + _png_chunk(b"IDAT", idat) + _png_chunk(b"IEND", b"")


def _fill(px, x0, y0, x1, y1, color):
    for y in range(max(0, y0), min(HEIGHT, y1)):
        for x in range(max(0, x0), min(WIDTH, x1)):
            px[y * WIDTH + x] = color


def render():
    px = [BG] * (WIDTH * HEIGHT)
    # Four bars of increasing-then-varied height, like a metrics graph.
    heights = (40, 70, 54, 88)
    bar_w = 16
    gap = 12
    total = len(heights) * bar_w + (len(heights) - 1) * gap
    x = (WIDTH - total) // 2
    base = 100  # baseline y
    for h in heights:
        _fill(px, x, base - h, x + bar_w, base, BAR)
        x += bar_w + gap
    # Baseline axis.
    _fill(px, 20, base, WIDTH - 20, base + 3, BASELINE)
    return px


def main(path):
    with open(path, "wb") as fh:
        fh.write(make_png(WIDTH, HEIGHT, render()))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "node_exporter.png")
