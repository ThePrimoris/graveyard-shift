"""Generates 64x64 icons for items, enemies, minions, and skills (v2).

Run from the project root:  python tools/generate_icons.py
Deterministic. v2 adds a shading/highlight depth pass, textures (speckles,
sparkles, grain), and distinct designs for groups that previously shared a
single silhouette (logs, dusts, rocks, gems, slimes, golems, skulls...).
"""
from PIL import Image, ImageDraw, ImageFilter, ImageChops
import math
import os
import random

SS = 4
S = 64 * SS
W = 3 * SS  # outline width


def darken(c, f=0.55):
    return tuple(int(v * f) for v in c[:3]) + (255,)


def lighten(c, f=0.35):
    return tuple(int(v + (255 - v) * f) for v in c[:3]) + (255,)


def canvas():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def P(*pts):
    return [(x * SS, y * SS) for x, y in pts]


def B(x0, y0, x1, y1):
    return (x0 * SS, y0 * SS, x1 * SS, y1 * SS)


def finish(img):
    """Depth pass: clean cartoon outline, form shadow, and a top-left rim light."""
    # 1) Solid dark outline around the whole silhouette (cartoon read).
    alpha = img.getchannel("A")
    mask = alpha.point(lambda v: 255 if v > 50 else 0)
    grown = mask.filter(ImageFilter.MaxFilter(9))
    outline = Image.new("RGBA", (S, S), (16, 12, 20, 255))
    outline.putalpha(grown)
    img = Image.alpha_composite(outline, img)
    alpha = img.getchannel("A")

    # 2) Form shadow: darken toward the bottom.
    grad = Image.new("L", (S, S), 0)
    gd = ImageDraw.Draw(grad)
    for y in range(S):
        t = y / S
        gd.line([(0, y), (S, y)], fill=int(120 * max(0.0, t - 0.35) / 0.65))
    shadow = Image.new("RGBA", (S, S), (10, 8, 16, 255))
    shadow.putalpha(ImageChops.multiply(grad, alpha))
    img = Image.alpha_composite(img, shadow)

    # 3) Soft top-left rim highlight for volume.
    hl = Image.new("L", (S, S), 0)
    ImageDraw.Draw(hl).ellipse((-S // 5, -S // 4, int(S * 0.58), int(S * 0.5)), fill=85)
    hl = hl.filter(ImageFilter.GaussianBlur(S // 9))
    light = Image.new("RGBA", (S, S), (255, 255, 250, 255))
    light.putalpha(ImageChops.multiply(hl, alpha))
    return Image.alpha_composite(img, light)


def speck(d, seed, box, color, n=10, rmax=1.6):
    rnd = random.Random(seed)
    x0, y0, x1, y1 = box
    for _ in range(n):
        x = rnd.uniform(x0, x1)
        y = rnd.uniform(y0, y1)
        r = rnd.uniform(0.6, rmax)
        d.ellipse(B(x - r, y - r, x + r, y + r), fill=color)


def star(d, x, y, r, color):
    d.polygon(P((x, y - r), (x + r * 0.3, y - r * 0.3), (x + r, y), (x + r * 0.3, y + r * 0.3),
                (x, y + r), (x - r * 0.3, y + r * 0.3), (x - r, y), (x - r * 0.3, y - r * 0.3)),
              fill=color)


def eye(d, x, y, r, iris=(200, 60, 60, 255)):
    d.ellipse(B(x - r, y - r, x + r, y + r), fill=(238, 234, 224, 255), outline=(30, 24, 30, 255), width=SS)
    d.ellipse(B(x - r * 0.45, y - r * 0.45, x + r * 0.45, y + r * 0.45), fill=iris)
    d.ellipse(B(x - r * 0.18, y - r * 0.18, x + r * 0.18, y + r * 0.18), fill=(20, 16, 20, 255))


# ================================================================ LOGS

def _log_body(d, c, rings=True):
    d.rounded_rectangle(B(6, 24, 50, 44), radius=8 * SS, fill=c, outline=darken(c), width=W)
    d.line(P((12, 30), (40, 30)), fill=darken(c, 0.72), width=2 * SS)
    d.line(P((12, 38), (36, 38)), fill=darken(c, 0.72), width=2 * SS)
    d.ellipse(B(42, 24, 58, 44), fill=lighten(c, 0.45), outline=darken(c), width=W)
    if rings:
        d.ellipse(B(46, 29, 54, 39), outline=darken(c, 0.6), width=SS)
        d.ellipse(B(48, 32, 52, 36), outline=darken(c, 0.6), width=SS)


def sh_log_mossy(d, c, a):  # grave_logs
    _log_body(d, c)
    for (x, y, r) in ((12, 23, 6), (22, 21, 7), (32, 23, 5)):
        d.ellipse(B(x - r, y - r + 3, x + r, y + r), fill=(96, 148, 86, 255))
    speck(d, "moss", (8, 18, 36, 26), (130, 180, 110, 255), 6, 1.2)


def sh_log_thorned(d, c, a):  # thorn_logs
    _log_body(d, c)
    for (x, y) in ((14, 24), (26, 22), (38, 24)):
        d.polygon(P((x - 3, y + 2), (x, y - 9), (x + 3, y + 2)), fill=(74, 56, 74, 255), outline=darken(c), width=SS)


def sh_log_pale(d, c, a):  # ash_logs
    _log_body(d, c)
    for x in (14, 24, 34):
        d.line(P((x, 26), (x + 3, 42)), fill=(90, 88, 84, 255), width=SS)


def sh_log_blessed(d, c, a):  # angel_logs
    _log_body(d, c)
    d.ellipse(B(44, 27, 56, 41), outline=(240, 210, 110, 255), width=2 * SS)
    star(d, 16, 20, 4, (250, 226, 130, 255))
    star(d, 30, 18, 3, (250, 226, 130, 255))


def sh_log_dark(d, c, a):  # walnut_logs
    _log_body(d, c, rings=False)
    d.ellipse(B(46, 29, 54, 39), outline=(140, 60, 50, 255), width=SS)
    d.ellipse(B(48, 32, 52, 36), fill=(150, 70, 55, 255))


def sh_branch(d, c, a):
    d.line(P((12, 54), (34, 30)), fill=c, width=5 * SS)
    d.line(P((34, 30), (50, 12)), fill=c, width=4 * SS)
    d.line(P((28, 36), (42, 42)), fill=c, width=3 * SS)
    d.line(P((36, 27), (30, 14)), fill=c, width=3 * SS)
    d.line(P((33, 32), (37, 28)), fill=darken(c, 0.5), width=SS)
    d.line(P((12, 54), (34, 30)), fill=darken(c), width=SS)


# ================================================================ ROCKS & ORES

def _rock_base(d, c, pts=None):
    pts = pts or P((14, 52), (7, 32), (20, 13), (44, 11), (57, 30), (48, 53))
    d.polygon(pts, fill=c, outline=darken(c), width=W)


def sh_rock_layered(d, c, a):  # limestone
    _rock_base(d, c)
    for y in (24, 32, 40):
        d.line(P((12, y), (52, y - 3)), fill=darken(c, 0.75), width=2 * SS)
    speck(d, "lime", (14, 16, 50, 48), lighten(c, 0.4), 6, 1.4)


def sh_rock_speckled(d, c, a):  # granite
    _rock_base(d, c)
    speck(d, "granite1", (12, 16, 52, 48), (60, 58, 60, 255), 12, 1.8)
    speck(d, "granite2", (12, 16, 52, 48), (225, 222, 218, 255), 9, 1.4)


def sh_rock_columns(d, c, a):  # basalt
    for i, x in enumerate((10, 25, 40)):
        h = (14, 8, 18)[i]
        d.polygon(P((x, 54), (x, h), (x + 7, h - 4), (x + 14, h), (x + 14, 54)), fill=c, outline=darken(c), width=2 * SS)
        d.line(P((x + 7, h - 3), (x + 7, 52)), fill=darken(c, 0.7), width=SS)


def sh_rock_crystals(d, c, a):  # peridot
    _rock_base(d, (120, 116, 110, 255))
    for (x, y, w_, h) in ((22, 30, 5, 12), (34, 26, 6, 14), (43, 36, 4, 9)):
        d.polygon(P((x - w_, y + h), (x, y - h), (x + w_, y + h)), fill=c, outline=darken(c), width=SS)
        d.line(P((x, y - h + 3), (x, y + h - 2)), fill=lighten(c, 0.5), width=SS)


def sh_slab(d, c, a):  # slate
    for i, y in enumerate((38, 28, 18)):
        col = c if i % 2 == 0 else lighten(c, 0.18)
        d.polygon(P((10, y + 12), (54, y + 12), (50, y), (14, y)), fill=col, outline=darken(c), width=2 * SS)
    d.line(P((20, 44), (30, 40)), fill=darken(c, 0.6), width=SS)


def _ore_rock(d, seed, vein_color):
    _rock_base(d, (74, 70, 76, 255))
    rnd = random.Random(seed)
    for _ in range(4):
        x = rnd.uniform(16, 40)
        y = rnd.uniform(18, 44)
        d.line(P((x, y), (x + rnd.uniform(4, 9), y + rnd.uniform(-4, 4))), fill=vein_color, width=2 * SS)
    speck(d, seed + "n", (14, 16, 50, 48), vein_color, 7, 2.2)


def sh_ore_sphalerite(d, c, a):
    _ore_rock(d, "sphal", (196, 168, 120, 255))


def sh_ore_tungsten(d, c, a):
    _ore_rock(d, "tung", (168, 180, 196, 255))


def sh_ore_nickel(d, c, a):
    _ore_rock(d, "nick", (214, 218, 212, 255))


# ================================================================ DUSTS & POWDERS

def sh_dust_skull(d, c, a):  # grave_dust
    d.pieslice(B(8, 26, 56, 68), 180, 360, fill=c, outline=darken(c), width=W)
    d.line(P((30, 26), (38, 18)), fill=(226, 218, 196, 255), width=3 * SS)
    d.ellipse(B(36, 14, 42, 20), fill=(226, 218, 196, 255))
    speck(d, "gdust", (12, 32, 52, 46), darken(c, 0.7), 8, 1.4)


def sh_dust_urn(d, c, a):  # ashes
    d.pieslice(B(6, 36, 42, 64), 180, 360, fill=c, outline=darken(c), width=2 * SS)
    d.polygon(P((34, 18), (52, 26), (48, 40), (30, 32)), fill=(120, 90, 70, 255), outline=(70, 52, 40, 255), width=2 * SS)
    d.ellipse(B(28, 27, 38, 37), fill=(40, 34, 30, 255))
    speck(d, "ash", (10, 40, 38, 48), lighten(c, 0.3), 7, 1.3)


def sh_dust_sparkle(d, c, a):  # pyrite_dust
    d.pieslice(B(8, 26, 56, 68), 180, 360, fill=c, outline=darken(c), width=W)
    star(d, 20, 34, 4, lighten(c, 0.6))
    star(d, 34, 40, 3, lighten(c, 0.6))
    star(d, 44, 32, 4, lighten(c, 0.6))
    star(d, 30, 18, 4, lighten(c, 0.5))


def sh_powder_vial(d, c, a):  # cobalt_powder
    d.rounded_rectangle(B(22, 14, 42, 56), radius=6 * SS, fill=(200, 214, 224, 90), outline=(150, 165, 180, 255), width=2 * SS)
    d.rounded_rectangle(B(24, 34, 40, 54), radius=4 * SS, fill=c)
    speck(d, "cob", (25, 35, 39, 52), lighten(c, 0.4), 6, 1.2)
    d.rectangle(B(25, 8, 39, 16), fill=(150, 110, 70, 255), outline=(100, 72, 46, 255), width=2 * SS)


# ================================================================ GEMS

def sh_jade_torus(d, c, a):  # jade_knot: carved ring with a real hole
    d.ellipse(B(12, 12, 52, 52), fill=c, outline=darken(c), width=W)
    d.arc(B(14, 14, 50, 50), 200, 320, fill=lighten(c, 0.45), width=2 * SS)
    d.arc(B(12, 12, 52, 52), 30, 90, fill=darken(c, 0.7), width=2 * SS)
    d.line(P((18, 40), (24, 36)), fill=darken(c, 0.7), width=SS)
    d.line(P((40, 20), (46, 26)), fill=darken(c, 0.7), width=SS)
    d.ellipse(B(25, 25, 39, 39), fill=(0, 0, 0, 0))
    d.ellipse(B(25, 25, 39, 39), outline=darken(c), width=2 * SS)


def sh_shard(d, c, a):  # obsidian_shard
    d.polygon(P((26, 6), (40, 16), (36, 34), (44, 40), (30, 58), (24, 36), (18, 22)),
              fill=c, outline=darken(c, 0.4), width=2 * SS)
    d.line(P((27, 10), (26, 40)), fill=(120, 96, 160, 255), width=SS)
    d.line(P((33, 14), (31, 46)), fill=lighten(c, 0.35), width=SS)
    star(d, 38, 20, 4, (210, 190, 240, 220))


def sh_geode(d, c, a):
    d.pieslice(B(8, 14, 56, 60), 180, 360, fill=a, outline=darken(a), width=W)
    d.pieslice(B(14, 22, 50, 54), 180, 360, fill=darken(c, 0.35), width=0)
    for x in (22, 30, 38, 44):
        d.polygon(P((x - 4, 37), (x - 1, 24), (x + 3, 37)), fill=c)
        d.line(P((x - 1, 26), (x - 1, 35)), fill=lighten(c, 0.5), width=SS)
    d.rectangle(B(8, 36, 56, 39), fill=darken(a), width=0)
    star(d, 30, 30, 3, (255, 255, 255, 230))


def sh_cluster(d, c, a):
    d.polygon(P((8, 56), (56, 56), (50, 46), (14, 46)), fill=a, outline=darken(a), width=W)
    for (x, h, w_) in ((20, 20, 7), (32, 9, 8), (44, 24, 6)):
        d.polygon(P((x - w_, 48), (x, h), (x + w_, 48)), fill=c, outline=darken(c), width=2 * SS)
        d.line(P((x, h + 4), (x - 2, 44)), fill=lighten(c, 0.5), width=SS)
    star(d, 32, 16, 4, (255, 255, 255, 220))


def sh_flakes(d, c, a):
    for i, (x, y) in enumerate(((15, 17), (33, 29), (21, 43))):
        d.polygon(P((x, y), (x + 15, y - 7), (x + 20, y + 2), (x + 5, y + 9)),
                  fill=c if i != 1 else lighten(c, 0.2), outline=darken(c), width=2 * SS)
    star(d, 44, 20, 4, lighten(c, 0.55))


# ================================================================ GRAVE MATERIALS

def sh_flesh(d, c, a):
    d.ellipse(B(10, 18, 54, 52), fill=c, outline=darken(c), width=W)
    d.ellipse(B(20, 26, 38, 40), fill=lighten(c, 0.3))
    for (x0, y0) in ((22, 44), (34, 46)):
        d.line(P((x0, y0), (x0 + 6, y0 - 3)), fill=darken(c, 0.5), width=SS)
        for t in range(3):
            d.line(P((x0 + t * 2, y0 + 2 - t), (x0 + t * 2 + 1, y0 - 4 - t)), fill=darken(c, 0.5), width=SS)


def sh_blood(d, c, a):
    d.polygon(P((32, 5), (45, 30), (19, 30)), fill=c, outline=darken(c), width=W)
    d.ellipse(B(14, 22, 50, 56), fill=c, outline=darken(c), width=W)
    d.polygon(P((32, 9), (42, 29), (22, 29)), fill=c)
    d.ellipse(B(21, 32, 31, 44), fill=lighten(c, 0.45))
    d.ellipse(B(50, 46, 58, 54), fill=c, outline=darken(c), width=SS)


def sh_marrow(d, c, a):
    d.line(P((18, 46), (46, 18)), fill=c, width=9 * SS)
    for (x, y) in ((14, 42), (23, 50), (41, 13), (50, 22)):
        d.ellipse(B(x - 7, y - 7, x + 7, y + 7), fill=c, outline=darken(c), width=2 * SS)
    d.line(P((24, 40), (40, 24)), fill=(200, 90, 90, 255), width=3 * SS)
    d.line(P((30, 34), (34, 30)), fill=(240, 140, 130, 255), width=2 * SS)


def sh_bones(d, c, a):
    for (p0, p1) in (((16, 44), (44, 18)), ((18, 20), (46, 46))):
        d.line(P(p0, p1), fill=c, width=6 * SS)
        for (x, y) in (p0, p1):
            d.ellipse(B(x - 6, y - 6, x + 6, y + 6), fill=c, outline=darken(c), width=SS)
    d.line(P((20, 41), (40, 22)), fill=lighten(c, 0.3), width=SS)


def sh_urn(d, c, a):
    d.polygon(P((22, 12), (42, 12), (46, 22), (44, 44), (38, 54), (26, 54), (20, 44), (18, 22)),
              fill=c, outline=darken(c), width=W)
    d.rectangle(B(20, 8, 44, 14), fill=a, outline=darken(a), width=2 * SS)
    d.line(P((24, 24), (24, 44)), fill=lighten(c, 0.3), width=3 * SS)
    d.ellipse(B(29, 30, 37, 38), fill=darken(c, 0.55))
    for x in (28, 32, 36):
        d.ellipse(B(x - 1, 26, x + 2, 29), fill=darken(c, 0.55))


def sh_rotten_meat(d, c, a):
    d.ellipse(B(10, 22, 50, 52), fill=c, outline=darken(c), width=W)
    d.ellipse(B(18, 28, 34, 42), fill=lighten(c, 0.3))
    d.line(P((44, 26), (56, 16)), fill=(226, 218, 196, 255), width=4 * SS)
    d.ellipse(B(52, 12, 60, 20), fill=(226, 218, 196, 255))
    speck(d, "flies", (14, 8, 50, 18), (40, 40, 40, 255), 4, 1.4)
    speck(d, "rot", (16, 30, 44, 48), (98, 110, 60, 255), 5, 2.0)


def sh_claws(d, c, a):
    for x in (16, 30, 44):
        d.polygon(P((x - 6, 12), (x + 5, 14), (x + 3, 34), (x - 9, 54), (x - 3, 32)),
                  fill=c, outline=darken(c), width=2 * SS)
        d.line(P((x - 1, 16), (x - 3, 34)), fill=lighten(c, 0.35), width=SS)


def sh_bile(d, c, a):
    d.rectangle(B(27, 8, 37, 20), fill=(150, 165, 180, 255), outline=(100, 115, 130, 255), width=2 * SS)
    d.ellipse(B(12, 18, 52, 58), fill=(190, 205, 216, 80), outline=(130, 145, 158, 255), width=2 * SS)
    d.pieslice(B(15, 28, 49, 55), 0, 180, fill=c)
    for (x, y, r) in ((24, 40, 2), (34, 46, 3), (40, 38, 2)):
        d.ellipse(B(x - r, y - r, x + r, y + r), fill=lighten(c, 0.4))


def sh_chains(d, c, a):
    for (x, y) in ((16, 16), (28, 28), (40, 40)):
        d.ellipse(B(x - 9, y - 6, x + 9, y + 6), outline=c, width=4 * SS)
    for (x, y) in ((22, 22), (34, 34)):
        d.ellipse(B(x - 9, y - 6, x + 9, y + 6), outline=lighten(c, 0.25), width=4 * SS)
    d.line(P((46, 46), (52, 54)), fill=c, width=4 * SS)
    d.polygon(P((50, 50), (58, 52), (52, 58)), fill=c)


def sh_skulls(d, c, a):
    d.ellipse(B(28, 14, 56, 40), fill=darken(c, 0.85), outline=darken(c, 0.5), width=2 * SS)
    d.ellipse(B(35, 22, 42, 30), fill=darken(c, 0.35))
    d.ellipse(B(45, 22, 52, 30), fill=darken(c, 0.35))
    d.ellipse(B(8, 24, 38, 52), fill=c, outline=darken(c), width=2 * SS)
    d.rectangle(B(16, 46, 30, 58), fill=c, outline=darken(c), width=2 * SS)
    d.ellipse(B(13, 32, 21, 41), fill=darken(c, 0.3))
    d.ellipse(B(25, 32, 33, 41), fill=darken(c, 0.3))
    d.polygon(P((22, 42), (24, 46), (20, 46)), fill=darken(c, 0.4))
    for x in (19, 23, 27):
        d.line(P((x, 50), (x, 56)), fill=darken(c, 0.5), width=SS)


def sh_ecto(d, c, a):
    d.pieslice(B(14, 8, 50, 44), 180, 360, fill=c, outline=darken(c), width=W)
    d.polygon(P((14, 26), (50, 26), (46, 40), (38, 34), (32, 46), (26, 34), (18, 42)),
              fill=c, outline=darken(c), width=SS)
    d.ellipse(B(23, 20, 29, 28), fill=darken(c, 0.4))
    d.ellipse(B(35, 20, 41, 28), fill=darken(c, 0.4))
    for (x, y, r) in ((50, 48, 3), (55, 54, 2)):
        d.ellipse(B(x - r, y - r, x + r, y + r), fill=c)


def sh_candle(d, c, a):
    d.rounded_rectangle(B(22, 26, 42, 56), radius=4 * SS, fill=c, outline=darken(c), width=W)
    d.polygon(P((22, 30), (26, 40), (30, 30)), fill=lighten(c, 0.4))
    d.polygon(P((42, 32), (38, 44), (42, 44)), fill=lighten(c, 0.4))
    d.line(P((32, 26), (32, 19)), fill=darken(c), width=2 * SS)
    d.ellipse(B(24, 2, 40, 20), fill=(255, 200, 90, 60))
    d.polygon(P((32, 6), (38, 16), (32, 21), (26, 16)), fill=a, outline=(180, 100, 40, 255), width=SS)
    d.polygon(P((32, 10), (35, 16), (32, 19), (29, 16)), fill=(255, 240, 170, 255))


def sh_beads(d, c, a):
    for i in range(10):
        ang = math.pi * 2 * i / 10 - math.pi / 2
        x = 32 + 17 * math.cos(ang)
        y = 26 + 15 * math.sin(ang)
        d.ellipse(B(x - 4, y - 4, x + 4, y + 4), fill=c, outline=darken(c), width=SS)
        d.ellipse(B(x - 3, y - 3, x, y), fill=lighten(c, 0.5))
    d.rectangle(B(29, 42, 35, 60), fill=a, outline=darken(a), width=SS)
    d.rectangle(B(23, 47, 41, 53), fill=a, outline=darken(a), width=SS)


# ================================================================ WOOD EXTRAS

def sh_amber(d, c, a):
    d.polygon(P((32, 6), (45, 30), (19, 30)), fill=c, outline=darken(c), width=W)
    d.ellipse(B(15, 22, 49, 56), fill=c, outline=darken(c), width=W)
    d.polygon(P((32, 10), (42, 29), (22, 29)), fill=c)
    d.ellipse(B(22, 32, 32, 44), fill=lighten(c, 0.5))
    d.ellipse(B(33, 38, 39, 44), fill=(70, 50, 30, 255))
    d.line(P((33, 39), (30, 36)), fill=(70, 50, 30, 255), width=SS)
    d.line(P((39, 39), (42, 36)), fill=(70, 50, 30, 255), width=SS)


def sh_thorns(d, c, a):
    d.line(P((8, 50), (56, 28)), fill=a, width=4 * SS)
    for (x, y) in ((18, 45), (32, 39), (46, 32)):
        d.polygon(P((x - 4, y + 2), (x + 1, y - 14), (x + 6, y)), fill=c, outline=darken(c), width=SS)
    d.ellipse(B(50, 38, 58, 46), fill=(140, 40, 60, 255), outline=(90, 26, 40, 255), width=SS)


def sh_flower(d, c, a):
    d.line(P((32, 40), (30, 58)), fill=(74, 96, 60, 255), width=3 * SS)
    d.polygon(P((30, 50), (24, 46), (30, 46)), fill=(74, 96, 60, 255))
    for i in range(5):
        ang = math.pi * 2 * i / 5 - math.pi / 2
        x = 32 + 13 * math.cos(ang)
        y = 28 + 13 * math.sin(ang)
        d.ellipse(B(x - 9, y - 9, x + 9, y + 9), fill=c, outline=darken(c), width=SS)
        d.ellipse(B(x - 5, y - 5, x, y), fill=lighten(c, 0.3))
    d.ellipse(B(25, 21, 39, 35), fill=a, outline=darken(a), width=SS)
    speck(d, "pollen", (27, 23, 37, 33), lighten(a, 0.5), 4, 1.0)


def sh_lichen(d, c, a):
    d.polygon(P((10, 52), (16, 34), (40, 30), (54, 44), (46, 54)), fill=(110, 106, 100, 255),
              outline=(70, 66, 62, 255), width=2 * SS)
    for (x, y, r) in ((22, 34, 8), (34, 30, 9), (44, 38, 7)):
        d.ellipse(B(x - r, y - r, x + r, y + r), fill=c, outline=darken(c), width=SS)
    speck(d, "lich", (16, 24, 50, 42), lighten(c, 0.4), 8, 1.3)


def sh_husk(d, c, a):
    d.ellipse(B(16, 8, 48, 56), fill=c, outline=darken(c), width=W)
    for y in (18, 30, 42):
        d.arc(B(16, y - 10, 48, y + 10), 20, 160, fill=darken(c, 0.7), width=2 * SS)
    d.line(P((46, 14), (58, 6)), fill=lighten(c, 0.2), width=SS)
    d.ellipse(B(20, 14, 30, 26), fill=lighten(c, 0.25))


def sh_moss(d, c, a):
    d.rectangle(B(8, 46, 56, 56), fill=(110, 92, 70, 255), outline=(70, 58, 44, 255), width=2 * SS)
    for (x, y, r) in ((18, 42, 11), (32, 38, 13), (46, 43, 10)):
        d.ellipse(B(x - r, y - r, x + r, y + r), fill=c, outline=darken(c), width=SS)
    speck(d, "mossy", (10, 28, 54, 46), lighten(c, 0.35), 10, 1.4)


def sh_acorn(d, c, a):
    d.pieslice(B(17, 10, 47, 36), 180, 360, fill=a, outline=darken(a), width=W)
    for x in (22, 28, 34, 40):
        d.line(P((x, 13), (x - 2, 22)), fill=darken(a, 0.7), width=SS)
    d.ellipse(B(20, 20, 44, 54), fill=c, outline=darken(c), width=W)
    d.ellipse(B(25, 27, 33, 39), fill=lighten(c, 0.3))
    d.line(P((32, 10), (34, 3)), fill=darken(a), width=3 * SS)


def sh_vine(d, c, a):
    d.arc(B(8, 4, 44, 36), 90, 300, fill=c, width=4 * SS)
    d.arc(B(22, 26, 56, 58), 270, 120, fill=c, width=4 * SS)
    for (x, y) in ((14, 10), (48, 52)):
        d.ellipse(B(x - 6, y - 3, x + 6, y + 3), fill=(74, 110, 60, 255), outline=darken(c), width=SS)
    for (x, y) in ((34, 28), (40, 34), (30, 34)):
        d.ellipse(B(x - 3, y - 3, x + 3, y + 3), fill=(120, 70, 160, 255), outline=(70, 40, 100, 255), width=SS)


def sh_feather(d, c, a):
    d.ellipse(B(16, 6, 46, 52), fill=c, outline=darken(c), width=W)
    d.line(P((30, 8), (35, 60)), fill=darken(c, 0.5), width=2 * SS)
    for y in (16, 24, 32, 40):
        d.line(P((31, y), (20, y + 7)), fill=darken(c, 0.7), width=SS)
        d.line(P((32, y), (43, y + 7)), fill=darken(c, 0.7), width=SS)
    d.polygon(P((18, 10), (30, 8), (24, 18)), fill=lighten(c, 0.4))


# ================================================================ FORGED

def sh_ring(d, c, a):
    d.ellipse(B(14, 22, 50, 58), outline=c, width=7 * SS)
    d.arc(B(14, 22, 50, 58), 160, 300, fill=lighten(c, 0.4), width=3 * SS)
    d.polygon(P((32, 4), (43, 14), (32, 24), (21, 14)), fill=a, outline=darken(a), width=W)
    d.polygon(P((32, 7), (39, 14), (32, 14)), fill=lighten(a, 0.5))
    star(d, 25, 9, 3, (255, 255, 255, 230))


def sh_amulet(d, c, a):
    d.arc(B(10, 2, 54, 46), 200, 340, fill=(150, 140, 120, 255), width=3 * SS)
    d.ellipse(B(19, 25, 45, 51), fill=c, outline=darken(c), width=W)
    d.ellipse(B(23, 29, 41, 47), outline=darken(c, 0.7), width=SS)
    d.ellipse(B(27, 33, 37, 43), fill=a, outline=darken(a), width=SS)
    d.ellipse(B(29, 35, 33, 39), fill=lighten(a, 0.5))
    star(d, 41, 30, 3, (255, 255, 255, 220))


def sh_idol(d, c, a):
    d.ellipse(B(23, 5, 41, 23), fill=c, outline=darken(c), width=W)
    d.polygon(P((19, 25), (45, 25), (49, 52), (15, 52)), fill=c, outline=darken(c), width=W)
    d.rectangle(B(11, 52, 53, 58), fill=darken(c, 0.8), outline=darken(c, 0.5), width=2 * SS)
    d.ellipse(B(27, 10, 31, 14), fill=a)
    d.ellipse(B(33, 10, 37, 14), fill=a)
    d.line(P((24, 32), (32, 40)), fill=darken(c, 0.6), width=2 * SS)
    d.line(P((32, 40), (40, 32)), fill=darken(c, 0.6), width=2 * SS)
    d.ellipse(B(29, 33, 35, 39), fill=a)


def sh_signet(d, c, a):
    d.ellipse(B(16, 20, 48, 56), outline=c, width=6 * SS)
    d.arc(B(16, 20, 48, 56), 150, 280, fill=lighten(c, 0.4), width=2 * SS)
    d.rounded_rectangle(B(19, 6, 45, 26), radius=3 * SS, fill=a, outline=darken(a), width=W)
    d.ellipse(B(26, 10, 38, 22), outline=darken(a, 0.6), width=SS)
    d.line(P((32, 12), (32, 20)), fill=darken(a, 0.6), width=SS)
    d.line(P((28, 16), (36, 16)), fill=darken(a, 0.6), width=SS)


def sh_reliquary(d, c, a):
    d.pieslice(B(14, 4, 50, 40), 180, 360, fill=c, outline=darken(c), width=W)
    d.rectangle(B(14, 22, 50, 54), fill=c, outline=darken(c), width=W)
    d.line(P((14, 22), (50, 22)), fill=darken(c, 0.6), width=2 * SS)
    d.rectangle(B(28, 28, 36, 46), fill=darken(c, 0.4))
    d.ellipse(B(28, 30, 36, 38), fill=a)
    d.ellipse(B(24, 26, 40, 42), outline=a, width=SS)
    star(d, 32, 34, 7, (255, 255, 255, 90))


# ================================================================ TOOLS

def _handle(d, p0, p1, a):
    d.line(P(p0, p1), fill=a, width=5 * SS)
    mx = (p0[0] + p1[0]) / 2
    my = (p0[1] + p1[1]) / 2
    d.line(P((mx - 2, my), (mx + 2, my)), fill=darken(a, 0.6), width=SS)


def sh_shovel(d, c, a):
    _handle(d, (42, 6), (26, 34), a)
    d.line(P((38, 2), (48, 8)), fill=a, width=4 * SS)
    d.polygon(P((12, 38), (30, 30), (38, 44), (24, 58), (12, 50)), fill=c, outline=darken(c), width=W)
    d.line(P((25, 36), (25, 50)), fill=darken(c, 0.65), width=SS)
    d.line(P((17, 40), (28, 34)), fill=lighten(c, 0.4), width=2 * SS)


def sh_hatchet(d, c, a):
    _handle(d, (46, 10), (18, 56), a)
    d.polygon(P((34, 6), (56, 16), (52, 34), (32, 26)), fill=c, outline=darken(c), width=W)
    d.line(P((53, 19), (44, 29)), fill=lighten(c, 0.45), width=2 * SS)
    d.ellipse(B(40, 14, 44, 18), fill=darken(c, 0.6))


def sh_pickaxe(d, c, a):
    _handle(d, (32, 14), (32, 58), a)
    d.polygon(P((8, 24), (32, 8), (56, 24), (52, 30), (32, 16), (12, 30)),
              fill=c, outline=darken(c), width=W)
    d.line(P((16, 25), (32, 13)), fill=lighten(c, 0.4), width=SS)
    d.line(P((32, 13), (48, 25)), fill=lighten(c, 0.4), width=SS)
    d.ellipse(B(30, 14, 34, 18), fill=darken(c, 0.6))


# ================================================================ COMBAT LOOT

def sh_tallow(d, c, a):
    d.ellipse(B(12, 28, 52, 56), fill=c, outline=darken(c), width=W)
    d.ellipse(B(18, 20, 46, 44), fill=c, outline=darken(c), width=SS)
    d.polygon(P((20, 44), (24, 56), (28, 44)), fill=lighten(c, 0.3))
    d.line(P((32, 20), (32, 12)), fill=(110, 82, 58, 255), width=2 * SS)
    d.ellipse(B(24, 26, 34, 34), fill=lighten(c, 0.35))


def sh_dice(d, c, a):
    d.rounded_rectangle(B(6, 18, 26, 38), radius=3 * SS, fill=c, outline=darken(c), width=2 * SS)
    d.ellipse(B(14, 26, 18, 30), fill=(40, 34, 32, 255))
    d.rounded_rectangle(B(28, 24, 48, 44), radius=3 * SS, fill=c, outline=darken(c), width=2 * SS)
    for (px, py) in ((33, 29), (43, 39), (38, 34)):
        d.ellipse(B(px - 2, py - 2, px + 2, py + 2), fill=(40, 34, 32, 255))


def sh_restraints(d, c, a):
    d.arc(B(10, 10, 54, 54), 160, 20, fill=c, width=6 * SS)
    d.rectangle(B(26, 8, 40, 20), fill=(150, 155, 165, 255), outline=(90, 95, 105, 255), width=2 * SS)
    d.ellipse(B(30, 11, 36, 17), fill=(60, 64, 72, 255))
    d.polygon(P((12, 40), (20, 44), (10, 52)), fill=c)
    for x in (20, 30, 40):
        d.ellipse(B(x - 1, 47, x + 2, 50), fill=darken(c, 0.5))


def sh_canvas(d, c, a):
    d.polygon(P((10, 14), (52, 10), (56, 48), (14, 54)), fill=c, outline=darken(c), width=W)
    d.line(P((14, 22), (50, 18)), fill=darken(c, 0.8), width=SS)
    d.line(P((16, 42), (52, 38)), fill=darken(c, 0.8), width=SS)
    d.ellipse(B(24, 22, 30, 30), fill=darken(c, 0.75))
    d.ellipse(B(36, 21, 42, 29), fill=darken(c, 0.75))
    d.arc(B(26, 30, 40, 42), 0, 180, fill=darken(c, 0.75), width=2 * SS)


def sh_pelt(d, c, a):
    d.polygon(P((16, 12), (48, 12), (54, 26), (48, 44), (52, 56), (40, 48), (24, 48), (12, 56), (16, 44), (10, 26)),
              fill=c, outline=darken(c), width=2 * SS)
    speck(d, "fur", (16, 16, 48, 44), darken(c, 0.75), 12, 1.2)
    d.line(P((48, 46), (58, 40)), fill=c, width=3 * SS)


def sh_gland(d, c, a):
    d.ellipse(B(14, 16, 50, 50), fill=c, outline=darken(c), width=W)
    d.ellipse(B(22, 22, 36, 36), fill=lighten(c, 0.35))
    d.line(P((32, 50), (30, 58)), fill=lighten(c, 0.2), width=SS)
    d.line(P((30, 58), (38, 62)), fill=lighten(c, 0.2), width=SS)
    d.ellipse(B(38, 36, 44, 42), fill=darken(c, 0.75))


def sh_fang(d, c, a):
    d.polygon(P((24, 8), (42, 12), (38, 28), (28, 50), (24, 30)), fill=c, outline=darken(c), width=W)
    d.polygon(P((28, 50), (26, 58), (30, 52)), fill=c)
    d.rectangle(B(22, 6, 44, 14), fill=(180, 160, 140, 255), outline=(120, 104, 88, 255), width=2 * SS)
    d.line(P((30, 16), (28, 40)), fill=lighten(c, 0.4), width=2 * SS)


def sh_beak(d, c, a):
    d.polygon(P((12, 24), (52, 18), (58, 26), (34, 40), (14, 34)), fill=c, outline=darken(c, 0.4), width=W)
    d.line(P((14, 28), (50, 23)), fill=darken(c, 0.5), width=SS)
    d.ellipse(B(18, 20, 24, 26), fill=(240, 200, 90, 255))
    d.polygon(P((30, 40), (36, 52), (40, 38)), fill=darken(c, 0.85))


def sh_gel(d, c, a):
    d.rounded_rectangle(B(14, 20, 50, 54), radius=8 * SS, fill=c, outline=darken(c), width=W)
    d.ellipse(B(20, 26, 30, 34), fill=lighten(c, 0.5))
    for (x, y, r) in ((36, 40, 3), (28, 44, 2), (42, 30, 2)):
        d.ellipse(B(x - r, y - r, x + r, y + r), fill=lighten(c, 0.3))
    d.polygon(P((18, 54), (22, 60), (26, 54)), fill=c)


def sh_ember_core(d, c, a):
    _rock_base(d, (60, 46, 44, 255), P((16, 52), (10, 32), (24, 14), (44, 13), (55, 32), (46, 52)))
    d.line(P((22, 26), (34, 38)), fill=c, width=2 * SS)
    d.line(P((34, 38), (28, 48)), fill=c, width=2 * SS)
    d.line(P((38, 20), (40, 36)), fill=c, width=2 * SS)
    d.ellipse(B(28, 28, 38, 38), fill=c)
    d.ellipse(B(30, 30, 36, 36), fill=lighten(c, 0.5))


def sh_wing(d, c, a):
    d.polygon(P((8, 16), (20, 40), (30, 32), (40, 46), (50, 34), (58, 44), (54, 18), (30, 10)),
              fill=c, outline=darken(c), width=2 * SS)
    for (x0, y0, x1, y1) in ((20, 14, 20, 38), (34, 12, 32, 32), (46, 16, 44, 34)):
        d.line(P((x0, y0), (x1, y1)), fill=darken(c, 0.6), width=2 * SS)


def sh_eyeball(d, c, a):
    d.ellipse(B(12, 12, 52, 52), fill=(238, 232, 222, 255), outline=(150, 120, 110, 255), width=2 * SS)
    for (x0, y0, x1, y1) in ((16, 24, 26, 30), (18, 40, 28, 38), (44, 22, 50, 28)):
        d.line(P((x0, y0), (x1, y1)), fill=(190, 90, 80, 255), width=SS)
    d.ellipse(B(22, 22, 42, 42), fill=c, outline=darken(c), width=SS)
    d.ellipse(B(28, 28, 36, 36), fill=(20, 16, 20, 255))
    d.ellipse(B(26, 24, 32, 30), fill=(255, 255, 255, 200))


def sh_sinew(d, c, a):
    for i in range(3):
        y = 20 + i * 4
        d.arc(B(8, y - 8, 56, y + 20), 200, 340, fill=c, width=4 * SS)
    d.arc(B(8, 30, 56, 52), 20, 160, fill=darken(c, 0.8), width=4 * SS)
    d.ellipse(B(6, 22, 16, 34), fill=c, outline=darken(c), width=SS)
    d.ellipse(B(48, 22, 58, 34), fill=c, outline=darken(c), width=SS)


def sh_heart(d, c, a):
    d.ellipse(B(14, 14, 36, 36), fill=c, outline=darken(c), width=2 * SS)
    d.ellipse(B(28, 14, 50, 36), fill=c, outline=darken(c), width=2 * SS)
    d.polygon(P((15, 30), (32, 56), (49, 30)), fill=c)
    d.line(P((15, 30), (32, 56)), fill=darken(c), width=2 * SS)
    d.line(P((49, 30), (32, 56)), fill=darken(c), width=2 * SS)
    for (x0, y0) in ((24, 22), (34, 40)):
        d.line(P((x0, y0), (x0 + 8, y0 - 2)), fill=darken(c, 0.4), width=SS)
        for t in range(3):
            d.line(P((x0 + t * 3, y0 + 2), (x0 + t * 3 + 1, y0 - 4)), fill=darken(c, 0.4), width=SS)
    d.ellipse(B(22, 20, 30, 28), fill=lighten(c, 0.3))
    d.polygon(P((30, 56), (32, 62), (34, 56)), fill=c)


def sh_vestments(d, c, a):
    d.polygon(P((14, 16), (50, 16), (54, 50), (10, 50)), fill=c, outline=darken(c), width=W)
    d.line(P((14, 26), (50, 26)), fill=darken(c, 0.7), width=2 * SS)
    d.line(P((14, 38), (50, 38)), fill=darken(c, 0.7), width=2 * SS)
    d.line(P((32, 28), (32, 44)), fill=(216, 178, 88, 255), width=3 * SS)
    d.line(P((26, 38), (38, 38)), fill=(216, 178, 88, 255), width=3 * SS)


def sh_censer(d, c, a):
    d.line(P((32, 2), (32, 16)), fill=(150, 140, 120, 255), width=2 * SS)
    d.ellipse(B(18, 16, 46, 44), fill=c, outline=darken(c), width=W)
    d.polygon(P((22, 40), (42, 40), (36, 52), (28, 52)), fill=c, outline=darken(c), width=2 * SS)
    for x in (24, 31, 38):
        d.ellipse(B(x - 1, 25, x + 2, 29), fill=darken(c, 0.4))
    for (x, y, r) in ((46, 14, 4), (52, 8, 3), (44, 4, 2)):
        d.ellipse(B(x - r, y - r, x + r, y + r), fill=(140, 150, 160, 140))


def sh_bark(d, c, a):
    d.polygon(P((14, 8), (50, 12), (46, 56), (10, 52)), fill=c, outline=darken(c), width=W)
    for x in (20, 28, 36):
        d.line(P((x, 14), (x - 2, 50)), fill=darken(c, 0.65), width=2 * SS)
    d.ellipse(B(36, 20, 44, 28), fill=(96, 148, 86, 255))
    speck(d, "bark", (14, 14, 44, 50), darken(c, 0.75), 6, 1.4)


def sh_crown(d, c, a):
    d.polygon(P((10, 44), (10, 24), (20, 34), (28, 16), (36, 34), (46, 18), (54, 26), (54, 44)),
              fill=c, outline=darken(c), width=W)
    d.rectangle(B(10, 44, 54, 52), fill=darken(c, 0.85), outline=darken(c, 0.55), width=2 * SS)
    for (x, y) in ((14, 26), (46, 22)):
        d.ellipse(B(x - 3, y - 2, x + 3, y + 3), fill=(96, 148, 86, 255))
    d.ellipse(B(29, 30, 35, 36), fill=(96, 176, 120, 255), outline=darken(c), width=SS)


def sh_core_shards(d, c, a):
    for (x, y, s_) in ((18, 22, 1.0), (38, 30, 1.2), (24, 44, 0.8)):
        d.polygon(P((x, y - 10 * s_), (x + 7 * s_, y), (x, y + 10 * s_), (x - 7 * s_, y)),
                  fill=c, outline=darken(c), width=2 * SS)
        d.ellipse(B(x - 2, y - 2, x + 2, y + 2), fill=(240, 200, 80, 255))
    star(d, 46, 16, 4, (240, 200, 80, 220))


def sh_golem_heart(d, c, a):
    d.polygon(P((32, 8), (52, 22), (46, 50), (18, 50), (12, 22)), fill=(120, 114, 108, 255),
              outline=(76, 70, 66, 255), width=W)
    d.ellipse(B(22, 20, 42, 40), fill=c, outline=darken(c), width=2 * SS)
    d.ellipse(B(27, 25, 37, 35), fill=lighten(c, 0.5))
    for ang in range(0, 360, 60):
        x = 32 + 14 * math.cos(math.radians(ang))
        y = 30 + 14 * math.sin(math.radians(ang))
        d.line(P((32, 30), (x, y)), fill=lighten(c, 0.25), width=SS)


def sh_void_prism(d, c, a):
    d.polygon(P((32, 4), (48, 20), (40, 56), (24, 56), (16, 20)), fill=c, outline=(140, 120, 190, 255), width=2 * SS)
    d.line(P((32, 4), (32, 56)), fill=(110, 90, 160, 255), width=SS)
    d.line(P((16, 20), (48, 20)), fill=(110, 90, 160, 255), width=SS)
    speck(d, "void", (22, 14, 42, 50), (220, 210, 250, 255), 8, 1.0)
    star(d, 32, 30, 5, (255, 255, 255, 200))


# ================================================================ CREATURES

def sh_zombie_head(d, c, a):
    d.ellipse(B(12, 8, 52, 50), fill=c, outline=darken(c), width=W)
    d.rectangle(B(20, 42, 44, 56), fill=darken(c, 0.9), outline=darken(c, 0.5), width=2 * SS)
    d.ellipse(B(19, 20, 29, 32), fill=(240, 236, 210, 255), outline=darken(c, 0.5), width=SS)
    d.ellipse(B(22, 24, 27, 29), fill=(40, 40, 36, 255))
    d.ellipse(B(36, 22, 44, 30), fill=darken(c, 0.4))
    d.line(P((20, 40), (40, 42)), fill=darken(c, 0.4), width=2 * SS)
    for x in (24, 30, 36):
        d.line(P((x, 39), (x + 1, 45)), fill=darken(c, 0.4), width=SS)
    d.line(P((34, 10), (46, 16)), fill=darken(c, 0.45), width=SS)
    for t in range(3):
        d.line(P((36 + t * 4, 9 + t * 2), (37 + t * 4, 14 + t * 2)), fill=darken(c, 0.45), width=SS)


def sh_skull(d, c, a):
    d.ellipse(B(14, 6, 50, 42), fill=c, outline=darken(c), width=W)
    d.rectangle(B(22, 38, 42, 52), fill=c, outline=darken(c), width=2 * SS)
    d.ellipse(B(20, 18, 30, 30), fill=darken(c, 0.3))
    d.ellipse(B(34, 18, 44, 30), fill=darken(c, 0.3))
    d.ellipse(B(23, 21, 27, 25), fill=a)
    d.ellipse(B(37, 21, 41, 25), fill=a)
    d.polygon(P((31, 30), (33, 34), (29, 34)), fill=darken(c, 0.4))
    for x in (26, 31, 36):
        d.line(P((x, 42), (x, 50)), fill=darken(c, 0.5), width=2 * SS)
    d.line(P((18, 12), (26, 8)), fill=lighten(c, 0.3), width=2 * SS)


def sh_skeleton_body(d, c, a):
    d.ellipse(B(20, 4, 44, 28), fill=c, outline=darken(c), width=2 * SS)
    d.ellipse(B(25, 12, 30, 18), fill=darken(c, 0.3))
    d.ellipse(B(34, 12, 39, 18), fill=darken(c, 0.3))
    d.rectangle(B(27, 26, 37, 32), fill=c)
    d.line(P((32, 30), (32, 54)), fill=c, width=3 * SS)
    for i, y in enumerate((36, 42, 48)):
        w_ = 12 - i * 2
        d.arc(B(32 - w_, y - 4, 32 + w_, y + 4), 0, 180, fill=c, width=2 * SS)
    d.line(P((20, 34), (12, 46)), fill=c, width=2 * SS)
    d.line(P((44, 34), (52, 46)), fill=c, width=2 * SS)


def sh_horror(d, c, a):
    d.ellipse(B(6, 18, 58, 58), fill=c, outline=darken(c), width=W)
    d.ellipse(B(14, 10, 34, 30), fill=c, outline=darken(c), width=SS)
    d.ellipse(B(34, 12, 52, 28), fill=darken(c, 0.85), outline=darken(c, 0.6), width=SS)
    d.line(P((10, 44), (2, 52)), fill=c, width=4 * SS)
    d.line(P((54, 42), (62, 50)), fill=c, width=4 * SS)
    eye(d, 22, 22, 4)
    eye(d, 42, 20, 3)
    eye(d, 32, 38, 5)
    eye(d, 18, 42, 3)
    d.arc(B(36, 42, 54, 54), 0, 180, fill=darken(c, 0.4), width=2 * SS)
    for x in (40, 45, 50):
        d.line(P((x, 47), (x, 51)), fill=darken(c, 0.4), width=SS)


def sh_ghost(d, c, a):
    d.pieslice(B(14, 6, 50, 42), 180, 360, fill=c, outline=darken(c), width=W)
    d.polygon(P((14, 24), (50, 24), (48, 38), (40, 32), (34, 44), (26, 34), (16, 40)),
              fill=c, outline=darken(c), width=SS)
    d.ellipse(B(22, 18, 29, 27), fill=darken(c, 0.35))
    d.ellipse(B(35, 18, 42, 27), fill=darken(c, 0.35))
    d.ellipse(B(24, 20, 27, 23), fill=(90, 160, 200, 255))
    d.ellipse(B(37, 20, 40, 23), fill=(90, 160, 200, 255))
    d.arc(B(26, 26, 38, 36), 0, 180, fill=darken(c, 0.4), width=2 * SS)


def sh_ghost_straps(d, c, a):
    sh_ghost(d, c, a)
    d.line(P((16, 26), (48, 34)), fill=(120, 118, 128, 255), width=3 * SS)
    d.line(P((16, 34), (48, 26)), fill=(120, 118, 128, 255), width=3 * SS)
    d.ellipse(B(29, 27, 35, 33), fill=(70, 70, 80, 255))


def sh_priest(d, c, a):
    d.polygon(P((20, 22), (44, 22), (52, 58), (12, 58)), fill=c, outline=darken(c), width=W)
    d.pieslice(B(18, 4, 46, 32), 180, 360, fill=c, outline=darken(c), width=2 * SS)
    d.ellipse(B(24, 12, 40, 28), fill=(20, 16, 24, 255))
    d.ellipse(B(27, 17, 31, 21), fill=(240, 90, 70, 255))
    d.ellipse(B(33, 17, 37, 21), fill=(240, 90, 70, 255))
    d.line(P((32, 32), (32, 50)), fill=a, width=3 * SS)
    d.line(P((25, 42), (39, 42)), fill=a, width=3 * SS)
    d.line(P((46, 30), (54, 44)), fill=(150, 140, 120, 255), width=2 * SS)
    d.ellipse(B(50, 42, 58, 50), fill=(216, 178, 88, 255), outline=(140, 110, 50, 255), width=SS)


def sh_rat(d, c, a):
    d.ellipse(B(8, 26, 44, 52), fill=c, outline=darken(c), width=W)
    d.polygon(P((38, 28), (58, 36), (38, 46)), fill=c, outline=darken(c), width=2 * SS)
    d.ellipse(B(36, 18, 48, 30), fill=c, outline=darken(c), width=2 * SS)
    d.ellipse(B(39, 21, 44, 26), fill=lighten(c, 0.25))
    d.arc(B(-16, 28, 16, 56), 270, 80, fill=(200, 150, 140, 255), width=3 * SS)
    d.ellipse(B(48, 32, 53, 37), fill=(200, 60, 60, 255))
    d.line(P((56, 34), (62, 30)), fill=lighten(c, 0.3), width=SS)
    d.line(P((56, 38), (62, 40)), fill=lighten(c, 0.3), width=SS)
    d.polygon(P((54, 40), (57, 47), (59, 40)), fill=(240, 236, 220, 255))


def sh_spider(d, c, a):
    for (x0, y0, x1, y1, mx, my) in ((22, 28, 4, 12, 12, 16), (22, 34, 2, 34, 10, 32),
                                     (22, 40, 6, 56, 12, 50), (42, 28, 60, 12, 52, 16),
                                     (42, 34, 62, 34, 54, 32), (42, 40, 58, 56, 52, 50)):
        d.line(P((x0, y0), (mx, my)), fill=darken(c, 0.85), width=2 * SS)
        d.line(P((mx, my), (x1, y1)), fill=darken(c, 0.85), width=2 * SS)
    d.ellipse(B(20, 26, 44, 50), fill=c, outline=darken(c), width=W)
    d.polygon(P((26, 30), (38, 30), (32, 44)), fill=a, outline=darken(c), width=SS)
    d.ellipse(B(26, 12, 38, 28), fill=c, outline=darken(c), width=2 * SS)
    for (x, y, r) in ((29, 17, 2), (35, 17, 2), (31, 22, 1), (33, 22, 1)):
        d.ellipse(B(x - r, y - r, x + r, y + r), fill=(240, 90, 70, 255))
    d.line(P((28, 26), (26, 32)), fill=(240, 236, 220, 255), width=2 * SS)
    d.line(P((36, 26), (38, 32)), fill=(240, 236, 220, 255), width=2 * SS)


def sh_wolf(d, c, a):
    d.polygon(P((8, 42), (22, 22), (28, 8), (36, 20), (54, 24), (60, 34), (46, 38), (40, 50), (24, 50)),
              fill=c, outline=darken(c), width=W)
    d.polygon(P((22, 22), (28, 8), (33, 20)), fill=darken(c, 0.75))
    d.ellipse(B(33, 24, 39, 30), fill=a)
    d.ellipse(B(35, 26, 38, 29), fill=(30, 24, 24, 255))
    d.polygon(P((44, 38), (62, 40), (58, 48), (42, 48)), fill=darken(c, 0.85), outline=darken(c, 0.5), width=SS)
    for x in (47, 52, 57):
        d.polygon(P((x, 40), (x + 2, 45), (x + 4, 40)), fill=(240, 236, 220, 255))
    d.line(P((14, 38), (24, 30)), fill=darken(c, 0.7), width=SS)


def sh_treant(d, c, a):
    d.polygon(P((24, 34), (40, 34), (44, 58), (36, 52), (32, 58), (28, 52), (20, 58)),
              fill=a, outline=darken(a), width=W)
    for (x, y, r) in ((20, 22, 13), (44, 22, 13), (32, 12, 13), (32, 28, 11)):
        d.ellipse(B(x - r, y - r, x + r, y + r), fill=c)
    d.ellipse(B(7, 9, 57, 39), outline=darken(c), width=W)
    d.rectangle(B(24, 34, 40, 46), fill=a)
    d.polygon(P((26, 36), (30, 38), (26, 42)), fill=(240, 200, 80, 255))
    d.polygon(P((38, 36), (34, 38), (38, 42)), fill=(240, 200, 80, 255))
    d.arc(B(27, 40, 37, 48), 0, 180, fill=darken(a, 0.5), width=2 * SS)
    speck(d, "leaves", (10, 10, 54, 34), lighten(c, 0.3), 8, 1.6)


def sh_crow(d, c, a):
    d.line(P((10, 52), (54, 52)), fill=(226, 218, 196, 255), width=4 * SS)
    d.ellipse(B(6, 48, 16, 56), fill=(226, 218, 196, 255))
    d.ellipse(B(48, 48, 58, 56), fill=(226, 218, 196, 255))
    d.ellipse(B(16, 22, 44, 48), fill=c, outline=darken(c, 0.4), width=W)
    d.polygon(P((30, 24), (52, 34), (30, 44)), fill=darken(c, 0.8))
    d.ellipse(B(34, 12, 50, 28), fill=c, outline=darken(c, 0.4), width=2 * SS)
    d.polygon(P((48, 18), (60, 22), (48, 26)), fill=(216, 178, 88, 255), outline=(140, 110, 50, 255), width=SS)
    d.ellipse(B(41, 17, 46, 22), fill=(240, 90, 70, 255))


def sh_slime(d, c, a):
    d.pieslice(B(8, 12, 56, 58), 180, 360, fill=c, outline=darken(c), width=W)
    d.polygon(P((8, 34), (56, 34), (54, 46), (46, 40), (40, 50), (32, 42), (24, 52), (16, 42), (10, 48)),
              fill=c, outline=darken(c), width=SS)
    d.ellipse(B(20, 26, 28, 36), fill=darken(c, 0.4))
    d.ellipse(B(36, 26, 44, 36), fill=darken(c, 0.4))
    d.arc(B(26, 34, 38, 44), 0, 180, fill=darken(c, 0.45), width=2 * SS)
    d.ellipse(B(16, 18, 28, 27), fill=lighten(c, 0.45))
    for (x, y, r) in ((44, 20, 2), (38, 16, 1.6)):
        d.ellipse(B(x - r, y - r, x + r, y + r), fill=lighten(c, 0.35))


def sh_slime_ember(d, c, a):
    sh_slime(d, c, a)
    d.line(P((16, 40), (24, 46)), fill=(255, 200, 90, 255), width=SS)
    d.line(P((40, 44), (48, 38)), fill=(255, 200, 90, 255), width=SS)
    d.ellipse(B(29, 44, 35, 50), fill=(255, 170, 70, 255))
    for (x, y, r) in ((20, 8, 2), (28, 4, 2.4), (36, 7, 1.8)):
        d.ellipse(B(x - r, y - r, x + r, y + r), fill=(150, 150, 160, 160))


def sh_bat(d, c, a):
    d.polygon(P((4, 20), (26, 26), (18, 40), (30, 36), (32, 48), (34, 36), (46, 40), (38, 26), (60, 20),
                (48, 12), (32, 18), (16, 12)), fill=c, outline=darken(c), width=SS)
    for (x0, y0, x1, y1) in ((12, 17, 18, 34), (52, 17, 46, 34)):
        d.line(P((x0, y0), (x1, y1)), fill=darken(c, 0.6), width=SS)
    d.polygon(P((26, 16), (28, 8), (31, 15)), fill=c)
    d.polygon(P((38, 16), (36, 8), (33, 15)), fill=c)
    d.ellipse(B(27, 20, 31, 24), fill=(240, 200, 90, 255))
    d.ellipse(B(33, 20, 37, 24), fill=(240, 200, 90, 255))
    d.polygon(P((29, 27), (31, 31), (33, 27)), fill=(240, 236, 220, 255))


def sh_lurker(d, c, a):
    _rock_base(d, c)
    speck(d, "lurk", (12, 16, 50, 46), darken(c, 0.8), 8, 1.6)
    eye(d, 32, 28, 9, (240, 200, 80, 255))
    d.line(P((16, 44), (48, 46)), fill=darken(c, 0.5), width=2 * SS)
    for x in (22, 30, 38):
        d.polygon(P((x, 44), (x + 3, 49), (x + 6, 44)), fill=(240, 236, 220, 255))


def sh_golem(d, c, a):
    d.polygon(P((18, 8), (46, 8), (48, 22), (40, 24), (40, 18), (24, 18), (24, 24), (16, 22)),
              fill=c, outline=darken(c), width=2 * SS)
    d.polygon(P((20, 24), (44, 24), (48, 46), (16, 46)), fill=c, outline=darken(c), width=W)
    d.rectangle(B(6, 24, 16, 44), fill=c, outline=darken(c), width=2 * SS)
    d.rectangle(B(48, 24, 58, 44), fill=c, outline=darken(c), width=2 * SS)
    d.rectangle(B(19, 46, 29, 58), fill=c, outline=darken(c), width=2 * SS)
    d.rectangle(B(35, 46, 45, 58), fill=c, outline=darken(c), width=2 * SS)
    d.ellipse(B(27, 11, 31, 15), fill=a)
    d.ellipse(B(33, 11, 37, 15), fill=a)
    d.ellipse(B(28, 30, 36, 38), fill=a)
    d.line(P((20, 28), (26, 34)), fill=darken(c, 0.6), width=SS)
    d.line(P((42, 40), (38, 34)), fill=darken(c, 0.6), width=SS)
    speck(d, "gol", (18, 26, 46, 44), (96, 148, 86, 255), 4, 1.6)


def sh_colossus(d, c, a):
    d.polygon(P((20, 4), (44, 4), (48, 18), (40, 20), (40, 14), (24, 14), (24, 20), (16, 18)),
              fill=c, outline=(120, 100, 150, 255), width=2 * SS)
    d.polygon(P((18, 20), (46, 20), (52, 48), (12, 48)), fill=c, outline=(120, 100, 150, 255), width=2 * SS)
    d.polygon(P((4, 20), (14, 22), (12, 46), (4, 40)), fill=c, outline=(120, 100, 150, 255), width=SS)
    d.polygon(P((60, 20), (50, 22), (52, 46), (60, 40)), fill=c, outline=(120, 100, 150, 255), width=SS)
    d.rectangle(B(17, 48, 28, 60), fill=c, outline=(120, 100, 150, 255), width=SS)
    d.rectangle(B(36, 48, 47, 60), fill=c, outline=(120, 100, 150, 255), width=SS)
    d.ellipse(B(26, 7, 30, 11), fill=a)
    d.ellipse(B(34, 7, 38, 11), fill=a)
    d.polygon(P((32, 24), (40, 34), (32, 44), (24, 34)), fill=a)
    d.polygon(P((32, 28), (36, 34), (32, 40), (28, 34)), fill=lighten(a, 0.4))
    d.line(P((20, 26), (26, 32)), fill=(120, 100, 150, 255), width=SS)


def sh_hound(d, c, a):
    d.polygon(P((8, 40), (22, 22), (28, 8), (36, 20), (54, 26), (58, 36), (44, 40), (38, 50), (22, 50)),
              fill=c, outline=darken(c), width=W)
    d.polygon(P((22, 22), (28, 8), (33, 20)), fill=darken(c, 0.75))
    d.ellipse(B(33, 24, 40, 31), fill=(200, 60, 60, 255))
    d.ellipse(B(35, 26, 38, 29), fill=(255, 140, 120, 255))
    d.line(P((12, 34), (20, 30)), fill=(226, 218, 196, 255), width=2 * SS)
    d.line(P((14, 40), (22, 36)), fill=(226, 218, 196, 255), width=2 * SS)
    for x in (44, 50):
        d.polygon(P((x, 38), (x + 2, 44), (x + 4, 38)), fill=(240, 236, 220, 255))


def sh_ghoul(d, c, a):
    d.ellipse(B(14, 6, 50, 46), fill=c, outline=darken(c), width=W)
    d.polygon(P((20, 40), (44, 40), (40, 56), (24, 56)), fill=c, outline=darken(c), width=2 * SS)
    d.ellipse(B(20, 18, 30, 30), fill=(240, 200, 80, 255))
    d.ellipse(B(34, 18, 44, 30), fill=(240, 200, 80, 255))
    d.ellipse(B(24, 22, 28, 26), fill=(30, 26, 24, 255))
    d.ellipse(B(38, 22, 42, 26), fill=(30, 26, 24, 255))
    d.polygon(P((22, 36), (42, 36), (38, 44), (26, 44)), fill=darken(c, 0.5))
    for x in (26, 31, 36):
        d.polygon(P((x, 36), (x + 2, 42), (x + 4, 36)), fill=(240, 236, 220, 255))


# ================================================================ SKILL GLYPHS

def sh_gravestone(d, c, a):
    d.rectangle(B(8, 50, 56, 58), fill=(96, 118, 76, 255), outline=(60, 76, 48, 255), width=2 * SS)
    for x in (12, 22, 44, 52):
        d.line(P((x, 50), (x - 2, 44)), fill=(110, 148, 90, 255), width=SS)
    d.pieslice(B(16, 6, 48, 38), 180, 360, fill=c, outline=darken(c), width=W)
    d.rectangle(B(16, 22, 48, 52), fill=c, outline=darken(c), width=W)
    d.line(P((16, 22), (16, 52)), fill=c, width=W)
    d.line(P((48, 22), (48, 52)), fill=c, width=W)
    d.line(P((32, 16), (32, 32)), fill=darken(c, 0.5), width=3 * SS)
    d.line(P((25, 22), (39, 22)), fill=darken(c, 0.5), width=3 * SS)
    d.line(P((20, 40), (30, 40)), fill=darken(c, 0.7), width=SS)
    d.line(P((20, 45), (34, 45)), fill=darken(c, 0.7), width=SS)


def sh_tree(d, c, a):
    d.polygon(P((28, 34), (36, 34), (38, 56), (26, 56)), fill=a, outline=darken(a), width=W)
    d.line(P((30, 44), (24, 38)), fill=a, width=2 * SS)
    for (x, y, r) in ((21, 25, 13), (43, 25, 13), (32, 13, 13), (32, 29, 12)):
        d.ellipse(B(x - r, y - r, x + r, y + r), fill=c)
    d.ellipse(B(8, 12, 56, 42), outline=darken(c), width=W)
    speck(d, "tree", (12, 14, 52, 38), lighten(c, 0.35), 9, 1.6)


def sh_anvil(d, c, a):
    d.polygon(P((6, 18), (58, 18), (52, 30), (38, 34), (38, 44), (26, 44), (26, 34), (14, 26)),
              fill=c, outline=darken(c), width=W)
    d.rectangle(B(18, 44, 46, 54), fill=c, outline=darken(c), width=W)
    d.line(P((10, 20), (54, 20)), fill=lighten(c, 0.35), width=2 * SS)
    star(d, 48, 10, 4, (255, 200, 90, 255))
    star(d, 55, 15, 3, (255, 170, 70, 255))



def sh_log_rotten(d, c, a):  # rotten_logs
    _log_body(d, c)
    speck(d, "rotspots", (10, 26, 38, 42), (98, 110, 60, 255), 8, 2.2)
    d.ellipse(B(14, 20, 22, 27), fill=(160, 140, 110, 255), outline=(110, 92, 70, 255), width=SS)
    d.line(P((18, 26), (18, 30)), fill=(110, 92, 70, 255), width=SS)
    d.polygon(P((36, 20), (42, 14), (44, 22)), fill=darken(c, 0.6))


def sh_rubble(d, c, a):  # stone_debris
    for (x, y, w_, h) in ((14, 44, 11, 8), (30, 40, 9, 10), (44, 46, 9, 7), (22, 30, 8, 7), (38, 28, 7, 6)):
        pts = P((x - w_, y + h), (x - w_ + 3, y - h), (x + w_ - 2, y - h + 2), (x + w_, y + h - 1))
        d.polygon(pts, fill=c if (x + y) % 3 else lighten(c, 0.15), outline=darken(c), width=2 * SS)
    speck(d, "rubble", (10, 24, 54, 52), darken(c, 0.75), 8, 1.4)
    d.line(P((26, 34), (30, 38)), fill=darken(c, 0.6), width=SS)



# ---------------------------------------------------------------- grave finds

def sh_shroud(d, c, a):  # rotted_shroud
    d.polygon(P((12, 10), (52, 10), (50, 40), (44, 50), (38, 42), (32, 52), (26, 42), (20, 50), (14, 40)),
              fill=c, outline=darken(c), width=W)
    for x in (22, 32, 42):
        d.line(P((x, 13), (x - 1, 42)), fill=darken(c, 0.72), width=2 * SS)
    d.ellipse(B(27, 22, 35, 30), fill=darken(c, 0.55))  # moth hole
    d.line(P((16, 12), (48, 12)), fill=lighten(c, 0.3), width=SS)
    speck(d, "shroud", (14, 14, 50, 40), darken(c, 0.7), 8, 1.6)


def sh_nails(d, c, a):  # coffin_nails
    d.line(P((24, 52), (40, 10)), fill=darken(c, 0.8), width=5 * SS)          # back nail
    d.rectangle(B(34, 6, 46, 16), fill=darken(c, 0.8), outline=darken(c, 0.5), width=SS)
    d.line(P((16, 50), (25, 22)), fill=c, width=6 * SS)                        # front nail (bent)
    d.line(P((25, 22), (29, 10)), fill=c, width=6 * SS)
    d.rectangle(B(22, 6, 37, 17), fill=c, outline=darken(c), width=SS)         # square head
    d.line(P((18, 48), (26, 24)), fill=lighten(c, 0.35), width=SS)
    speck(d, "nailrust", (14, 10, 46, 52), (150, 86, 48, 255), 10, 1.6)


def sh_locket(d, c, a):  # rusted_locket
    for (x, y) in ((16, 12), (23, 8), (48, 11)):
        d.ellipse(B(x - 4, y - 3, x + 4, y + 3), outline=darken(c), width=2 * SS)  # broken chain
    d.ellipse(B(18, 18, 46, 52), fill=c, outline=darken(c), width=W)               # body
    d.ellipse(B(28, 12, 36, 20), fill=c, outline=darken(c), width=SS)              # bail
    d.line(P((32, 20), (32, 50)), fill=darken(c, 0.55), width=2 * SS)              # seam
    d.ellipse(B(29, 31, 35, 39), fill=a, outline=darken(a), width=SS)             # inset stone
    d.arc(B(21, 22, 43, 48), 160, 245, fill=lighten(c, 0.4), width=2 * SS)         # shine
    speck(d, "tarnish", (20, 22, 44, 50), darken(c, 0.65), 8, 1.4)


def sh_teeth(d, c, a):  # yellowed_teeth
    for (x, y, w_) in ((22, 28, 9), (35, 22, 10), (46, 32, 7), (30, 42, 8)):
        d.ellipse(B(x - w_, y - w_, x + w_, y + int(w_ * 0.6)), fill=c, outline=darken(c), width=SS)
        d.polygon(P((x - w_ * 0.6, y), (x - w_ * 0.3, y + w_), (x - w_ * 0.1, y)), fill=c, outline=darken(c), width=SS)
        d.polygon(P((x + w_ * 0.6, y), (x + w_ * 0.3, y + w_), (x + w_ * 0.1, y)), fill=c, outline=darken(c), width=SS)
        d.ellipse(B(x - 3, y - 4, x + 1, y), fill=lighten(c, 0.4))
    speck(d, "decay", (18, 22, 52, 46), (150, 118, 66, 255), 7, 1.5)


def sh_book(d, c, a):  # nincompoops_tome
    d.polygon(P((48, 10), (53, 15), (53, 52), (50, 52)), fill=(224, 212, 186, 255), outline=darken(c, 0.5), width=SS)
    for yy in (18, 26, 34, 42):
        d.line(P((49, yy), (52, yy)), fill=(180, 168, 142, 255), width=SS)     # page lines
    d.polygon(P((14, 10), (48, 10), (50, 52), (16, 52)), fill=c, outline=darken(c), width=W)  # cover
    d.rectangle(B(14, 10, 21, 52), fill=darken(c, 0.7), outline=darken(c, 0.5), width=SS)     # spine
    cx, cy = 35, 29
    d.ellipse(B(cx - 8, cy - 9, cx + 8, cy + 5), fill=a, outline=darken(a), width=SS)         # skull emblem
    d.rectangle(B(cx - 5, cy + 3, cx + 5, cy + 10), fill=a, outline=darken(a), width=SS)
    d.ellipse(B(cx - 5, cy - 5, cx - 1, cy - 1), fill=darken(a, 0.35))
    d.ellipse(B(cx + 1, cy - 5, cx + 5, cy - 1), fill=darken(a, 0.35))
    d.polygon(P((40, 10), (45, 10), (45, 25), (42, 21), (40, 25)), fill=(160, 44, 52, 255))   # ribbon
    d.line(P((26, 45), (45, 45)), fill=darken(c, 0.45), width=SS)



def sh_fangs(d, c, a):  # jagged_fangs
    for (x, top, w_, curve) in ((20, 12, 7, 3), (34, 8, 8, -2), (46, 14, 6, 2)):
        d.polygon(P((x - w_, top), (x + w_, top), (x + w_ * 0.3 + curve, top + 34), (x - w_ * 0.2 + curve, top + 20)),
                  fill=c, outline=darken(c), width=W)
        d.line(P((x, top + 4), (x + curve, top + 26)), fill=lighten(c, 0.35), width=SS)
    d.line(P((14, 13), (52, 11)), fill=darken(c, 0.5), width=2 * SS)  # gumline
    speck(d, "fangstain", (16, 26, 50, 44), (150, 90, 70, 255), 5, 1.4)


SHAPES = {n[3:]: fn for n, fn in list(globals().items()) if n.startswith("sh_")}

# ================================================================ TABLES

ITEMS = {
    "flesh": ("flesh", (196, 106, 106), None),
    "bones": ("bones", (226, 218, 196), None),
    "blood": ("blood", (168, 30, 40), None),
    # grave finds (necromantic body parts & reagents)
    "grave_dust": ("dust_skull", (150, 143, 128), None),
    "rancid_sinew": ("sinew", (176, 104, 108), None),
    "cracked_skull": ("skull", (224, 214, 190), (120, 40, 40)),
    "bone_marrow": ("marrow", (232, 200, 164), None),
    "jagged_fangs": ("fangs", (234, 226, 202), None),
    "withered_heart": ("heart", (150, 44, 50), None),
    "nincompoops_tome": ("book", (92, 62, 78), (214, 204, 176)),
    "rotten_logs": ("log_rotten", (110, 96, 66), None),
    "stone_debris": ("rubble", (150, 146, 138), None),
    # lumbering — woods
    "brittle_branches": ("branch", (150, 132, 96), None),
    "blackthorn_timber": ("log_thorned", (72, 60, 56), (40, 32, 34)),
    "ash_burl": ("log_pale", (176, 166, 144), None),
    "angel_oak": ("log_blessed", (198, 178, 122), (150, 120, 70)),
    "sable_walnut_heartwood": ("log_dark", (78, 54, 42), None),
    # lumbering — herbal
    "pale_lichen": ("lichen", (156, 172, 146), None),
    "velvet_moss": ("moss", (68, 112, 66), None),
    "poison_thorns": ("thorns", (96, 116, 80), (60, 40, 60)),
    "nightshade_vine": ("vine", (108, 86, 138), (60, 40, 80)),
    "briar_blossom": ("flower", (188, 96, 158), (150, 60, 120)),
    "amber_droplet": ("amber", (206, 142, 52), None),
    "silken_husk": ("husk", (206, 200, 182), None),
    "petrified_acorn": ("acorn", (150, 132, 104), (110, 92, 70)),
    "raven_quill": ("feather", (66, 60, 82), (30, 28, 40)),
    # spelunking — stone / ore / gem
    "slate_slab": ("slab", (92, 100, 112), None),
    "granite_cobble": ("rock_speckled", (146, 140, 132), None),
    "basalt_debris": ("rock_columns", (72, 70, 78), None),
    "peridotite_chunk": ("rock_crystals", (112, 132, 92), (90, 150, 90)),
    "sphalerite_nugget": ("ore_sphalerite", (154, 124, 92), (200, 180, 120)),
    "pyrite_dust": ("dust_sparkle", (186, 164, 92), (230, 210, 120)),
    "nickel_granule": ("ore_nickel", (172, 176, 182), None),
    "tungsten_lump": ("ore_tungsten", (118, 120, 132), None),
    "cobalt_powder": ("powder_vial", (66, 96, 186), None),
    "malachite_flake": ("flakes", (42, 146, 104), (30, 110, 80)),
    "quartz_geode": ("geode", (200, 190, 214), (150, 140, 180)),
    "beryl_cluster": ("cluster", (122, 204, 184), (80, 170, 150)),
    "obsidian_shard": ("shard", (44, 40, 54), (90, 70, 120)),
    "imperial_jade_knot": ("jade_torus", (62, 172, 124), (40, 130, 90)),
    # dungeon / prestige drops (new)
    "heartwood_core": ("core_shards", (108, 158, 82), (70, 120, 50)),
    "bloodsap_resin": ("gel", (156, 52, 50), None),
    "thornheart_bud": ("beads", (150, 54, 74), (100, 30, 50)),
    "pale_silkgland": ("gland", (212, 206, 190), None),
    "dryads_heartstone": ("idol", (146, 138, 126), (110, 100, 90)),
    "verdigris_cyst": ("bile", (92, 152, 116), None),
    "cinder_slag": ("ember_core", (182, 84, 42), (230, 140, 60)),
    "resonant_geode": ("void_prism", (150, 172, 192), (110, 140, 170)),
    "living_jade_core": ("golem_heart", (52, 180, 116), (30, 140, 90)),
    "obsidian_wyrm_scale": ("wing", (58, 50, 80), (120, 90, 150)),
    # tools
    "rusty_shovel": ("shovel", (150, 96, 62), (110, 82, 58)),
    "rusty_hatchet": ("hatchet", (150, 96, 62), (110, 82, 58)),
    "rusty_pickaxe": ("pickaxe", (150, 96, 62), (110, 82, 58)),
    "galvanized_shovel": ("shovel", (168, 182, 192), (110, 82, 58)),
    "galvanized_hatchet": ("hatchet", (168, 182, 192), (110, 82, 58)),
    "galvanized_pickaxe": ("pickaxe", (168, 182, 192), (110, 82, 58)),
    "reinforced_shovel": ("shovel", (104, 118, 134), (74, 60, 48)),
    "reinforced_hatchet": ("hatchet", (104, 118, 134), (74, 60, 48)),
    "reinforced_pickaxe": ("pickaxe", (104, 118, 134), (74, 60, 48)),
    "tempered_shovel": ("shovel", (78, 116, 214), (54, 48, 60)),
    "tempered_hatchet": ("hatchet", (78, 116, 214), (54, 48, 60)),
    "tempered_pickaxe": ("pickaxe", (78, 116, 214), (54, 48, 60)),
}

SKILLS = {
    "graverobbing": ("gravestone", (196, 188, 166), (110, 92, 70)),
    "lumbering": ("tree", (86, 148, 86), (110, 82, 58)),
    "spelunking": ("pickaxe", (150, 160, 172), (110, 82, 58)),
}





UI = {
    "mortimer": ("ghost", (206, 210, 218), None),
}

MINIONS = {
    "zombie": ("zombie_head", (120, 150, 96), (80, 110, 60)),
    "skeleton": ("skeleton_body", (222, 216, 198), (150, 140, 120)),
    "ghoul": ("ghoul", (150, 156, 120), (100, 110, 80)),
    "undead_hound": ("hound", (128, 116, 104), (80, 70, 62)),
}

def render(table, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    for key, (shape, main, accent) in table.items():
        img, d = canvas()
        c = tuple(main) + (255,)
        a = (tuple(accent) + (255,)) if accent else darken(c, 0.7)
        SHAPES[shape](d, c, a)
        img = finish(img)
        img = img.resize((96, 96), Image.LANCZOS)
        img.save(os.path.join(out_dir, key + ".png"))
    print("wrote %d icons to %s" % (len(table), out_dir))


def main():
    render(ITEMS, "icons/items")
    render(SKILLS, "icons/skills")
    render(UI, "icons/ui")
    render(MINIONS, "icons/minions")


if __name__ == "__main__":
    main()
