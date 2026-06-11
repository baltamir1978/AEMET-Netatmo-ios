#!/usr/bin/env python3
"""Generate AppPersonal app icons (light/dark/tinted) in the flat-green style
shared with the sibling apps (BirdApp / RadioApp).

Motif: a classic weather glyph — amber sun peeking behind a white cloud with
rain drops — on an emerald vertical gradient. Run:

    python3 Tools/generate_icon.py

Outputs the three 1024×1024 PNGs into the AppIcon.appiconset.
"""
import os
from PIL import Image, ImageDraw

SS = 4                      # supersampling factor for smooth edges
N = 1024
S = N * SS
OUT = os.path.join(os.path.dirname(__file__), "..",
                   "AppPersonal/Assets.xcassets/AppIcon.appiconset")

# (gradient_top, gradient_bottom, sun, cloud, drop) per variant
VARIANTS = {
    "AppIcon.png":        ((0x37, 0xD0, 0x94), (0x0B, 0x6F, 0x53),
                           (0xFF, 0xC5, 0x3D), (0xFF, 0xFF, 0xFF), (0xFF, 0xFF, 0xFF)),
    "AppIcon-dark.png":   ((0x0E, 0x3D, 0x2C), (0x06, 0x14, 0x0F),
                           (0xE8, 0xB2, 0x4A), (0xF2, 0xF5, 0xF3), (0xF2, 0xF5, 0xF3)),
    "AppIcon-tinted.png": ((0x0B, 0x0B, 0x0B), (0x1C, 0x1C, 0x1C),
                           (0xCF, 0xCF, 0xCF), (0xFF, 0xFF, 0xFF), (0xFF, 0xFF, 0xFF)),
}


def vgradient(top, bottom):
    img = Image.new("RGB", (S, S))
    d = ImageDraw.Draw(img)
    for y in range(S):
        t = y / (S - 1)
        c = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
        d.line([(0, y), (S, y)], fill=c)
    return img


def s(v):
    return int(v * SS)


def circle(d, cx, cy, r, fill):
    d.ellipse([s(cx - r), s(cy - r), s(cx + r), s(cy + r)], fill=fill)


def rrect(d, x0, y0, x1, y1, rad, fill):
    d.rounded_rectangle([s(x0), s(y0), s(x1), s(y1)], radius=s(rad), fill=fill)


def drop(d, cx, top, fill):
    # Teardrop: pointed top via triangle + rounded bottom via circle.
    r = 30
    circle(d, cx, top + 58, r, fill)
    d.polygon([(s(cx), s(top)), (s(cx - r), s(top + 62)), (s(cx + r), s(top + 62))], fill=fill)


def build(top, bottom, sun, cloud, dropc):
    img = vgradient(top, bottom)
    d = ImageDraw.Draw(img)

    # Sun (upper-right), drawn first so the cloud overlaps and "hides" part of it.
    circle(d, 700, 355, 140, sun)

    # Cloud (white) — union of puffs over a flat rounded base.
    rrect(d, 250, 545, 715, 660, 58, cloud)
    circle(d, 340, 565, 95, cloud)
    circle(d, 460, 495, 130, cloud)
    circle(d, 590, 520, 108, cloud)
    circle(d, 665, 565, 92, cloud)

    # Rain drops below the cloud.
    for cx in (385, 500, 615):
        drop(d, cx, 705, dropc)

    return img.resize((N, N), Image.LANCZOS)


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, (top, bottom, sun, cloud, dropc) in VARIANTS.items():
        out = os.path.join(OUT, name)
        build(top, bottom, sun, cloud, dropc).save(out)
        print("wrote", os.path.relpath(out))


if __name__ == "__main__":
    main()
