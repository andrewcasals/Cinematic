"""Talent calculator art, our own, made from scratch here: the talents'
shape as the talents window draws it, a square with its corners cut off,
for clients without the talents window's own borders.
Usage: make_talent_ring.py Textures  (writes TalentRing.tga there)

TalentRing.tga  64x64, white (tinted in the game: green when it can take a
                point, gold at full rank, dark grey when not): the border,
                with a thin dark line either side. The shape sits 6 pixels in
                from the edges."""
import os
import sys
from PIL import Image

N = 64
MARGIN = 6    # room round the shape
CUT = 0.17    # the corners cut off, as a share of the shape's width
BAND = 4.0    # the border, pixels of N
LINE = 1.2    # the dark lines either side of it
OUT = sys.argv[1] if len(sys.argv) > 1 else "."


def inside(x, y, margin):
    # How far inside the shape (negative outside), at a pixel centre.
    half = (N - 2 * margin) / 2
    cut = CUT * 2 * half
    ax, ay = abs(x - N / 2), abs(y - N / 2)
    return min(half - ax, half - ay, (2 * half - cut - ax - ay) / 2 ** 0.5)


def cover(d):
    return min(1.0, max(0.0, d + 0.5))


def save(name, pixel):
    image = Image.new("RGBA", (N, N))
    image.putdata([pixel(x + 0.5, y + 0.5) for y in range(N) for x in range(N)])
    image.save(os.path.join(OUT, name))


def ring(x, y):
    d = inside(x, y, MARGIN)
    band = cover(d) * (1 - cover(d - BAND))
    dark = (cover(d + LINE) * (1 - cover(d))) + (cover(d - BAND) * (1 - cover(d - BAND - LINE)))
    alpha = min(1.0, band + dark * 0.85)
    shade = 255 * band / alpha if alpha > 0 else 0
    return (round(shade), round(shade), round(shade), round(255 * alpha))


save("TalentRing.tga", ring)
