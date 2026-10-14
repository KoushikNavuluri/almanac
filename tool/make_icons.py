#!/usr/bin/env python3
"""Renders Almanac's app icon (navy sky, rising sun, drifting cloud) into every PNG the
platforms need. Run after `flutter create` so the iOS AppIcon set exists:
    python3 tool/make_icons.py
Android uses the adaptive vector icon committed in android/app/src/main/res; this script also
refreshes the legacy mipmap PNGs and writes store/branding PNGs."""
import json
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

NAVY = (23, 39, 103)
TEAL = (25, 121, 139)
SUN = (243, 213, 103)
AMBER = (238, 155, 67)
CRIMSON = (184, 4, 34)
CLOUD = (248, 249, 252)
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def render(size, rounded=False):
    s = 1024
    img = Image.new("RGB", (s, s), NAVY)
    px = img.load()
    for y in range(s):
        t = y / (s - 1)
        if t < 0.62:
            k = t / 0.62
            c = tuple(int(NAVY[i] + (TEAL[i] - NAVY[i]) * k) for i in range(3))
        else:
            k = (t - 0.62) / 0.38
            c = tuple(int(TEAL[i] + (AMBER[i] - TEAL[i]) * k) for i in range(3))
        for x in range(s):
            px[x, y] = c
    iso = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(iso)
    for i in range(4):
        y0 = 250 + i * 150
        pts = [(x, y0 + 26 * math.sin(x / 120 + i)) for x in range(0, s + 8, 8)]
        d.line(pts, fill=(248, 249, 252, 40), width=6)
    img.paste(iso, (0, 0), iso)
    glow = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    cx, cy = 600, 400
    gd.ellipse((cx - 300, cy - 300, cx + 300, cy + 300), fill=(243, 213, 103, 120))
    glow = glow.filter(ImageFilter.GaussianBlur(90))
    img.paste(glow, (0, 0), glow)
    d = ImageDraw.Draw(img)
    for i in range(12):
        a = i / 12 * math.tau
        x1, y1 = cx + math.cos(a) * 165, cy + math.sin(a) * 165
        x2, y2 = cx + math.cos(a) * 215, cy + math.sin(a) * 215
        d.line((x1, y1, x2, y2), fill=SUN, width=30)
        for (x, y) in ((x1, y1), (x2, y2)):
            d.ellipse((x - 15, y - 15, x + 15, y + 15), fill=SUN)
    d.ellipse((cx - 120, cy - 120, cx + 120, cy + 120), fill=SUN)
    cl = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    c = ImageDraw.Draw(cl)
    for (x, y, r) in ((330, 640, 120), (470, 580, 150), (610, 650, 110)):
        c.ellipse((x - r, y - r, x + r, y + r), fill=CLOUD + (255,))
    c.rounded_rectangle((210, 610, 720, 760), radius=60, fill=CLOUD + (255,))
    shadow = cl.filter(ImageFilter.GaussianBlur(24))
    sh = Image.new("RGBA", (s, s), (18, 24, 56, 0))
    sh.putalpha(shadow.split()[3].point(lambda v: int(v * 0.35)))
    img.paste(sh, (0, 18), sh)
    img.paste(cl, (0, 0), cl)
    d.rectangle((0, 900, s, 1024), fill=CRIMSON)
    out = img.resize((size, size), Image.LANCZOS)
    if rounded:
        mask = Image.new("L", (size * 4, size * 4), 0)
        ImageDraw.Draw(mask).ellipse((0, 0, size * 4 - 1, size * 4 - 1), fill=255)
        mask = mask.resize((size, size), Image.LANCZOS)
        rgba = out.convert("RGBA")
        rgba.putalpha(mask)
        return rgba
    return out


def save(img, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, optimize=True)
    print("wrote", os.path.relpath(path, ROOT))


def main():
    save(render(1024), os.path.join(ROOT, "assets/branding/icon-1024.png"))
    save(render(512), os.path.join(ROOT, "assets/branding/play-store-512.png"))
    res = os.path.join(ROOT, "android/app/src/main/res")
    if os.path.isdir(res):
        for folder, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
            save(render(px), os.path.join(res, f"mipmap-{folder}", "ic_launcher.png"))
            save(render(px, rounded=True), os.path.join(res, f"mipmap-{folder}", "ic_launcher_round.png"))
    iconset = os.path.join(ROOT, "ios/Runner/Assets.xcassets/AppIcon.appiconset")
    contents = os.path.join(iconset, "Contents.json")
    if os.path.isfile(contents):
        with open(contents) as f:
            spec = json.load(f)
        for im in spec.get("images", []):
            name = im.get("filename")
            if not name:
                continue
            pts = float(im["size"].split("x")[0])
            scale = float(im.get("scale", "1x").rstrip("x"))
            save(render(int(round(pts * scale))), os.path.join(iconset, name))
    return 0


if __name__ == "__main__":
    sys.exit(main())
