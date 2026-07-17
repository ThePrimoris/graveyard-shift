"""Scene backdrops for the game views (P8 round 2).

Run from the project root:  python3 tools/generate_backdrops.py
Deterministic. Each view gets a very dark painted scene (silhouettes, fog,
a light source) so screens read as PLACES instead of cards floating on a
flat clear color. Kept deliberately dim — UI must stay readable on top.

  theme/backdrops/bg_graveyard.png  headstones, fog, a low moon (also the app-wide base)
  theme/backdrops/bg_forest.png     trunk silhouettes, canopy, fireflies
  theme/backdrops/bg_quarry.png     strata walls, rubble line
  theme/backdrops/bg_combat.png     jagged ridge, ember air
  theme/backdrops/bg_alchemy.png    shelf of bottles, still-light
  theme/backdrops/bg_forge.png      anvil glow from below
"""
from PIL import Image, ImageDraw, ImageFilter
import random
import os

W, H = 960, 540
rnd = random.Random("mortimer")


def vertical_gradient(top, bottom):
    img = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(img)
    for y in range(H):
        t = y / H
        d.line([(0, y), (W, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)))
    return img


def vignette(img, strength=110):
    """Darken corners/edges so the scene pools in the middle."""
    m = Image.new("L", (W, H), 0)
    ImageDraw.Draw(m).ellipse((-W * 0.25, -H * 0.35, W * 1.25, H * 1.35), fill=strength)
    m = m.filter(ImageFilter.GaussianBlur(120))
    dark = Image.new("RGB", (W, H), (0, 0, 0))
    return Image.composite(img, dark, m.point(lambda v: 255 - (strength - v) if v < strength else 255))


def glow(img, cx, cy, radius, color, alpha=70):
    g = Image.new("L", (W, H), 0)
    ImageDraw.Draw(g).ellipse((cx - radius, cy - radius, cx + radius, cy + radius), fill=alpha)
    g = g.filter(ImageFilter.GaussianBlur(radius * 0.55))
    layer = Image.new("RGB", (W, H), color)
    return Image.composite(layer, img, g).convert("RGB") if False else Image.blend(img, Image.composite(layer, img, g), 1.0)


def specks(d, box, color, n, rmax=1.6):
    x0, y0, x1, y1 = box
    for _ in range(n):
        x, y = rnd.uniform(x0, x1), rnd.uniform(y0, y1)
        r = rnd.uniform(0.5, rmax)
        d.ellipse((x - r, y - r, x + r, y + r), fill=color)


def fog_bands(img, y_center, color, alpha=26, bands=3):
    fog = Image.new("L", (W, H), 0)
    fd = ImageDraw.Draw(fog)
    for i in range(bands):
        y = y_center + rnd.uniform(-40, 40)
        h = rnd.uniform(18, 44)
        fd.ellipse((rnd.uniform(-200, 0), y - h, W + rnd.uniform(0, 200), y + h), fill=alpha)
    fog = fog.filter(ImageFilter.GaussianBlur(24))
    layer = Image.new("RGB", (W, H), color)
    return Image.composite(layer, img, fog)


def bg_graveyard():
    img = vertical_gradient((16, 13, 28), (7, 6, 13))
    # low moon behind cloud
    img = glow(img, W * 0.78, H * 0.22, 90, (196, 190, 170), 46)
    d = ImageDraw.Draw(img)
    d.ellipse((W * 0.78 - 34, H * 0.22 - 34, W * 0.78 + 34, H * 0.22 + 34), fill=(88, 86, 92))
    specks(d, (0, 0, W, H * 0.4), (70, 70, 90), 26, 1.1)  # dim stars
    # ground + headstone silhouettes
    sil = (10, 8, 18)
    d.rectangle((0, H * 0.86, W, H), fill=sil)
    x = 20
    while x < W:
        w = rnd.uniform(16, 30)
        h = rnd.uniform(24, 56)
        y = H * 0.86
        if rnd.random() < 0.6:
            d.rounded_rectangle((x, y - h, x + w, y + 6), radius=int(w * 0.4), fill=sil)
        else:  # cross
            d.rectangle((x + w * 0.4, y - h, x + w * 0.6, y + 6), fill=sil)
            d.rectangle((x, y - h * 0.7, x + w, y - h * 0.55), fill=sil)
        x += rnd.uniform(50, 130)
    # dead tree, left
    d.line((W * 0.09, H, W * 0.11, H * 0.6), fill=sil, width=10)
    d.line((W * 0.11, H * 0.72, W * 0.05, H * 0.58), fill=sil, width=5)
    d.line((W * 0.107, H * 0.66, W * 0.16, H * 0.52), fill=sil, width=4)
    img = fog_bands(img, H * 0.82, (34, 32, 52))
    return vignette(img)


