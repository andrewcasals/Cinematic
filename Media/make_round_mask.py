"""Mask for Cinematic's campfire Sit button: 64x64, white, its alpha a square
with rounded, softened corners, so the icon under it has gentle edges.
Our own, made from scratch here; usage: make_round_mask.py Textures/RoundIcon.tga"""
import sys
from PIL import Image

N = 64
RADIUS = 14  # corner radius, pixels of N
SOFT = 2.0   # pixels the edge fades over
OUT = sys.argv[1] if len(sys.argv) > 1 else "RoundIcon.tga"


def alpha(x, y):
    # Distance outside the rounded square (negative inside), at pixel centres.
    px, py = x + 0.5, y + 0.5
    cx = min(max(px, RADIUS), N - RADIUS)
    cy = min(max(py, RADIUS), N - RADIUS)
    d = ((px - cx) ** 2 + (py - cy) ** 2) ** 0.5 - RADIUS
    # Fades from 1 at SOFT inside the edge to 0 at the edge.
    t = min(1.0, max(0.0, -d / SOFT))
    return round(255 * t * t * (3 - 2 * t))


image = Image.new("RGBA", (N, N))
image.putdata([(255, 255, 255, alpha(x, y)) for y in range(N) for x in range(N)])
image.save(OUT)
