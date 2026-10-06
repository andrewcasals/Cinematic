"""Cinematic addon icon: a brass spyglass on a sunset sky, with letterbox bars,
a lens flare and a gold frame. Drawn at 4x and scaled down for smooth edges."""
import math, sys
from PIL import Image, ImageDraw, ImageFilter

S = 1600            # working size (4x of 400)
OUT = sys.argv[1]


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def vertical_gradient(w, h, stops):
    img = Image.new("RGBA", (w, h))
    px = img.load()
    for y in range(h):
        t = y / (h - 1)
        for i in range(len(stops) - 1):
            if stops[i][0] <= t <= stops[i + 1][0]:
                lt = (t - stops[i][0]) / (stops[i + 1][0] - stops[i][0])
                c = lerp(stops[i][1], stops[i + 1][1], lt)
                break
        for x in range(w):
            px[x, y] = c
    return img


def rounded_mask(w, h, r):
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, w - 1, h - 1], r, fill=255)
    return m


# ---------------------------------------------------------------- sky
sky = vertical_gradient(S, S, [
    (0.0, (34, 22, 58, 255)),     # deep twilight purple
    (0.38, (92, 42, 92, 255)),
    (0.62, (214, 96, 62, 255)),   # ember orange
    (0.80, (250, 176, 82, 255)),  # golden horizon
    (1.0, (120, 56, 40, 255)),
])
# a soft sun glow low on the horizon
glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
gd = ImageDraw.Draw(glow)
for i in range(60, 0, -1):
    r = int(S * 0.32 * i / 60)
    a = int(150 * (1 - i / 60) ** 1.6)
    gd.ellipse([S * 0.66 - r, S * 0.74 - r, S * 0.66 + r, S * 0.74 + r], fill=(255, 214, 140, a))
sky = Image.alpha_composite(sky, glow)

# distant mountain silhouettes
mtn = Image.new("RGBA", (S, S), (0, 0, 0, 0))
md = ImageDraw.Draw(mtn)
md.polygon([(0, S * 0.80), (S * 0.18, S * 0.66), (S * 0.32, S * 0.75), (S * 0.47, S * 0.62),
            (S * 0.62, S * 0.76), (S * 0.80, S * 0.68), (S, S * 0.78), (S, S), (0, S)],
           fill=(58, 26, 44, 235))
md.polygon([(0, S * 0.88), (S * 0.25, S * 0.79), (S * 0.45, S * 0.86), (S * 0.70, S * 0.80),
            (S, S * 0.87), (S, S), (0, S)], fill=(32, 14, 28, 255))
sky = Image.alpha_composite(sky, mtn)

# a few stars in the upper sky
sd = ImageDraw.Draw(sky)
for (fx, fy, r) in [(0.14, 0.24, 5), (0.27, 0.18, 4), (0.44, 0.27, 3), (0.58, 0.20, 5),
                    (0.36, 0.34, 3), (0.20, 0.38, 3), (0.70, 0.30, 3)]:
    sd.ellipse([fx * S - r, fy * S - r, fx * S + r, fy * S + r], fill=(255, 244, 220, 230))

# ---------------------------------------------------------------- spyglass
# Drawn horizontally (eyepiece left, objective right), then rotated.
L = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ld = ImageDraw.Draw(L)
cy = S // 2


def tube(x0, x1, half, light=(255, 222, 140), dark=(126, 74, 22)):
    """A brass tube section with a top-lit cylindrical shading."""
    for y in range(-half, half + 1):
        t = (y + half) / (2 * half)            # 0 top .. 1 bottom
        shade = 1 - abs(t - 0.28) * 1.35       # highlight a little above centre
        shade = max(0.0, min(1.0, shade))
        c = lerp(dark, light, shade)
        ld.line([(x0, cy + y), (x1, cy + y)], fill=c + (255,))


