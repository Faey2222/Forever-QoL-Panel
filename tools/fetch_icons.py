"""Downloads interface icons by name as 40x40 PNGs: python tools/fetch_icons.py <name> [...]
(saved to tools/.cache/icons)."""
import json, sys, time, urllib.request, pathlib
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import atlas_preview as ap
out = pathlib.Path(__file__).resolve().parent / ".cache" / "icons"; out.mkdir(parents=True, exist_ok=True)
names = sys.argv[1:]
for n in names:
    q = urllib.request.Request(f"https://wago.tools/api/files?search={n.lower()}", headers=ap.UA)
    res = json.loads(urllib.request.urlopen(q, timeout=90).read()) or {}
    fid = next((k for k, v in res.items() if v.lower() == f"interface/icons/{n}.blp"), None)
    if not fid: print("missing", n); continue
    n = n.lower()
    try:
        im = ap.texture(fid)
    except Exception as e:
        print("fail", n, e); continue
    w = im.width; t = int(w * 0.07)
    im.crop((t, t, w - t, w - t)).resize((40, 40)).save(out / f"{n}.png"); print("ok", n, fid)
    time.sleep(0.2)
