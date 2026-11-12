"""Inlines client textures, icons and the font into infopanel.src.html -> infopanel.html (not committed:
it contains Blizzard art). Needs tools/atlas_export.py, tools/fetch_icons.py and tools/gen_caps.py first."""
import base64, io, json, pathlib
from PIL import Image

HERE = pathlib.Path(__file__).resolve().parent
CACHE = HERE.parent.parent / "tools" / ".cache"  # client data stays out of git
PNG, ICONS, FONT = CACHE / "png", CACHE / "icons", CACHE / "frizqt.ttf"


def b64(img):
    buf = io.BytesIO(); img.save(buf, "PNG", optimize=True)
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode()


def load(name):
    return Image.open(PNG / f"{name}.png").convert("RGBA")


def nine(prefix):
    """Assemble a 30x30 nine-slice sheet (7px corners) from separate client pieces."""
    p = lambda s: load(f"{prefix}-{s}-c60")
    out = Image.new("RGBA", (30, 30))
    out.paste(p("center").resize((16, 16)), (7, 7))
    out.paste(p("edgetop").resize((16, 7)), (7, 0)); out.paste(p("edgebottom").resize((16, 7)), (7, 23))
    out.paste(p("edgeleft").resize((7, 16)), (0, 7)); out.paste(p("edgeright").resize((7, 16)), (23, 7))
    out.paste(p("cornertopleft"), (0, 0)); out.paste(p("cornertopright"), (23, 0))
    out.paste(p("cornerbottomleft"), (0, 23)); out.paste(p("cornerbottomright"), (23, 23))
    return out


A = {
    "frame": load("ui-hud-actionbar-frame-c60-2x"),
    "heavy": load("heavybronze-frame-basic-c60-2x"),
    "brBL": load("heavybronze-horz-cornerbracket-bl-c60-2x"), "brBR": load("heavybronze-horz-cornerbracket-br-c60-2x"),
    "brTL": load("heavybronze-horz-cornerbracket-tl-c60-2x"), "brTR": load("heavybronze-horz-cornerbracket-tr-c60-2x"),
    "divTop": load("ui-hud-actionbar-frame-divider-threeslice-edgetop-c60-2x"),
    "divMid": load("ui-hud-actionbar-frame-divider-threeslice-center-c60-2x"),
    "divBot": load("ui-hud-actionbar-frame-divider-threeslice-edgebottom-c60-2x"),
    "xpBg": load("ui-hud-experiencebar-background-c60"), "xpFill": load("ui-hud-experiencebar-fill-experience-c60"),
    "xpRested": load("ui-hud-experiencebar-fill-rested-c60"), "xpPred": load("ui-hud-experiencebar-fill-prediction-c60"),
    "xpGold": load("ui-hud-experiencebar-fill-artifactpower-c60"), "xpFrame": load("ui-hud-experiencebar-frame-c60"),
    "pip": load("ui-hud-experiencebar-frame-pip-c60"), "pipHi": load("ui-hud-experiencebar-frame-pip-mouseover-c60"),
    "tip9": nine("tooltip-nineslice"),
    "bgTex": load("heavybronze-frame-background-c60").resize((384, 384), Image.LANCZOS),
    "slot": load("ui-hud-actionbar-iconframe-c60"),
    "gryL": load("ui-hud-actionbar-gryphon-left-c60"), "gryR": load("ui-hud-actionbar-gryphon-right-c60"),
    "mmFrame": load("ui-hud-minimap-frame-c60"),
    "capPanel": load("cap-panel"), "edgeStrip": load("edge"),
    "capU": load("cap-bar"), "capUOpen": load("cap-bar-open"), "edgeThin": load("edge-bar-strip"),
}
for f in ICONS.glob("*.png"):
    A["i_" + f.stem] = Image.open(f).convert("RGBA")

data = {k: b64(v) for k, v in A.items()}
data["font"] = "data:font/ttf;base64," + base64.b64encode(FONT.read_bytes()).decode()
src = (HERE / "infopanel.src.html").read_text(encoding="utf-8")
out = src.replace("/*__ASSETS__*/{}", json.dumps(data))
(HERE / "infopanel.html").write_text(out, encoding="utf-8")
print("built", len(out) // 1024, "KB")
