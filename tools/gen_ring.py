"""Rings for the XP bar around the minimap: python tools/gen_ring.py
The panel's XP bar turned into a circle: its cross-section (sampled from the bar in the game, top edge = outside of
the ring) revolved around the centre, so the ring has the same border, shading and colours.
ring-<k>-<layer>.tga, k = the band's width in % of the outer radius:
  frame-bronze / frame-silver: the dark empty bar with both borders (the background and rim in one)
  fill, rested, gold, log: the fills, in their colours (the swipe textures of the frozen cooldowns)"""
import pathlib
import numpy as np
from PIL import Image

MEDIA = pathlib.Path(__file__).resolve().parent.parent / "ForeverQoLPanel" / "media"
N, SS = 256, 4
R = N / 2 - 1
PX = 1.6        # texture pixels per UI unit at the usual minimap size

# cross-sections, outside to inside, sampled from the bar in the game
RIM_OUT = [(6, 4, 3), (115, 82, 47), (150, 116, 77), (62, 40, 10)]
RIM_IN = [(47, 34, 21), (125, 92, 55), (37, 24, 8)]
FILL = [(37, 53, 122), (55, 79, 180), (58, 86, 203), (29, 58, 181), (4, 31, 158), (4, 31, 158), (4, 31, 158),
        (4, 31, 158), (5, 27, 134)]
GOLD = [(44, 35, 10), (60, 47, 14), (63, 50, 16), (57, 45, 14), (50, 40, 13), (44, 35, 12), (37, 29, 11), (30, 24, 9),
        (21, 17, 8)]
EMPTY = [(2, 3, 3), (3, 4, 5), (3, 4, 5), (3, 4, 5), (4, 6, 7), (5, 6, 7)]
RESTED = [tuple(int(c * 0.42 + 4) for c in rgb) for rgb in FILL]
LOG = [tuple(int(c * 0.35 + base) for c, base in zip(rgb, (34, 42, 56))) for rgb in FILL]


def silver(rows):
    out = []
    for r, g, b in rows:
        v = 0.3 * r + 0.59 * g + 0.11 * b
        out.append((min(255, v * 1.1), min(255, v * 1.1), min(255, v * 1.2)))
    return out


def profile(rows, t):
    """colour at t (0 = first row, 1 = last), linearly between the samples"""
    rows = np.array(rows, float)
    pos = t * (len(rows) - 1)
    i = np.clip(np.floor(pos).astype(int), 0, len(rows) - 2)
    f = (pos - i)[..., None]
    return rows[i] * (1 - f) + rows[i + 1] * f


def build(k, zones):
    """zones: list of (from_radius, to_radius, rows) outside to inside; returns an RGBA image"""
    y, x = (np.mgrid[0:N * SS, 0:N * SS] + 0.5) / SS
    d = np.hypot(x - N / 2, y - N / 2)
    rgb = np.zeros(d.shape + (3,))
    a = np.zeros(d.shape)
    for r0, r1, rows in zones:
        m = (d <= r0) & (d > r1)
        t = np.clip((r0 - d) / max(1e-6, r0 - r1), 0, 1)
        rgb[m] = profile(rows, t[m])
        a[m] = 1
    rgb = rgb.reshape(N, SS, N, SS, 3).mean(axis=(1, 3))
    a = a.reshape(N, SS, N, SS).mean(axis=(1, 3))
    rgb = np.where(a[..., None] > 0, rgb / np.maximum(a[..., None], 1e-6), 0)
    img = np.zeros((N, N, 4), np.uint8)
    img[..., :3] = np.clip(rgb, 0, 255).round().astype(np.uint8)
    img[..., 3] = (np.clip(a, 0, 1) * 255).round().astype(np.uint8)
    return Image.fromarray(img, "RGBA")


def stripes(k, r0, r1):
    """white stripes across the zone, slanted like the bar's (every ~6 units along the ring)"""
    y, x = (np.mgrid[0:N * SS, 0:N * SS] + 0.5) / SS
    d = np.hypot(x - N / 2, y - N / 2)
    ang = np.arctan2(x - N / 2, -(y - N / 2))
    along = ang * (r0 + r1) / 2 + (r0 - d) * 0.9      # slant: the stripe moves along as it goes inwards
    period = 6 * PX
    on = ((along % period) < period * 0.45) & (d <= r0) & (d > r1)
    a = on.astype(float).reshape(N, SS, N, SS).mean(axis=(1, 3))
    img = np.zeros((N, N, 4), np.uint8)
    img[..., :3] = 255
    img[..., 3] = (a * 255).round().astype(np.uint8)
    return Image.fromarray(img, "RGBA")


for old in MEDIA.glob("ring-*.tga"):
    old.unlink()
for k in (8, 11, 15, 19):          # 8: only the reputation ring's "thin" (frame and shade below)
    inner = R * (1 - k / 100)
    ro, ri = 2.3 * PX, 2.0 * PX         # border widths as on the bar
    a, b = R - ro, inner + ri            # the fill zone
    for metal, rows_out, rows_in in (("bronze", RIM_OUT, RIM_IN), ("silver", silver(RIM_OUT), silver(RIM_IN))):
        build(k, [(R, a, rows_out), (a, b, EMPTY), (b, inner, rows_in)]).save(MEDIA / f"ring-{k}-frame-{metal}.tga")
    if k == 8:
        lum = [0.3 * r + 0.59 * g + 0.11 * b_ for r, g, b_ in FILL]
        top = max(lum)
        build(k, [(a, b, [(v, v, v) for v in (255 * (0.55 + 0.45 * l / top) for l in lum)])]).save(MEDIA / f"ring-{k}-shade.tga")
        continue
    for name, rows in (("fill", FILL), ("rested", RESTED), ("gold", GOLD), ("log", LOG)):
        build(k, [(a, b, rows)]).save(MEDIA / f"ring-{k}-{name}.tga")
    # white shapes for the other looks of finished quests, tinted in the game: the whole zone (glow, shimmer), a line
    # along its inner edge (line), its two edges (frame), stripes across (stripes)
    # the fill's shading in grey, tinted with the standing's colour for the reputation ring
    lum = [0.3 * r + 0.59 * g + 0.11 * b_ for r, g, b_ in FILL]
    top = max(lum)
    SHADE = [(v, v, v) for v in (255 * (0.55 + 0.45 * l / top) for l in lum)]
    build(k, [(a, b, SHADE)]).save(MEDIA / f"ring-{k}-shade.tga")
    W = [(255, 255, 255)]
    lw = 1.6 * PX
    build(k, [(a, b, W)]).save(MEDIA / f"ring-{k}-q-solid.tga")
    build(k, [(b + lw, b, W)]).save(MEDIA / f"ring-{k}-q-line.tga")
    build(k, [(a, a - lw * 0.7, W), (b + lw * 0.7, b, W)]).save(MEDIA / f"ring-{k}-q-frame.tga")
    stripes(k, a, b).save(MEDIA / f"ring-{k}-q-stripes.tga")
print("ok")
