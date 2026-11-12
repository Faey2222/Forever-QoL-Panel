"""Border textures for the panel, made by bending the client's bronze frame edge
(ui-frame-metal-edgebottom-c60-2x) along the panel outline.

    python tools/gen_caps.py

Needs tools/.cache/png/ui-frame-metal-edgebottom-c60-2x.png (tools/atlas_export.py "ui-frame-metal-edge").
Writes PNGs to tools/.cache/png (for the mockup) and TGAs to ForeverQoLPanel/media (shipped with the addon):
power-of-two canvases, content in the top left corner, 2x pixel density (1 UI unit = 2 texels).
Geometry must match Dock.lua (G) and G in docs/mockup/infopanel.src.html: 1x F 76, content 26, bar 15.
"""
import numpy as np, pathlib
from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parent.parent
CACHE = ROOT / "tools" / ".cache" / "png"
MEDIA = ROOT / "ForeverQoLPanel" / "media"
edge = np.asarray(Image.open(CACHE / "ui-frame-metal-edgebottom-c60-2x.png").convert("RGBA")).astype(float)
STRIP = edge[166:198]  # 32 rows, full 256 columns (tiles seamlessly); row 12 sits on the line, row 0 faces inside
SH, SW, C = STRIP.shape[0], STRIP.shape[1], 12
A = np.array


def bez(p0, p1, p2, p3, n=3000):
    t = np.linspace(0, 1, n)[:, None]
    return (1 - t) ** 3 * p0 + 3 * (1 - t) ** 2 * t * p1 + 3 * (1 - t) * t ** 2 * p2 + t ** 3 * p3


def line(a, b, n=600):
    t = np.linspace(0, 1, n)[:, None]
    return a + (b - a) * t


# thinner version of the same edge for the XP bar's own border (22 instead of 32 rows)
THIN = np.asarray(Image.fromarray(STRIP.clip(0, 255).astype(np.uint8)).resize((SW, 22), Image.LANCZOS)).astype(float)
CT = C * 22 / 32


def stroke(cv, pts, k=2, strip=None, c=None):
    strip = STRIP if strip is None else strip; c = C if c is None else c
    d = np.diff(pts, axis=0); s = np.concatenate([[0], np.cumsum(np.hypot(d[:, 0], d[:, 1]))])
    ss = np.arange(0, s[-1], 0.25); x = np.interp(ss, s, pts[:, 0]); y = np.interp(ss, s, pts[:, 1])
    tx, ty = np.gradient(x), np.gradient(y); L = np.hypot(tx, ty); tx /= L; ty /= L
    nx, ny = ty, -tx
    H, W = cv.shape[:2]
    for j in np.arange(0, strip.shape[0], 0.5):
        col = strip[int(j)][ss.astype(int) % SW]
        px = ((x + nx * (c - j)) * k).astype(int); py = ((y + ny * (c - j)) * k).astype(int)
        ok = (px >= 0) & (px < W) & (py >= 0) & (py < H)
        px, py, col = px[ok], py[ok], col[ok]
        a = col[:, 3:4] / 255
        cv[py, px, :3] = cv[py, px, :3] * (1 - a) + col[:, :3] * a
        cv[py, px, 3] = np.maximum(cv[py, px, 3], col[:, 3])


def render(w, h, strokes):
    """Strokes at 4x, each on its own layer, layered with normal "over" blending (like the client stacks the
    straight pieces), then scaled to w x h (2x density)."""
    k = 2
    cv = np.zeros((h * k, w * k, 4))
    for p in strokes:
        lay = np.zeros_like(cv)
        if isinstance(p, tuple): stroke(lay, p[0], k, p[1], p[2])
        else: stroke(lay, p, k)
        sa = lay[..., 3:4] / 255; da = cv[..., 3:4] / 255; oa = sa + da * (1 - sa)
        rgb = (lay[..., :3] * sa + cv[..., :3] * da * (1 - sa)) / np.maximum(oa, 1e-6)
        cv = np.concatenate([rgb, oa * 255], axis=2)
    return Image.fromarray(cv.clip(0, 255).astype(np.uint8)).resize((w, h), Image.LANCZOS)


def silver(img):
    a = np.asarray(img).astype(float)
    lum = (a[..., 0] * .3 + a[..., 1] * .59 + a[..., 2] * .11) * 1.5
    out = np.stack([lum, lum, lum, a[..., 3]], axis=2).clip(0, 255).astype(np.uint8)
    return Image.fromarray(out)


def pot(n):
    p = 1
    while p < n: p *= 2
    return p


