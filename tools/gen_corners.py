"""Rounded corners for the modern skin: python tools/gen_corners.py
corner.tga: a quarter disc (top-left corner, the circle's centre at the texture's bottom-right), white.
corner-ring-<r>-<t>.tga: the matching border arc (t units thick) for a radius of r UI units. Tinted in the game."""
import pathlib
import numpy as np
from PIL import Image

MEDIA = pathlib.Path(__file__).resolve().parent.parent / "ForeverQoLPanel" / "media"
N, SS = 64, 4


def disc(inner):
    y, x = (np.mgrid[0:N * SS, 0:N * SS] + 0.5) / SS
    d = np.hypot(N - x, N - y)
    a = (d <= N) & (d >= inner)
    a = a.reshape(N, SS, N, SS).mean(axis=(1, 3))
    img = np.zeros((N, N, 4), np.uint8)
    img[..., :3] = 255
    img[..., 3] = (a * 255).round().astype(np.uint8)
    return Image.fromarray(img, "RGBA")


disc(0).save(MEDIA / "corner.tga")
for r in (3, 6):
    for t in (1, 2, 3):
        disc(max(0, N - N * t / r)).save(MEDIA / f"corner-ring-{r}-{t}.tga")
print("ok")
