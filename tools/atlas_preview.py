"""Contact sheet of client atlas entries matching a pattern: python tools/atlas_preview.py <regex> [out.png]

Downloads the atlas textures of WoW: Forever (via wago.tools) into tools/.cache and crops every
matching member, to pick client art for the UI without starting the game.
"""
import csv
import io
import pathlib
import re
import struct
import sys
import time
import urllib.request

from PIL import Image, ImageDraw

ROOT = pathlib.Path(__file__).resolve().parent.parent
CACHE = ROOT / "tools" / ".cache"
BUILD = "1.60.1.70245"
UA = {"User-Agent": "Mozilla/5.0"}


def table(name):
    CACHE.mkdir(exist_ok=True)
    path = CACHE / f"{name}-{BUILD}.csv"
    if not path.exists():
        url = f"https://wago.tools/db2/{name}/csv?build={BUILD}"
        path.write_bytes(urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60).read())
    return list(csv.DictReader(path.read_text(encoding="utf-8").splitlines()))


def decode_blp(data):
    """PIL reads compressed BLPs; uncompressed BGRA ones (encoding 3) are read here."""
    if data[:4] == b"BLP2" and data[8] == 3:
        width, height = struct.unpack_from("<II", data, 12)
        offset = struct.unpack_from("<I", data, 20)[0]
        raw = data[offset:offset + width * height * 4]
        return Image.frombuffer("RGBA", (width, height), raw, "raw", "BGRA", 0, 1)
    return Image.open(io.BytesIO(data)).convert("RGBA")


def texture(file_id):
    path = CACHE / "blp" / f"{file_id}.png"
    if not path.exists():
        path.parent.mkdir(parents=True, exist_ok=True)
        data = urllib.request.urlopen(urllib.request.Request(f"https://wago.tools/api/casc/{file_id}?download", headers=UA), timeout=60).read()
        decode_blp(data).save(path)
        time.sleep(0.2)
    return Image.open(path)


def main():
    pattern = re.compile(sys.argv[1], re.I)
    out = pathlib.Path(sys.argv[2]) if len(sys.argv) > 2 else CACHE / "atlas_preview.png"
    atlases = {r["ID"]: r for r in table("UiTextureAtlas")}
    members = [r for r in table("UiTextureAtlasMember") if pattern.search(r["CommittedName"])][:80]
    cell, cols = 200, 6
    rows = (len(members) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * cell, rows * (cell + 16)), (60, 60, 70, 255))
    draw = ImageDraw.Draw(sheet)
    for i, m in enumerate(members):
        atlas = atlases.get(m["UiTextureAtlasID"])
        try:
            tex = texture(atlas["FileDataID"])
            sx, sy = tex.width / int(atlas["AtlasWidth"]), tex.height / int(atlas["AtlasHeight"])
            box = (int(int(m["CommittedLeft"]) * sx), int(int(m["CommittedTop"]) * sy),
                   int(int(m["CommittedRight"]) * sx), int(int(m["CommittedBottom"]) * sy))
            img = tex.crop(box)
            img.thumbnail((cell - 8, cell - 8))
        except Exception as exc:  # noqa: BLE001 - a missing texture just leaves a gap
            print("skip", m["CommittedName"], exc)
            continue
        x, y = (i % cols) * cell, (i // cols) * (cell + 16)
        sheet.alpha_composite(img, (x + 4, y + 4))
        draw.text((x + 4, y + cell), m["CommittedName"][:32], fill=(255, 255, 255))
    sheet.save(out)
    print("wrote", out, len(members))


if __name__ == "__main__":
    main()
