"""Exports client atlas members as PNGs plus a native-size contact sheet.

    python tools/atlas_export.py <regex> [outdir] [sheetname]

Default outdir is tools/.cache (PNGs land in tools/.cache/png).
"""
import pathlib, re, sys
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import atlas_preview as ap
from PIL import Image, ImageDraw
pat = re.compile(sys.argv[1], re.I)
out = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else pathlib.Path(__file__).resolve().parent / ".cache"
name = sys.argv[3] if len(sys.argv) > 3 else "sheet"
(out / "png").mkdir(parents=True, exist_ok=True)
atl = {r["ID"]: r for r in ap.table("UiTextureAtlas")}
mem = [r for r in ap.table("UiTextureAtlasMember") if pat.search(r["CommittedName"])]
imgs = []
for m in mem:
    a = atl.get(m["UiTextureAtlasID"])
    try:
        t = ap.texture(a["FileDataID"])
        sx, sy = t.width / int(a["AtlasWidth"]), t.height / int(a["AtlasHeight"])
        im = t.crop((int(int(m["CommittedLeft"])*sx), int(int(m["CommittedTop"])*sy), int(int(m["CommittedRight"])*sx), int(int(m["CommittedBottom"])*sy)))
    except Exception as e:
        print("skip", m["CommittedName"], e); continue
    im.save(out / "png" / (m["CommittedName"].strip("!_") + ".png"))
    imgs.append((m["CommittedName"], im, m["Width"], m["Height"]))
W = 1400; x = y = 8; rowh = 0; places = []
for n, im, w, h in imgs:
    d = im.copy(); d.thumbnail((640, 200))
    cw = max(d.width, 210)
    if x + cw > W: x = 8; y += rowh + 24; rowh = 0
    places.append((n, d, x, y, im.size, w, h)); x += cw + 12; rowh = max(rowh, d.height)
sheet = Image.new("RGBA", (W, y + rowh + 30), (34, 30, 28, 255)); dr = ImageDraw.Draw(sheet)
for n, d, x, y, sz, w, h in places:
    sheet.alpha_composite(d, (x, y)); dr.text((x, y + d.height + 2), f"{n[:40]} {sz[0]}x{sz[1]} ({w}x{h})", fill=(230, 220, 190))
sheet.save(out / f"{name}.png"); print("ok", len(imgs))
