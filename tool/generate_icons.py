from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
BG = "#3C0060"

BANDS = [
    ((188, 112), "#FFFFFF"),
    ((140, 218), "#CFBCFF"),
    ((92, 324), "#9D8AB0"),
]
W, H, R = 232, 76, 10
SS = 4

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

    return draw_mark(size, BG).convert("RGB")

def maskable(size):

    return draw_mark(size, BG, scale=0.82).convert("RGB")

def foreground(size):

    return draw_mark(size, (0, 0, 0, 0))

def monochrome(size):
    return draw_mark(size, (0, 0, 0, 0), mono="#FFFFFF")

def redraw(path, maker):
    with Image.open(path) as img:
        size = max(img.size)
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
        redraw(p, tile)
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
