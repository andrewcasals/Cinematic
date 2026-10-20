"""Icon for Cinematic's talent calculator button: 64x64, a calculator on a
dark square, in the style of the game's icons. Our own, drawn from scratch
here; usage: make_calculator.py Textures/Calculator.tga"""
import sys
from PIL import Image, ImageDraw

N = 64
S = 4  # drawn this many times bigger, then shrunk, for smooth edges
OUT = sys.argv[1] if len(sys.argv) > 1 else "Calculator.tga"

big = Image.new("RGBA", (N * S, N * S))
draw = ImageDraw.Draw(big)


def box(x0, y0, x1, y1, fill, radius=0, outline=None, width=0):
    draw.rounded_rectangle([x0 * S, y0 * S, x1 * S - 1, y1 * S - 1], radius=radius * S,
                           fill=fill, outline=outline, width=width * S)


# The dark square behind, lighter towards the top, like an icon's.
for y in range(N * S):
    t = y / (N * S)
    shade = round(70 - 45 * t)
    draw.line([(0, y), (N * S - 1, y)], fill=(shade, round(shade * 0.8), round(shade * 0.55), 255))

# The calculator: its body, a shadow under it, the display and the keys.
box(15, 7, 51, 59, (0, 0, 0, 140), radius=6)
box(13, 5, 49, 57, (196, 178, 140, 255), radius=6, outline=(70, 55, 35, 255), width=1)
box(17, 9, 45, 21, (60, 78, 52, 255), radius=2, outline=(40, 35, 25, 255), width=1)
box(19, 11, 43, 19, (150, 196, 120, 255), radius=1)
for row in range(4):
    for col in range(4):
        x, y = 17 + col * 7.25, 25 + row * 7.75
        last = col == 3
        colour = (205, 120, 40, 255) if last else (95, 85, 70, 255)
        box(x, y, x + 5.5, y + 5.5, colour, radius=1, outline=(40, 32, 22, 255), width=1)
# Digits on the display: three bars.
for i in range(3):
    box(29 + i * 5, 13, 32 + i * 5, 17, (35, 50, 30, 255))

big.resize((N, N), Image.LANCZOS).save(OUT)
