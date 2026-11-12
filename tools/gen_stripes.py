"""Diagonal stripes for the XP bar's preview of finished quests: python tools/gen_stripes.py
White on transparent (tinted in the game), tiles seamlessly in both directions."""
import pathlib
import numpy as np
from PIL import Image

MEDIA = pathlib.Path(__file__).resolve().parent.parent / "ForeverQoLPanel" / "media"
N, PERIOD, ON = 32, 16, 2.6   # size, stripe period and stripe width in texels
y, x = np.mgrid[0:N * 4, 0:N * 4] / 4.0          # 4x supersampling
d = (x + y) % PERIOD
alpha = np.clip(np.minimum(d, PERIOD - d) * -1 + ON / 2 + 0.5, 0, 1)
alpha = alpha.reshape(N, 4, N, 4).mean(axis=(1, 3))
img = np.zeros((N, N, 4), np.uint8)
img[..., :3] = 255
img[..., 3] = (alpha * 255).round().astype(np.uint8)
Image.fromarray(img, "RGBA").save(MEDIA / "stripes.tga")
print("wrote", MEDIA / "stripes.tga")