def bg_forest():
    img = vertical_gradient((11, 17, 13), (5, 8, 7))
    img = glow(img, W * 0.5, H * 0.18, 130, (70, 110, 70), 30)  # canopy light
    d = ImageDraw.Draw(img)
    sil = (6, 10, 8)
    d.rectangle((0, 0, W, H * 0.12), fill=sil)  # canopy mass
    for x in (0.06, 0.16, 0.82, 0.93):
        w = rnd.uniform(26, 44)
        d.line((W * x, H, W * x + rnd.uniform(-14, 14), -10), fill=sil, width=int(w))
    d.rectangle((0, H * 0.9, W, H), fill=sil)
    specks(d, (W * 0.2, H * 0.45, W * 0.8, H * 0.85), (120, 160, 80), 14, 1.4)  # fireflies
    img = fog_bands(img, H * 0.8, (26, 40, 30))
    return vignette(img)


def bg_quarry():
    img = vertical_gradient((19, 16, 15), (8, 7, 8))
    d = ImageDraw.Draw(img)
    # strata walls
    for i, y in enumerate(range(int(H * 0.25), H, 46)):
        shade = 12 + (i % 3) * 4
        d.polygon([(0, y), (W, y - 26), (W, y + 20 - 26), (0, y + 20)], fill=(shade + 6, shade + 2, shade))
    sil = (9, 8, 9)
    d.rectangle((0, H * 0.88, W, H), fill=sil)
    x = 0
    while x < W:  # rubble line
        r = rnd.uniform(8, 26)
        d.ellipse((x, H * 0.88 - r, x + r * 2.2, H * 0.88 + r), fill=sil)
        x += r * 1.8
    img = glow(img, W * 0.24, H * 0.3, 80, (150, 130, 90), 22)  # lantern shaft
    img = fog_bands(img, H * 0.84, (30, 28, 30), alpha=20)
    return vignette(img)


def bg_combat():
    img = vertical_gradient((24, 12, 20), (9, 5, 11))
    d = ImageDraw.Draw(img)
    sil = (12, 6, 12)
    pts = [(0, H * 0.8)]
    x = 0
    while x < W:  # jagged ridge
        x += rnd.uniform(50, 120)
        pts.append((x, H * rnd.uniform(0.62, 0.82)))
    pts += [(W, H), (0, H)]
    d.polygon(pts, fill=sil)
    img = glow(img, W * 0.5, H * 0.95, 190, (150, 60, 40), 30)  # hell-light from below
    d = ImageDraw.Draw(img)
    specks(d, (0, H * 0.3, W, H * 0.75), (140, 70, 40), 22, 1.3)  # ember air
    return vignette(img, 96)


def bg_alchemy():
    img = vertical_gradient((10, 18, 17), (5, 9, 9))
    img = glow(img, W * 0.3, H * 0.62, 110, (60, 140, 110), 30)  # still-light
    d = ImageDraw.Draw(img)
    sil = (6, 11, 11)
    d.rectangle((0, H * 0.885, W, H), fill=sil)      # bench
    d.rectangle((W * 0.62, H * 0.36, W, H * 0.375), fill=sil)  # shelf
    x = W * 0.65
    while x < W - 20:  # bottle silhouettes on the shelf
        bw = rnd.uniform(9, 18)
        bh = rnd.uniform(20, 42)
        d.rounded_rectangle((x, H * 0.36 - bh, x + bw, H * 0.36), radius=4, fill=sil)
        x += bw + rnd.uniform(8, 22)
    specks(d, (W * 0.2, H * 0.5, W * 0.42, H * 0.85), (70, 150, 120), 12, 1.6)  # rising bubbles
    return vignette(img)


def bg_forge():
    img = vertical_gradient((17, 13, 12), (8, 6, 6))
    img = glow(img, W * 0.5, H * 1.02, 220, (170, 90, 40), 40)  # forge mouth below
    d = ImageDraw.Draw(img)
    sil = (10, 7, 6)
    d.rectangle((0, H * 0.88, W, H), fill=sil)
    # anvil silhouette
    ax, ay = W * 0.76, H * 0.88
    d.polygon([(ax - 60, ay - 34), (ax + 66, ay - 34), (ax + 44, ay - 16), (ax + 18, ay - 10),
               (ax + 18, ay), (ax - 30, ay), (ax - 30, ay - 10), (ax - 48, ay - 20)], fill=sil)
    specks(d, (W * 0.3, H * 0.45, W * 0.7, H * 0.85), (170, 90, 40), 18, 1.4)  # sparks
    return vignette(img, 100)


def main():
    os.makedirs("theme/backdrops", exist_ok=True)
    for name, fn in (("bg_graveyard", bg_graveyard), ("bg_forest", bg_forest),
                     ("bg_quarry", bg_quarry), ("bg_combat", bg_combat),
                     ("bg_alchemy", bg_alchemy), ("bg_forge", bg_forge)):
        fn().save("theme/backdrops/%s.png" % name)
        print("theme/backdrops/%s.png" % name)


if __name__ == "__main__":
    main()
