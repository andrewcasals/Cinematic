"""Corner piece for Cinematic's vignettes (Tint.lua): 128x128, white, its alpha
rising from clear at the top-left to full at the bottom-right edges, by the
distance from that corner, eased so it starts and ends without a crease. One
quarter of a rounded vignette: flipped for each corner, and its first row or
column stretched along the edges between them.
Our own, made from scratch here; usage: make_vignette.py Textures/Vignette.tga"""
import sys
from PIL import Image

N = 128
OUT = sys.argv[1] if len(sys.argv) > 1 else "Vignette.tga"


def alpha(x, y):
    # 0 at the first pixel, 1 at the last, so the edge rows sample exactly.
    u, v = x / (N - 1), y / (N - 1)
    t = min(1.0, (u * u + v * v) ** 0.5)
    return round(255 * t * t * (3 - 2 * t))


image = Image.new("RGBA", (N, N))
image.putdata([(255, 255, 255, alpha(x, y)) for y in range(N) for x in range(N)])
image.save(OUT)