def ring(x, half, w=26):
    for y in range(-half - 8, half + 9):
        t = (y + half + 8) / (2 * half + 16)
        shade = max(0.0, min(1.0, 1 - abs(t - 0.3) * 1.4))
        c = lerp((70, 36, 12), (230, 180, 96), shade)
        ld.line([(x - w // 2, cy + y), (x + w // 2, cy + y)], fill=c + (255,))


# eyepiece (narrow) -> middle -> wide objective barrel
tube(330, 560, 48)
tube(540, 840, 70)
tube(820, 1190, 96)
# flared objective hood
for i in range(0, 70):
    half = 96 + int(i * 0.6)
    t_light = (255, 230, 160)
    for y in range(-half, half + 1):
        t = (y + half) / (2 * half)
        shade = max(0.0, min(1.0, 1 - abs(t - 0.28) * 1.35))
        ld.point((1190 + i, cy + y), fill=lerp((120, 70, 20), t_light, shade) + (255,))
ring(335, 48, 22)
ring(560, 48)
ring(840, 70)
ring(1190, 96)
ring(1258, 138, 18)
# eyepiece cap
ld.rounded_rectangle([300, cy - 40, 342, cy + 40], 10, fill=(60, 30, 14, 255))
# leather grip wrap on the middle tube
for k in range(6):
    x = 600 + k * 38
    ld.polygon([(x, cy - 70), (x + 20, cy - 70), (x + 6, cy + 70), (x - 14, cy + 70)],
               fill=(92, 46, 26, 150))
# glass at the objective
ld.ellipse([1262, cy - 132, 1300, cy + 132], fill=(150, 210, 255, 255))
ld.ellipse([1270, cy - 96, 1292, cy - 10], fill=(235, 250, 255, 220))

# drop shadow for depth
shadow = L.split()[3].point(lambda a: int(a * 0.55))
shadow_img = Image.new("RGBA", (S, S), (20, 6, 14, 0))
shadow_img.putalpha(shadow)
shadow_img = shadow_img.filter(ImageFilter.GaussianBlur(22))

ANGLE = 32
L = L.rotate(ANGLE, resample=Image.BICUBIC, center=(S / 2, S / 2))
shadow_img = shadow_img.rotate(ANGLE, resample=Image.BICUBIC, center=(S / 2, S / 2))
offset = Image.new("RGBA", (S, S), (0, 0, 0, 0))
offset.paste(shadow_img, (18, 30), shadow_img)
art = Image.alpha_composite(sky, offset)
# shift the spyglass down-left a touch so the flare sits nicely
placed = Image.new("RGBA", (S, S), (0, 0, 0, 0))
placed.paste(L, (-30, 70), L)
art = Image.alpha_composite(art, placed)

# ---------------------------------------------------------------- lens flare
# where the objective glass ended up after rotation and the shift
ox, oy = 1281 - S / 2, 0
a = math.radians(ANGLE)
fx = S / 2 + ox * math.cos(a) - 30
fy = S / 2 - ox * math.sin(a) + 70
flare = Image.new("RGBA", (S, S), (0, 0, 0, 0))
fd = ImageDraw.Draw(flare)
for i in range(40, 0, -1):          # soft core
    r = 6 * i
    fd.ellipse([fx - r, fy - r, fx + r, fy + r], fill=(255, 240, 200, int(200 * (1 - i / 40) ** 2.2)))
for ang, length, width in [(0, 330, 12), (90, 330, 12), (45, 170, 6), (135, 170, 6)]:   # star spikes
    rad = math.radians(ang)
    dx, dy = math.cos(rad), math.sin(rad)
    px, py = -dy, dx
    fd.polygon([(fx - dx * length, fy - dy * length), (fx + px * width, fy + py * width),
                (fx + dx * length, fy + dy * length), (fx - px * width, fy - py * width)],
               fill=(255, 250, 230, 235))
flare = flare.filter(ImageFilter.GaussianBlur(3))
fd = ImageDraw.Draw(flare)
fd.ellipse([fx - 22, fy - 22, fx + 22, fy + 22], fill=(255, 255, 250, 255))
art = Image.alpha_composite(art, flare)

# ---------------------------------------------------------------- letterbox bars
bars = Image.new("RGBA", (S, S), (0, 0, 0, 0))
bd = ImageDraw.Draw(bars)
bar = int(S * 0.115)
bd.rectangle([0, 0, S, bar], fill=(6, 4, 8, 255))
bd.rectangle([0, S - bar, S, S], fill=(6, 4, 8, 255))
# thin gold accent lines inside the bars
bd.rectangle([0, bar - 10, S, bar - 4], fill=(212, 160, 70, 200))
bd.rectangle([0, S - bar + 4, S, S - bar + 10], fill=(212, 160, 70, 200))
art = Image.alpha_composite(art, bars)

# ---------------------------------------------------------------- gold frame
radius = int(S * 0.13)
frame = Image.new("RGBA", (S, S), (0, 0, 0, 0))
frd = ImageDraw.Draw(frame)
steps = [(0, (92, 56, 16)), (14, (250, 214, 120)), (30, (176, 118, 36)), (44, (255, 232, 150)),
         (56, (110, 66, 18))]
for inset, col in steps:
    frd.rounded_rectangle([inset, inset, S - 1 - inset, S - 1 - inset], radius - inset,
                          outline=col + (255,), width=16)
art = Image.alpha_composite(art, frame)

# clip everything to the rounded square and scale down
mask = rounded_mask(S, S, radius)
final = Image.new("RGBA", (S, S), (0, 0, 0, 0))
final.paste(art, (0, 0), mask)
final = final.resize((400, 400), Image.LANCZOS)
final.save(OUT)
print("saved", OUT)
