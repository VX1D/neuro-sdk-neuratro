#!/usr/bin/env python3
"""Rasterise a neuro-game draw-op log (scripts/raster.lua output) to PNG contact sheets.

Optional half of the tool: everything a caller usually asserts on lives in the .ops text.
This only exists so a human (or an agent with eyes) can look at the frame. Needs Pillow.

    python3 scripts/raster_png.py FILE.ops OUT_PREFIX [--crop X,Y,W,H] [--cols N] [--zoom Z]

Writes OUT_PREFIX_<persona>.png, one contact sheet per persona in the log.
"""
import os
import re
import sys
import math

try:
    # NOTE: text is rendered with DejaVuSans (or whatever of the list below exists), NOT with the
    # font the Lua side measured with. So a string's WIDTH in a PNG is indicative, never exact --
    # a label can appear to overflow a box that in the game fits it by construction. Judge box fit
    # from the op log (the R entries carry real geometry); judge colour, alpha and layout from the
    # PNG. This bit once looked like a badge-chip overflow bug and was not one.
    from PIL import Image, ImageDraw, ImageFont
except ImportError:  # degrade gracefully -- the caller still has the op log
    sys.stderr.write("raster_png: Pillow (PIL) not installed; the .ops log is still valid\n")
    sys.exit(3)

FONT_PATHS = (
    "/usr/share/fonts/TTF/DejaVuSans.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/usr/share/fonts/noto/NotoSans-Regular.ttf",
    "/usr/share/fonts/gnu-free/FreeSans.otf",
)
_FONT_FILE = next((p for p in FONT_PATHS if os.path.exists(p)), None)
_fonts = {}


def font(px):
    px = max(6, int(px))
    if px not in _fonts:
        _fonts[px] = (ImageFont.truetype(_FONT_FILE, px) if _FONT_FILE
                      else ImageFont.load_default())
    return _fonts[px]


UNESC = re.compile(r"%([0-9A-Fa-f]{2})")


def unescape(tok):
    return UNESC.sub(lambda m: chr(int(m.group(1), 16)), tok)


def parse(path):
    """-> (frames, size). Each frame: dict(persona, scene, t, ops[list[str]], errs)."""
    frames, cur, size = [], None, (1280, 720)
    with open(path) as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            if line.startswith("FRAME "):
                p = line.split()
                cur = {"persona": p[1], "scene": p[2], "t": float(p[3]), "ops": [], "errs": []}
                wh = p[4].split("x")
                size = (int(wh[0]), int(wh[1]))
                frames.append(cur)
            elif line.startswith("! "):
                if cur is not None:
                    cur["errs"].append(line[2:])
            elif cur is not None:
                cur["ops"].append(line)
    return frames, size


def rgba(parts):
    r, g, b, a = (float(v) for v in parts[:4])
    clamp = lambda v: int(max(0.0, min(1.0, v)) * 255)
    return (clamp(r), clamp(g), clamp(b), clamp(a))


def composite(base, tile, ox, oy, sc):
    """Paste `tile` at (ox, oy), cropped to the scissor rect `sc` if one is active."""
    if sc:
        sx, sy, sw, sh = sc
        x0, y0 = max(ox, int(sx)), max(oy, int(sy))
        x1 = min(ox + tile.width, int(sx + sw))
        y1 = min(oy + tile.height, int(sy + sh))
        if x1 <= x0 or y1 <= y0:
            return
        tile = tile.crop((x0 - ox, y0 - oy, x1 - ox, y1 - oy))
        ox, oy = x0, y0
    if ox >= base.width or oy >= base.height:
        return
    if ox + tile.width <= 0 or oy + tile.height <= 0:
        return
    base.alpha_composite(tile, (max(0, ox), max(0, oy)), (max(0, -ox), max(0, -oy)))


MAX_TILE = 8000


