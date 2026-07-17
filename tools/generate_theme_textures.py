"""Panel textures for the Lanternlight theme (P8, v3).

Run from the project root:  python3 tools/generate_theme_textures.py

v3 quality rules (v2 read as low-quality and why):
  - Everything is drawn 4x SUPERSAMPLED and LANCZOS-downscaled — v2 drew at
    1x with aliased primitives, so every border was jaggy.
  - NO noise grain — 9-patch STRETCHES the texture center, which smeared the
    grain into streaks. Fills are smooth vertical gradients: they survive
    any stretching invisibly.
  - Bevel lighting instead of flat borders: a crisp near-black contour, one
    subtle frame line, a 1px inner top highlight and 1px inner bottom shade.
  - Corner ornament is a single clean gold diamond stud per corner (inside
    the 9-patch margin so it never stretches), not clip-art L-ticks.

  theme/textures/panel_card.png     elevated card / main panel   (margins 20)
  theme/textures/panel_inset.png    sunken wells / inset panels  (margins 16)
  theme/textures/panel_tooltip.png  tooltip / popup              (margins 18)
  theme/textures/divider.png        HSeparator line              (margins 24 l/r)
"""
from PIL import Image, ImageDraw
import os

OUT = 128          # final texture size (9-patch margins in the theme: 20px)
SS = 4             # supersample factor
S = OUT * SS


def rr(d, box, radius, **kw):
    d.rounded_rectangle(box, radius=radius * SS, **kw)


def base_canvas():
    return Image.new("RGBA", (S, S), (0, 0, 0, 0))


def vgrad_fill(img, mask_radius, top, bottom, alpha=255):
    """Rounded-rect filled with a smooth vertical gradient."""
    grad = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gd = ImageDraw.Draw(grad)
    for y in range(S):
        t = y / S
        col = tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)) + (alpha,)
        gd.line([(0, y), (S, y)], fill=col)
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, S - 1, S - 1), radius=mask_radius * SS, fill=255)
    img.paste(grad, (0, 0), mask)
    return img


def stud(d, cx, cy, r, fill, edge):
    """A small clean diamond stud (drawn supersampled => smooth)."""
    pts = [(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)]
    d.polygon(pts, fill=fill)
    d.line(pts + [pts[0]], fill=edge, width=SS)
    # tiny highlight facet
    d.polygon([(cx, cy - r * 0.55), (cx + r * 0.55, cy), (cx, cy), (cx - r * 0.2, cy - r * 0.2)],
              fill=(255, 236, 190, 90))


def corner_studs(d, inset, r, fill=(166, 132, 74, 255), edge=(60, 44, 22, 255)):
    for cx, cy in ((inset, inset), (S - inset, inset), (inset, S - inset), (S - inset, S - inset)):
        stud(d, cx, cy, r, fill, edge)


def finish(img):
    return img.resize((OUT, OUT), Image.LANCZOS)


def make_card():
    """Elevated panel: gradient body, dark contour, violet frame, bevel, studs."""
    img = base_canvas()
    img = vgrad_fill(img, 10, (30, 26, 46), (18, 15, 29), alpha=250)
    d = ImageDraw.Draw(img)
    # crisp near-black contour
    rr(d, (0, 0, S - 1, S - 1), 10, outline=(5, 4, 10, 255), width=2 * SS)
    # subtle violet frame just inside
    rr(d, (2 * SS, 2 * SS, S - 1 - 2 * SS, S - 1 - 2 * SS), 9, outline=(74, 62, 104, 255), width=SS)
    # bevel: light catches the top inner edge, shade pools at the bottom
    rr(d, (3 * SS, 3 * SS, S - 1 - 3 * SS, S - 1 - 3 * SS), 8, outline=(110, 96, 150, 70), width=SS)
    d.line([(12 * SS, 4 * SS), (S - 12 * SS, 4 * SS)], fill=(150, 132, 190, 60), width=SS)
    d.line([(12 * SS, S - 5 * SS), (S - 12 * SS, S - 5 * SS)], fill=(0, 0, 0, 90), width=SS)
    corner_studs(d, 10 * SS, 3.2 * SS)
    return finish(img)


def make_inset():
    """Sunken well: darker gradient (lit from below the rim), inner top shadow."""
    img = base_canvas()
    img = vgrad_fill(img, 8, (10, 8, 18), (16, 13, 26), alpha=255)
    d = ImageDraw.Draw(img)
    rr(d, (0, 0, S - 1, S - 1), 8, outline=(4, 3, 8, 255), width=SS)
    # the rim's cast shadow: a soft band inside the top edge
    for i, a in enumerate((90, 60, 35, 18)):
        d.line([(3 * SS, (2 + i) * SS), (S - 3 * SS, (2 + i) * SS)], fill=(0, 0, 0, a), width=SS)
    # faint bottom-inner light (light bounces into the well)
    d.line([(6 * SS, S - 3 * SS), (S - 6 * SS, S - 3 * SS)], fill=(96, 84, 130, 45), width=SS)
    rr(d, (SS, SS, S - 1 - SS, S - 1 - SS), 8, outline=(54, 46, 78, 160), width=SS)
    return finish(img)


def make_tooltip():
    """Near-black scrap with a refined double gold frame."""
    img = base_canvas()
    img = vgrad_fill(img, 9, (20, 17, 31), (12, 10, 20), alpha=252)
    d = ImageDraw.Draw(img)
    rr(d, (0, 0, S - 1, S - 1), 9, outline=(5, 4, 10, 255), width=2 * SS)
    rr(d, (2 * SS, 2 * SS, S - 1 - 2 * SS, S - 1 - 2 * SS), 8, outline=(172, 136, 76, 235), width=SS)
    rr(d, (4 * SS, 4 * SS, S - 1 - 4 * SS, S - 1 - 4 * SS), 7, outline=(96, 74, 40, 140), width=SS)
    corner_studs(d, 9 * SS, 2.8 * SS, fill=(196, 158, 92, 255))
    return finish(img)


def make_divider():
    """A hairline that brightens toward the middle, gold studs at the tips."""
    W, H = 240, 9
    img = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    mid = H * SS // 2
    for x in range(W * SS):
        t = x / (W * SS)
        fade = min(min(t, 1 - t) * 4.0, 1.0)
        d.point((x, mid), fill=(122, 104, 158, int(200 * fade)))
        d.point((x, mid - SS), fill=(60, 50, 86, int(110 * fade)))
        d.point((x, mid + SS), fill=(6, 5, 12, int(150 * fade)))
    for cx in (13 * SS, (W - 13) * SS):
        stud(d, cx, mid, 3.4 * SS, (166, 132, 74, 255), (60, 44, 22, 255))
    return img.resize((W, H), Image.LANCZOS)


def main():
    os.makedirs("theme/textures", exist_ok=True)
    make_card().save("theme/textures/panel_card.png")
    make_inset().save("theme/textures/panel_inset.png")
    make_tooltip().save("theme/textures/panel_tooltip.png")
    make_divider().save("theme/textures/divider.png")
    print("wrote 4 theme textures (supersampled, grain-free)")


if __name__ == "__main__":
    main()
