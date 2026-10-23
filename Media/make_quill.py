"""Icon for the copy chat button (ChatCopy.lua): 64x64, a white quill on a
see-through background, slanted like one held to write. Our own, drawn from
scratch here; usage: make_quill.py Textures/Quill.tga"""
import math
import sys
from PIL import Image, ImageDraw

N = 64
S = 4  # drawn this many times bigger, then shrunk, for smooth edges
OUT = sys.argv[1] if len(sys.argv) > 1 else "Quill.tga"

big = Image.new("RGBA", (N * S, N * S), (0, 0, 0, 0))
draw = ImageDraw.Draw(big)

# The quill runs from its nib (bottom left) to its tip (top right), bending a
# little. Points along it are (t along, offset across), turned into the image.
NIB, TIP = (9, 56), (57, 6)
LENGTH = math.dist(NIB, TIP)
ALONG = ((TIP[0] - NIB[0]) / LENGTH, (TIP[1] - NIB[1]) / LENGTH)
ACROSS = (ALONG[1], -ALONG[0])  # (to the upper left of the shaft)
BEND = 3


def point(t, offset):
    offset += BEND * math.sin(t * math.pi)
    x = NIB[0] + ALONG[0] * t * LENGTH + ACROSS[0] * offset
    y = NIB[1] + ALONG[1] * t * LENGTH + ACROSS[1] * offset
    return (x * S, y * S)


def vane(start, sides, steps=40):
    """The feathered part: wider on one side, widest a little past the middle."""
    upper, lower = [], []
    for i in range(steps + 1):
        t = start + (1 - start) * i / steps
        u = (t - start) / (1 - start)
        width = math.sin(math.pi * u ** 0.8) * (1 - 0.25 * u)
        upper.append(point(t, sides[0] * width))
        lower.append(point(t, -sides[1] * width))
    return upper + lower[::-1]


# A soft shadow for contrast on light chat backgrounds, then the outline, the
# vane, a darker inner half and the shaft.
shadow = vane(0.3, (11, 6))
draw.polygon([(x + 1.5 * S, y + 1.5 * S) for x, y in shadow], fill=(0, 0, 0, 110))
draw.polygon(vane(0.3, (11, 6)), fill=(40, 34, 28, 255))
draw.polygon(vane(0.31, (9.6, 4.8)), fill=(246, 240, 226, 255))
draw.polygon(vane(0.34, (4.5, 0)), fill=(214, 206, 190, 255))
# A few notches where the barbs part.
for t, side in ((0.55, 1), (0.72, 1), (0.62, -1)):
    a = point(t, side * 10)
    b = point(t - 0.06, side * 3)
    draw.line([a, b], fill=(40, 34, 28, 255), width=int(1.2 * S))
shaft = [point(i / 40, 0) for i in range(41)]
draw.line(shaft, fill=(40, 34, 28, 255), width=int(2.6 * S), joint="curve")
draw.line(shaft[4:], fill=(222, 212, 192, 255), width=int(1.2 * S), joint="curve")
# The nib: brass, its point dipped in ink.
draw.line([point(0, 0), point(0.12, 0)], fill=(40, 34, 28, 255), width=int(3.4 * S))
draw.line([point(0.03, 0), point(0.11, 0)], fill=(214, 170, 80, 255), width=int(1.8 * S))

big.resize((N, N), Image.LANCZOS).save(OUT)
