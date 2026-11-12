"""Builds the addon icon and logo from art/logo_source.png: python tools/import_logo.py"""
import pathlib
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
src = Image.open(ROOT / "art" / "logo_source.png").convert("RGBA")
w, h = src.size
# the icon is shown in round frames (portrait, minimap button) that cut off about the outer 20 %: the wide
# "FOREVER" reaches out to 92 % of the diameter, so the whole logo is shrunk to fit inside the visible circle
SIZE, FIT = 128, 0.80
icon = Image.new("RGBA", (SIZE, SIZE), (2, 4, 10, 255))
inner = src.resize((int(SIZE * FIT), int(SIZE * FIT)), Image.LANCZOS)
off = (SIZE - inner.width) // 2
icon.alpha_composite(inner, (off, off))
icon.save(ROOT / "ForeverQoLPanel" / "media" / "icon.tga")
src.resize((256, 256), Image.LANCZOS).save(ROOT / "ForeverQoLPanel" / "media" / "logo.tga")
print("icon + logo ok")