def render(frame, size, bg=(18, 16, 20, 255)):
    W, H = size
    base = Image.new("RGBA", (W, H), bg)
    sc = None
    for op in frame["ops"]:
        p = op.split()
        k = p[0]
        try:
            if k == "S":
                sc = None if p[1] == "off" else tuple(float(v) for v in p[1:5])
                continue
            # verb [mode] r g b a blend ...
            has_mode = k in ("R", "C", "E", "A", "P")
            i = 1 + (1 if has_mode else 0)
            mode = p[1] if has_mode else None
            c = rgba(p[i:i + 4])
            i += 5  # rgba + blend token
            if c[3] == 0:
                continue
            if k == "R":
                x, y, w, h, rad, lw = (float(v) for v in p[i:i + 6])
                if w <= 0 or h <= 0:
                    continue
                pad = int(math.ceil(lw)) + 1
                tw, th = int(math.ceil(w)) + pad * 2, int(math.ceil(h)) + pad * 2
                if tw > MAX_TILE or th > MAX_TILE:
                    continue
                tile = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
                d = ImageDraw.Draw(tile)
                box = (pad, pad, pad + w - 1, pad + h - 1)
                r = int(min(rad, w / 2, h / 2))
                if mode == "fill":
                    # PIL's rounded_rectangle draws nothing for a degenerate box, so every 1px
                    # rect -- which is what the pixel-art prims are made of -- silently vanished
                    if r <= 0 or w <= 2 or h <= 2:
                        d.rectangle(box, fill=c)
                    else:
                        d.rounded_rectangle(box, radius=r, fill=c)
                else:
                    d.rounded_rectangle(box, radius=r, outline=c, width=max(1, int(lw)))
                composite(base, tile, int(x) - pad, int(y) - pad, sc)
            elif k in ("C", "E"):
                if k == "C":
                    x, y, rx, lw = (float(v) for v in p[i:i + 4])
                    ry = rx
                else:
                    x, y, rx, ry, lw = (float(v) for v in p[i:i + 5])
                if rx <= 0 or ry <= 0 or rx > MAX_TILE or ry > MAX_TILE:
                    continue
                pad = int(math.ceil(lw)) + 2
                tile = Image.new("RGBA", (int(rx * 2) + pad * 2 + 2, int(ry * 2) + pad * 2 + 2),
                                 (0, 0, 0, 0))
                d = ImageDraw.Draw(tile)
                box = (pad, pad, pad + rx * 2, pad + ry * 2)
                if mode == "fill":
                    d.ellipse(box, fill=c)
                else:
                    d.ellipse(box, outline=c, width=max(1, int(lw)))
                composite(base, tile, int(x - rx) - pad, int(y - ry) - pad, sc)
            elif k == "A":
                x, y, r, a1, a2, lw = (float(v) for v in p[i:i + 6])
                if r <= 0 or r > MAX_TILE:
                    continue
                pad = int(math.ceil(lw)) + 2
                tile = Image.new("RGBA", (int(r * 2) + pad * 2 + 2,) * 2, (0, 0, 0, 0))
                d = ImageDraw.Draw(tile)
                box = (pad, pad, pad + r * 2, pad + r * 2)
                d1, d2 = math.degrees(a1), math.degrees(a2)
                if mode == "fill":
                    d.pieslice(box, d1, d2, fill=c)
                else:
                    d.arc(box, d1, d2, fill=c, width=max(1, int(lw)))
                composite(base, tile, int(x - r) - pad, int(y - r) - pad, sc)
            elif k in ("L", "P", "D"):
                if k == "D":
                    lw, nums = 1.0, [float(v) for v in p[i:]]
                else:
                    lw, nums = float(p[i]), [float(v) for v in p[i + 1:]]
                xs, ys = nums[0::2], nums[1::2]
                if len(xs) < 1:
                    continue
                pad = int(math.ceil(lw)) + 3
                x0, y0 = int(min(xs)) - pad, int(min(ys)) - pad
                tw = int(max(xs)) - x0 + pad * 2
                th = int(max(ys)) - y0 + pad * 2
                if tw <= 0 or th <= 0 or tw > MAX_TILE or th > MAX_TILE:
                    continue
                tile = Image.new("RGBA", (tw, th), (0, 0, 0, 0))
                d = ImageDraw.Draw(tile)
                rel = [(px - x0, py - y0) for px, py in zip(xs, ys)]
                if k == "D":
                    d.point(rel, fill=c)
                elif k == "L":
                    if len(rel) >= 2:
                        d.line(rel, fill=c, width=max(1, int(lw)))
                elif mode == "fill" and len(rel) >= 3:
                    d.polygon(rel, fill=c)
                elif len(rel) >= 2:
                    d.line(rel + [rel[0]], fill=c, width=max(1, int(lw)))
                composite(base, tile, x0, y0, sc)
            elif k == "T":
                x, y, px = float(p[i]), float(p[i + 1]), int(float(p[i + 2]))
                txt = unescape(p[i + 3]) if len(p) > i + 3 else ""
                if not txt:
                    continue
                f = font(px)
                bb = f.getbbox(txt)
                tile = Image.new("RGBA", (max(1, bb[2] + 4), max(1, bb[3] + 6)), (0, 0, 0, 0))
                ImageDraw.Draw(tile).text((1, 1), txt, font=f, fill=c)
                composite(base, tile, int(x), int(y), sc)
            elif k == "I":
                x, y, w, h = (float(v) for v in p[i:i + 4])
                if w <= 0 or h <= 0 or w > MAX_TILE or h > MAX_TILE:
                    continue
                # sprites are not available offline: draw the footprint the atlas would fill,
                # tinted by the colour the draw was issued under so alpha bugs still show
                a = c[3]
                tile = Image.new("RGBA", (int(w), int(h)), (70, 66, 88, a))
                d = ImageDraw.Draw(tile)
                d.rectangle((0, 0, int(w) - 1, int(h) - 1), outline=(c[0], c[1], c[2], a))
                d.line((0, 0, int(w) - 1, int(h) - 1), fill=(c[0], c[1], c[2], a // 2))
                d.line((0, int(h) - 1, int(w) - 1, 0), fill=(c[0], c[1], c[2], a // 2))
                composite(base, tile, int(x), int(y), sc)
        except (ValueError, IndexError):
            continue
    return base.convert("RGB")


def main(argv):
    if len(argv) < 3:
        sys.stderr.write(__doc__)
        return 2
    ops_path, prefix = argv[1], argv[2]
    crop, cols, zoom = None, 4, 1
    i = 3
    while i < len(argv):
        a = argv[i]
        if a == "--crop":
            crop = tuple(int(v) for v in argv[i + 1].split(",")); i += 2
        elif a == "--cols":
            cols = max(1, int(argv[i + 1])); i += 2
        elif a == "--zoom":
            zoom = max(1, int(argv[i + 1])); i += 2
        else:
            sys.stderr.write("raster_png: unknown option %s\n" % a); return 2

    frames, size = parse(ops_path)
    if not frames:
        sys.stderr.write("raster_png: no frames in %s\n" % ops_path)
        return 1

    by_persona = {}
    for fr in frames:
        by_persona.setdefault(fr["persona"], []).append(fr)

    lbl = font(11)
    written = []
    for persona, frs in sorted(by_persona.items()):
        tiles = []
        for fr in frs:
            im = render(fr, size)
            if crop:
                x, y, w, h = crop
                im = im.crop((x, y, min(x + w, im.width), min(y + h, im.height)))
            if zoom > 1:
                im = im.resize((im.width * zoom, im.height * zoom), Image.NEAREST)
            tiles.append((fr, im))
        cw, ch = tiles[0][1].size
        n_cols = min(cols, len(tiles))
        n_rows = math.ceil(len(tiles) / n_cols)
        band = 16
        sheet = Image.new("RGB", (n_cols * cw, n_rows * (ch + band)), (30, 28, 34))
        d = ImageDraw.Draw(sheet)
        for idx, (fr, im) in enumerate(tiles):
            cx, cy = (idx % n_cols) * cw, (idx // n_cols) * (ch + band)
            sheet.paste(im, (cx, cy + band))
            tag = "%s  t=%.2f  ops=%d%s" % (fr["scene"], fr["t"], len(fr["ops"]),
                                            "  ERR" if fr["errs"] else "")
            d.text((cx + 4, cy + 2), tag,
                   fill=(255, 120, 120) if fr["errs"] else (230, 230, 230), font=lbl)
        out = "%s_%s.png" % (prefix, persona)
        sheet.save(out)
        written.append((out, len(tiles)))

    for out, n in written:
        print("raster_png: %s (%d frames)" % (out, n))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
