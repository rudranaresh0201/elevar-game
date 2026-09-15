"""Draw the Elevar Play icon and write every size the builds need.

    python tools/make_icons.py        (needs Pillow)

One drawing, three crops:
  * full      — iPhone home screen, browser tab, legacy Android launchers.
                iOS rounds the corners itself, so this is a plain square.
  * maskable  — Android Chrome "install app"; art inside the 80% safe circle.
  * adaptive  — Android 8+ launchers, foreground and background as separate
                layers so the launcher can crop to its own shape.

The look is the ping pong court: the red/blue split from the backdrop, the net
line, the yellow ball. Fonts come from packages/design_system.
"""

import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP = os.path.join(ROOT, "app")
FONT = os.path.join(ROOT, "packages", "design_system", "assets", "fonts", "Baloo2-ExtraBold.ttf")

N = 1024
RED, BLUE, YELLOW, INK, WHITE = "#FF1024", "#3F5BFF", "#FFF200", "#000000", "#FFFFFF"


def background(n):
    im = Image.new("RGBA", (n, n), RED)
    d = ImageDraw.Draw(im)
    d.polygon([(0, 0), (n, 0), (n, n * 0.62), (0, n * 0.38)], fill=BLUE)
    k = n / 1024
    # The net: white, edged in ink like everything else in the app.
    for half, colour in ((26, INK), (13, WHITE)):
        d.polygon(
            [(0, n * 0.38 - half * k), (n, n * 0.62 - half * k), (n, n * 0.62 + half * k), (0, n * 0.38 + half * k)],
            fill=colour,
        )
    return im


def foreground(n, scale):
    """Ball, trail and word, drawn inside `scale` of the canvas."""
    im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    c = n / 2
    u = n * scale / 1024

    bx, by, br = c + 150 * u, c - 90 * u, 165 * u
    # Trail up and to the left: the ball is coming down along the net.
    for dx, dy, rr, alpha in ((-270, -95, 72, 170), (-420, -150, 50, 120), (-535, -192, 32, 80)):
        x, y, r = bx + dx * u, by + dy * u, rr * u
        d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255, alpha))
    edge = 18 * u
    d.ellipse([bx - br - edge, by - br - edge, bx + br + edge, by + br + edge], fill=INK)
    d.ellipse([bx - br, by - br, bx + br, by + br], fill=YELLOW)
    d.ellipse([bx - br * 0.55, by - br * 0.62, bx - br * 0.05, by - br * 0.25], fill=(255, 255, 255, 190))

    font = ImageFont.truetype(FONT, int(300 * u))
    word = "PLAY"
    w = d.textlength(word, font=font)
    ty = c + 40 * u
    d.text((c - w / 2, ty + 14 * u), word, font=font, fill=INK, stroke_width=int(26 * u), stroke_fill=INK)
    d.text((c - w / 2, ty), word, font=font, fill=WHITE, stroke_width=int(22 * u), stroke_fill=INK)
    return im


def compose(scale):
    im = background(N)
    im.alpha_composite(foreground(N, scale))
    return im.convert("RGB")


def save(im, size, *path):
    target = os.path.join(*path)
    os.makedirs(os.path.dirname(target), exist_ok=True)
    im.resize((size, size), Image.LANCZOS).save(target, optimize=True)


def main():
    full, maskable = compose(1.0), compose(0.72)
    fg, bg = foreground(N, 0.62), background(N).convert("RGB")

    web = os.path.join(APP, "web")
    save(full, 64, web, "favicon.png")
    save(full, 180, web, "icons", "Icon-180.png")
    save(full, 192, web, "icons", "Icon-192.png")
    save(full, 512, web, "icons", "Icon-512.png")
    save(maskable, 192, web, "icons", "Icon-maskable-192.png")
    save(maskable, 512, web, "icons", "Icon-maskable-512.png")

    res = os.path.join(APP, "android", "app", "src", "main", "res")
    for density, legacy, adaptive in (("mdpi", 48, 108), ("hdpi", 72, 162), ("xhdpi", 96, 216),
                                      ("xxhdpi", 144, 324), ("xxxhdpi", 192, 432)):
        folder = "mipmap-" + density
        save(full, legacy, res, folder, "ic_launcher.png")
        save(fg, adaptive, res, folder, "ic_launcher_foreground.png")
        save(bg, adaptive, res, folder, "ic_launcher_background.png")
    # mipmap-anydpi-v26/ic_launcher.xml points at the two layers; it is
    # checked in and does not change.

    save(full, 192, ROOT, "site", "icon.png")
    print("icons written")


if __name__ == "__main__":
    main()