def export(name, img, colored=True):
    img.save(CACHE / f"{name}.png")
    canvas = Image.new("RGBA", (pot(img.width), pot(img.height)), (0, 0, 0, 0))
    for suffix, im in [("", img)] + ([("-silver", silver(img))] if colored else []):
        c = canvas.copy(); c.paste(im, (0, 0)); c.save(MEDIA / f"{name}{suffix}.tga")
    print(f"{name}: {img.width}x{img.height} in {canvas.width}x{canvas.height}")


MEDIA.mkdir(parents=True, exist_ok=True)
F, BH, BAR = 152, 52, 30
yp = BH + 10
# The panel's S-curve starts Y0 above the screen edge (y = EXT is the screen edge), so the visible part already
# slopes down where it leaves the screen and the cut end with its shadow stays off screen. D is spare room left.
EXT, D, Y0 = 28, 32, 14
CW, CH = D + F + 40, yp + EXT + 30
sp = bez(A([D, EXT - Y0]), A([D + F / 2, EXT - Y0]), A([D + F / 2, EXT + yp]), A([D + F, EXT + yp]))

# the panel's background inside the curve: white, tinted in the addon (the straight middle is a colour texture)
k = 4
fill = Image.new("L", (CW * k, CH * k), 0)
poly = [(0, 0), (0, (EXT - Y0) * k)] + [(x * k, y * k) for x, y in sp] + [(CW * k, (EXT + yp) * k), (CW * k, 0)]
ImageDraw.Draw(fill).polygon(poly, fill=255)
fill = fill.resize((CW, CH), Image.LANCZOS)
export("cap-panel-fill", Image.merge("RGBA", (Image.new("L", fill.size, 255),) * 3 + (fill,)), colored=False)

# rounded end of the XP bar (thin edge): along the top to the left, half circle down, along the bottom.
# At the top point the half circle is tangent to the panel's bottom line, so the bar hangs from it.
R = BAR / 2; ux, uy = 26, 16; uend = ux + 40; UH = int(uy + BAR + 18)
half = np.array([[ux - R * np.sin(a), uy + R - R * np.cos(a)] for a in np.linspace(0, np.pi, 900)])

# Every border in three widths (the addon's "border" setting): the client strip squeezed or stretched across the
# line. Scales 2/3 and 4/3 keep the line row on whole UI units (C = 12 rows -> 8 and 16).
WIDTHS = [("", 1.0), ("-thin", 2 / 3), ("-thick", 4 / 3)]
for suffix, k_ in WIDTHS:
    rows, trows = round(SH * k_), round(22 * k_)
    strip = np.asarray(Image.fromarray(STRIP.clip(0, 255).astype(np.uint8)).resize((SW, rows), Image.LANCZOS)).astype(float)
    thin = np.asarray(Image.fromarray(STRIP.clip(0, 255).astype(np.uint8)).resize((SW, trows), Image.LANCZOS)).astype(float)
    c, ct = C * k_, CT * k_
    export("cap-panel" + suffix, render(CW, CH, [(np.vstack([sp, line(A([D + F, EXT + yp]), A([D + F + 44, EXT + yp]))]), strip, c)]))
    export("cap-bar" + suffix, render(uend, UH, [(np.vstack([line(A([uend + 4, uy]), A([ux, uy]), 300), half,
                                                         line(A([ux, uy + BAR]), A([uend + 4, uy + BAR]), 300)]), thin, ct)]))
    # same end without the top part: in the panel the bar hangs from the panel's line, which is its top border
    export("cap-bar-open" + suffix, render(uend, UH, [(np.vstack([half, line(A([ux, uy + BAR]), A([uend + 4, uy + BAR]), 300)]), thin, ct)]))
    # straight pieces through the same routine as the caps, so both sides of every seam match exactly
    export("edge" + suffix, render(SW, rows, [(line(A([0, c]), A([SW, c]), 2000), strip, c)]))
    # the XP bar's straight borders on the very canvas of its caps (same height, same line rows, same stroke
    # direction), placed at the caps' position: the seams cannot step
    export("edge-bar" + suffix, render(SW, UH, [(line(A([0, uy + BAR]), A([SW, uy + BAR]), 2000), thin, ct)]))
    export("edge-bar-top" + suffix, render(SW, UH, [(line(A([SW, uy]), A([0, uy]), 2000), thin, ct)]))
export("edge-bar-strip", render(SW, 22, [(line(A([0, CT]), A([SW, CT]), 2000), THIN, CT)]))

print("ok")
