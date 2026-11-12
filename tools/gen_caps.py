"""Cap textures for the panel, made by bending the client's bronze frame edge
(ui-frame-metal-edgebottom-c60-2x) along the outline. Everything at 2x; the page shows it at half size.
Run tools/atlas_export.py for the c60 frame atlases first.
Geometry must match G in docs/mockup/infopanel.src.html (1x: F 76, tip 11, content 26, bar 15)."""
import numpy as np, pathlib
from PIL import Image

HERE = pathlib.Path(__file__).resolve().parent / ".cache"  # client textures in, caps out (tools/.cache/png)
edge = np.asarray(Image.open(HERE / "png" / "ui-frame-metal-edgebottom-c60-2x.png").convert("RGBA")).astype(float)
STRIP = edge[166:198, 6:250]  # 32 rows; row 12 sits on the line, row 0 faces the inside
SH, SW, C = STRIP.shape[0], STRIP.shape[1], 12
A = np.array


def bez(p0, p1, p2, p3, n=3000):
    t = np.linspace(0, 1, n)[:, None]
    return (1 - t) ** 3 * p0 + 3 * (1 - t) ** 2 * t * p1 + 3 * (1 - t) * t ** 2 * p2 + t ** 3 * p3


def quad(p0, p1, p2, n=1200):
    t = np.linspace(0, 1, n)[:, None]
    return (1 - t) ** 2 * p0 + 2 * (1 - t) * t * p1 + t ** 2 * p2


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


def render(w, h, strokes, name):
    k = 2
    cv = np.zeros((h * k, w * k, 4))
    # each stroke on its own layer, then layered with normal "over" blending, like the browser/client stacks
    # the straight strips, so the caps match them at the seam
    for p in strokes:
        lay = np.zeros_like(cv)
        if isinstance(p, tuple): stroke(lay, p[0], k, p[1], p[2])
        else: stroke(lay, p, k)
        sa = lay[..., 3:4] / 255; da = cv[..., 3:4] / 255; oa = sa + da * (1 - sa)
        rgb = (lay[..., :3] * sa + cv[..., :3] * da * (1 - sa)) / np.maximum(oa, 1e-6)
        cv = np.concatenate([rgb, oa * 255], axis=2)
    rgb = cv[..., :3]; a = cv[..., 3:4]
    img = Image.fromarray(np.concatenate([rgb, a], axis=2).clip(0, 255).astype(np.uint8)).resize((w, h), Image.LANCZOS)
    img.save(HERE / "png" / f"{name}.png")


F, T, BH, BAR = 152, 22, 52, 30
# bar in the frame: the S-curve runs into the tip, its line becomes the bar's top edge
top = BH + 12; yc = top + BAR / 2; yb = top + BAR
sc = bez(A([0, 0]), A([F / 2, 0]), A([F / 2, yc]), A([F, yc]))
end = F + T + 40
render(end, 116, [
    np.vstack([quad(A([F, yc]), A([F + T * .25, yb]), A([F + T, yb])), line(A([F + T, yb]), A([end + 4, yb]))]),
    np.vstack([sc, quad(A([F, yc]), A([F + T * .25, top]), A([F + T, top])), line(A([F + T, top]), A([end + 4, top]))]),
], "cap-edge")
# bar below: the S-curve ends in a straight bottom line
yp = BH + 10
# The S-curve starts Y0 above the screen edge (y = EXT here is the screen edge), so the visible part already slopes
# down where it leaves the screen and the cut end with its shadow stays off screen. D is spare room on the left.
EXT, D, Y0 = 28, 32, 14
sp = bez(A([D, EXT - Y0]), A([D + F / 2, EXT - Y0]), A([D + F / 2, EXT + yp]), A([D + F, EXT + yp]))
render(D + F + 40, yp + EXT + 22, [np.vstack([sp, line(A([D + F, EXT + yp]), A([D + F + 44, EXT + yp]))])], "cap-panel")
# the bar's own tip (bar below)
ty, tb, tx0 = 20, 20 + BAR, 6
tc = (ty + tb) / 2; tend = tx0 + T + 40
render(tend, tb + 22, [
    np.vstack([quad(A([tx0, tc]), A([tx0 + T * .25, tb]), A([tx0 + T, tb])), line(A([tx0 + T, tb]), A([tend + 4, tb]))]),
    np.vstack([quad(A([tx0, tc]), A([tx0 + T * .25, ty]), A([tx0 + T, ty])), line(A([tx0 + T, ty]), A([tend + 4, ty]))]),
], "cap-tip")
# rounded end of the XP bar (thin edge): along the top to the left, half circle down, along the bottom.
# At the top point the half circle is tangent to the panel's bottom line, so the bar hangs from it.
R = BAR / 2; ux, uy = 26, 16; uend = ux + 40
half = np.array([[ux - R * np.sin(a), uy + R - R * np.cos(a)] for a in np.linspace(0, np.pi, 900)])
render(uend, int(uy + BAR + 16), [(np.vstack([line(A([uend + 4, uy]), A([ux, uy]), 300), half,
                                             line(A([ux, uy + BAR]), A([uend + 4, uy + BAR]), 300)]), THIN, CT)], "cap-u")
# same end without the top part: in the panel the bar hangs from the panel's line, which is its top border
render(uend, int(uy + BAR + 16), [(np.vstack([half, line(A([ux, uy + BAR]), A([uend + 4, uy + BAR]), 300)]), THIN, CT)], "cap-u-open")
# straight pieces through the same routine as the caps, so both sides of every seam match exactly
render(SW, SH, [line(A([0, C]), A([SW, C]), 2000)], "edge-strip")
render(SW, 22, [(line(A([0, CT]), A([SW, CT]), 2000), THIN, CT)], "edge-strip-thin")
print("caps ok")
