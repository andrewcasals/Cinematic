"""Depth-of-field haze for Cinematic: 512x512, stretched over the whole screen.
Clear in the middle, rising to a soft milky haze toward the edges and corners.
The haze is lumpy, low-frequency noise, so over the scene it flattens the
contrast unevenly and reads as out of focus rather than as a plain darkening."""
import math, random, sys
from PIL import Image, ImageFilter

N = 512
OUT = sys.argv[1] if len(sys.argv) > 1 else "Focus.tga"
random.seed(7)

# Lumpy noise: a coarse random grid, blown up and blurred heavily.
coarse = Image.new("L", (32, 32))
coarse.putdata([random.randint(0, 255) for _ in range(32 * 32)])
noise = coarse.resize((N, N), Image.BICUBIC).filter(ImageFilter.GaussianBlur(18))
px = list(noise.getdata())
lo, hi = min(px), max(px)
lumps = [(p - lo) / (hi - lo) for p in px]

CLEAR = 0.45  # radius (0 centre, 1 edge midpoint) that stays sharp
FULL = 1.15   # radius where the haze is at full strength (past the corners' 1.41 it holds)

def smooth(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)

data = []
for y in range(N):
    for x in range(N):
        dx, dy = (x + 0.5) / N * 2 - 1, (y + 0.5) / N * 2 - 1
        r = math.hypot(dx, dy)
        lump = lumps[y * N + x]
        mask = smooth((r - CLEAR) / (FULL - CLEAR))
        alpha = mask * (0.7 + 0.3 * lump)
        # A soft, slightly cool mid-grey: lifts the darks, dims the lights.
        g = 0.42 + 0.16 * lump
        data.append((int(g * 245), int(g * 250), int(g * 255), int(alpha * 255)))

img = Image.new("RGBA", (N, N))
img.putdata(data)
img.save(OUT)
