# Regenerates every launcher icon from the Bands mark (#572): three spectrum
# bands in the phase tints stepping across a Spectrum Deep Purple tile.
# Pure Pillow, no Flutter tooling: each existing icon file is redrawn in place
# at its own pixel size, so running it again after editing the geometry below
# refreshes every platform. Usage: python3 tool/generate_icons.py
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
BG = "#3C0060"
# (x, y, fill) on a 512 canvas; bands are 232x76 with a 10px corner radius.
BANDS = [
    ((188, 112), "#FFFFFF"),
    ((140, 218), "#CFBCFF"),
    ((92, 324), "#9D8AB0"),
]
W, H, R = 232, 76, 10
SS = 4  # supersample factor so small sizes keep crisp edges


def draw_mark(size, background, scale=1.0, mono=None):
    c = size * SS
    img = Image.new("RGBA", (c, c), background)
    d = ImageDraw.Draw(img)
    f = c / 512 * scale
    off = (c - 512 * f) / 2
    for (x, y), color in BANDS:
        d.rounded_rectangle(
            [off + x * f, off + y * f, off + (x + W) * f, off + (y + H) * f],
            radius=R * f,
            fill=mono or color,
        )
    return img.resize((size, size), Image.LANCZOS)


def tile(size):
    # Full-bleed launcher tile; platforms apply their own corner mask.
    return draw_mark(size, BG).convert("RGB")


def maskable(size):
    # PWA maskable: keep the art inside the center 80% safe circle.
    return draw_mark(size, BG, scale=0.82).convert("RGB")


def foreground(size):
    # Adaptive layer; mipmap-anydpi-v26/ic_launcher.xml insets a further 16%.
    return draw_mark(size, (0, 0, 0, 0))


def monochrome(size):
    return draw_mark(size, (0, 0, 0, 0), mono="#FFFFFF")


def redraw(path, maker):
    size = Image.open(path).size[0]
    maker(size).save(path)
    print(f"{path.relative_to(ROOT)} ({size})")


def main():
    for p in sorted(ROOT.glob("android/app/src/main/res/mipmap-*/ic_launcher.png")):
        redraw(p, tile)
    for p in sorted(ROOT.glob("android/app/src/main/res/drawable-*/ic_launcher_foreground.png")):
        redraw(p, foreground)
    for p in sorted(ROOT.glob("android/app/src/main/res/drawable-*/ic_launcher_monochrome.png")):
        redraw(p, monochrome)
    for p in sorted(ROOT.glob("ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png")):
        redraw(p, tile)  # iOS forbids alpha; tile() is RGB
    for p in sorted(ROOT.glob("macos/Runner/Assets.xcassets/AppIcon.appiconset/*.png")):
        redraw(p, tile)
    redraw(ROOT / "web/favicon.png", tile)
    redraw(ROOT / "web/icons/Icon-192.png", tile)
    redraw(ROOT / "web/icons/Icon-512.png", tile)
    redraw(ROOT / "web/icons/Icon-maskable-192.png", maskable)
    redraw(ROOT / "web/icons/Icon-maskable-512.png", maskable)
    redraw(ROOT / "assets/icon/icon.png", tile)
    redraw(ROOT / "assets/icon/icon_foreground.png", foreground)
    tile(256).save(
        ROOT / "windows/runner/resources/app_icon.ico",
        sizes=[(16, 16), (32, 32), (48, 48), (256, 256)],
    )
    print("windows/runner/resources/app_icon.ico (16/32/48/256)")


if __name__ == "__main__":
    main()
