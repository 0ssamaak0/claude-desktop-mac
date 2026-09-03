#!/usr/bin/env python3
"""Generate the Thinspace app-icon layer PNGs described in icon.md.

Draws the four flat silhouettes consumed by Resources/AppIcon.icon —
Icon Composer supplies all shading, so every asset is white-on-transparent.
The composition is identical in every appearance; only the fills in
icon.json change. Geometry lives in the constants below and must match
the table in icon.md.

Requires Pillow:  python3 generate_icon_layers.py --out DIR [--sheet PATH]
"""
import argparse
from PIL import Image, ImageChops, ImageDraw, ImageFilter

CANVAS = 1024          # Icon Composer design canvas, points
SS = 4                 # supersampling factor for clean edges

# The capsule: the Chat Bar's silhouette. 3.14:1, fully rounded.
CAP_W, CAP_H = 704, 224
CAP_X0 = (CANVAS - CAP_W) / 2          # 160
CAP_Y0 = (CANVAS - CAP_H) / 2          # 400
CAP_X1, CAP_Y1 = CAP_X0 + CAP_W, CAP_Y0 + CAP_H
CAP_R = CAP_H / 2                      # 112 — fully rounded ends

# The thin space: a vertical cut at 33% of the capsule's length.
SPLIT = 0.33
GAP_W = 40
GAP_CX = CAP_X0 + SPLIT * CAP_W        # 392.32
GAP_X0, GAP_X1 = GAP_CX - GAP_W / 2, GAP_CX + GAP_W / 2

# The caret: one shape in every appearance — soft round tips,
# overshooting the capsule top and bottom. Same mark as the menu bar's,
# with the overshoot the menu bar cannot afford at 18 px.
CARET_OVERSHOOT = 34
CARET_TIP_R = GAP_W / 2                # fully rounded tips

# Bloom (soak): light soaking into the glass, clipped to the capsule.
SOAK_W, SOAK_BLUR = 170, 45
# Spill (fan): the glow escaping past the capsule, present in every mode.
SPILL_W, SPILL_OVER, SPILL_R, SPILL_BLUR = 104, 90, 52, 66
SPILL_WIN_PAD_X, SPILL_WIN_Y0, SPILL_WIN_Y1, SPILL_WIN_R, SPILL_WIN_BLUR = 110, 240, 784, 80, 44


def s(v):
    return v * SS


def blank():
    return Image.new("L", (CANVAS * SS, CANVAS * SS), 0)


def rrect(mask, box, radius, fill=255):
    ImageDraw.Draw(mask).rounded_rectangle([s(box[0]), s(box[1]), s(box[2]), s(box[3])],
                                           radius=s(radius), fill=fill)
    return mask


def rect(mask, box, fill=255):
    ImageDraw.Draw(mask).rectangle([s(box[0]), s(box[1]), s(box[2]), s(box[3])], fill=fill)
    return mask


def outer_capsule():
    return rrect(blank(), (CAP_X0, CAP_Y0, CAP_X1, CAP_Y1), CAP_R)


def capsule():
    """Two slabs with a real void between them — never a bar over a pill."""
    m = outer_capsule()
    return rect(m, (GAP_X0, CAP_Y0 - 1, GAP_X1, CAP_Y1 + 1), fill=0)


def caret():
    """The one caret: soft-tipped, overshooting the capsule in every mode."""
    return rrect(blank(), (GAP_X0, CAP_Y0 - CARET_OVERSHOOT, GAP_X1, CAP_Y1 + CARET_OVERSHOOT),
                 CARET_TIP_R)


def bloom():
    """Soak: a soft column of light inside the capsule's outer silhouette."""
    col = rect(blank(), (GAP_CX - SOAK_W / 2, CAP_Y0, GAP_CX + SOAK_W / 2, CAP_Y1))
    col = col.filter(ImageFilter.GaussianBlur(s(SOAK_BLUR)))
    return ImageChops.multiply(col, outer_capsule())


def spill():
    """Fan: the glow escaping past the capsule, contained to a soft column."""
    fan = rrect(blank(), (GAP_CX - SPILL_W / 2, CAP_Y0 - SPILL_OVER,
                          GAP_CX + SPILL_W / 2, CAP_Y1 + SPILL_OVER), SPILL_R)
    fan = fan.filter(ImageFilter.GaussianBlur(s(SPILL_BLUR)))
    win = rrect(blank(), (GAP_CX - SPILL_WIN_PAD_X, SPILL_WIN_Y0,
                          GAP_CX + SPILL_WIN_PAD_X, SPILL_WIN_Y1), SPILL_WIN_R)
    win = win.filter(ImageFilter.GaussianBlur(s(SPILL_WIN_BLUR)))
    return ImageChops.multiply(fan, win)


def export(mask, path):
    out = Image.new("RGBA", mask.size, (255, 255, 255, 0))
    out.putalpha(mask)
    out = out.resize((CANVAS, CANVAS), Image.LANCZOS)
    out.save(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--sheet")
    args = ap.parse_args()
    layers = {"capsule": capsule(), "caret": caret(), "bloom": bloom(), "spill": spill()}
    for name, m in layers.items():
        export(m, f"{args.out}/{name}.png")
    if args.sheet:
        small = {k: m.resize((512, 512), Image.LANCZOS) for k, m in layers.items()}
        grid = Image.new("RGB", (2 * 512 + 30, 2 * 512 + 30), (24, 26, 32))
        for i, k in enumerate(("capsule", "caret", "bloom", "spill")):
            cell = Image.new("RGBA", (512, 512), (24, 26, 32, 255))
            solid = Image.new("RGBA", (512, 512), (235, 238, 245, 0))
            solid.putalpha(small[k])
            cell.alpha_composite(solid)
            grid.paste(cell.convert("RGB"), (10 + (i % 2) * 522, 10 + (i // 2) * 522))
        grid.save(args.sheet)
    print("wrote", ", ".join(sorted(layers)))


if __name__ == "__main__":
    main()
