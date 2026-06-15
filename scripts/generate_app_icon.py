#!/usr/bin/env python3
from pathlib import Path
import math
import shutil
import subprocess

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "Assets"
ICONSET = ASSETS / "AppIcon.iconset"
BASE_PNG = ASSETS / "AppIcon.png"
ICNS = ASSETS / "AppIcon.icns"


def lerp(a, b, t):
    return int(a + (b - a) * t)


def vertical_gradient(size, top, bottom):
    w, h = size
    image = Image.new("RGBA", size)
    pixels = image.load()
    for y in range(h):
        t = y / max(1, h - 1)
        color = tuple(lerp(top[i], bottom[i], t) for i in range(4))
        for x in range(w):
            pixels[x, y] = color
    return image


def radial_highlight(size, center, color, radius):
    w, h = size
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    pixels = layer.load()
    cx, cy = center
    for y in range(h):
        for x in range(w):
            d = math.hypot(x - cx, y - cy)
            if d < radius:
                t = 1.0 - d / radius
                alpha = int(color[3] * (t ** 1.8))
                pixels[x, y] = (color[0], color[1], color[2], alpha)
    return layer


def rounded_mask(size, radius):
    mask = Image.new("L", size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size[0], size[1]), radius=radius, fill=255)
    return mask


def shadow_for_mask(mask, offset, blur, alpha):
    shadow = Image.new("RGBA", mask.size, (0, 0, 0, 0))
    shadow.putalpha(mask.filter(ImageFilter.GaussianBlur(blur)).point(lambda p: int(p * alpha / 255)))
    canvas = Image.new("RGBA", mask.size, (0, 0, 0, 0))
    canvas.alpha_composite(shadow, offset)
    return canvas


def polygon_layer(size, points, fill, outline=None, width=1):
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    draw.polygon(points, fill=fill)
    if outline:
        draw.line(points + [points[0]], fill=outline, width=width, joint="curve")
    return layer


def load_font(size, bold=False):
    candidates = [
        "/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf",
        "/System/Library/Fonts/SFNS.ttf",
        "/Library/Fonts/Arial.ttf",
    ]
    for candidate in candidates:
        try:
            return ImageFont.truetype(candidate, size)
        except Exception:
            pass
    return ImageFont.load_default()


def draw_icon(size=1024):
    scale = size / 1024
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    bg_box = tuple(int(v * scale) for v in (82, 74, 942, 934))
    bg_radius = int(215 * scale)
    bg_size = (bg_box[2] - bg_box[0], bg_box[3] - bg_box[1])
    bg_mask = rounded_mask(bg_size, bg_radius)

    shadow_mask = Image.new("L", (size, size), 0)
    shadow_mask.paste(bg_mask, bg_box[:2])
    image.alpha_composite(shadow_for_mask(shadow_mask, (0, int(20 * scale)), int(38 * scale), 92))

    bg = vertical_gradient(bg_size, (78, 39, 150, 255), (29, 18, 66, 255))
    bg.alpha_composite(radial_highlight(bg_size, (int(250 * scale), int(160 * scale)), (190, 141, 255, 140), int(560 * scale)))
    bg.alpha_composite(radial_highlight(bg_size, (int(620 * scale), int(700 * scale)), (89, 187, 255, 76), int(420 * scale)))
    bg.putalpha(bg_mask)
    image.alpha_composite(bg, bg_box[:2])

    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle(bg_box, radius=bg_radius, outline=(255, 255, 255, 46), width=max(1, int(3 * scale)))

    gem_shadow = Image.new("L", (size, size), 0)
    gem_points = [(245, 252), (500, 128), (790, 278), (720, 680), (450, 834), (218, 610)]
    gem_points = [(int(x * scale), int(y * scale)) for x, y in gem_points]
    ImageDraw.Draw(gem_shadow).polygon(gem_points, fill=255)
    image.alpha_composite(shadow_for_mask(gem_shadow, (int(8 * scale), int(18 * scale)), int(28 * scale), 100))

    facets = [
        ([(245, 252), (500, 128), (478, 430), (300, 472)], (150, 88, 238, 255)),
        ([(500, 128), (790, 278), (610, 420), (478, 430)], (116, 73, 222, 255)),
        ([(300, 472), (478, 430), (450, 834), (218, 610)], (76, 49, 156, 255)),
        ([(478, 430), (610, 420), (720, 680), (450, 834)], (57, 38, 127, 255)),
        ([(610, 420), (790, 278), (720, 680)], (93, 54, 188, 255)),
        ([(245, 252), (300, 472), (218, 610)], (192, 132, 255, 255)),
    ]
    for points, color in facets:
        scaled = [(int(x * scale), int(y * scale)) for x, y in points]
        image.alpha_composite(polygon_layer((size, size), scaled, color))

    edge_color = (228, 210, 255, 86)
    dark_edge = (22, 15, 54, 80)
    for points in [
        [(245, 252), (500, 128), (790, 278), (720, 680), (450, 834), (218, 610)],
        [(300, 472), (478, 430), (500, 128)],
        [(478, 430), (450, 834)],
        [(478, 430), (610, 420), (790, 278)],
        [(610, 420), (720, 680)],
    ]:
        scaled = [(int(x * scale), int(y * scale)) for x, y in points]
        draw.line(scaled, fill=edge_color, width=max(2, int(6 * scale)), joint="curve")
        draw.line(scaled, fill=dark_edge, width=max(1, int(2 * scale)), joint="curve")

    shine = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    shine_draw = ImageDraw.Draw(shine)
    shine_draw.line(
        [(int(350 * scale), int(228 * scale)), (int(485 * scale), int(168 * scale)), (int(625 * scale), int(240 * scale))],
        fill=(255, 255, 255, 86),
        width=max(2, int(10 * scale)),
        joint="curve",
    )
    image.alpha_composite(shine.filter(ImageFilter.GaussianBlur(int(0.4 * scale))))

    card_box = tuple(int(v * scale) for v in (520, 565, 850, 825))
    card_radius = int(58 * scale)
    card_mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(card_mask).rounded_rectangle(card_box, radius=card_radius, fill=255)
    image.alpha_composite(shadow_for_mask(card_mask, (int(6 * scale), int(12 * scale)), int(20 * scale), 92))

    draw.rounded_rectangle(card_box, radius=card_radius, fill=(250, 247, 255, 242), outline=(255, 255, 255, 190), width=max(1, int(3 * scale)))
    header = (card_box[0], card_box[1], card_box[2], int(642 * scale))
    draw.rounded_rectangle(header, radius=card_radius, fill=(255, 82, 112, 238))
    draw.rectangle((header[0], int(610 * scale), header[2], header[3]), fill=(255, 82, 112, 238))

    for x in (610, 760):
        draw.rounded_rectangle(
            (int((x - 22) * scale), int(535 * scale), int((x + 22) * scale), int(592 * scale)),
            radius=int(14 * scale),
            fill=(245, 232, 255, 255),
        )

    number_font = load_font(int(112 * scale), bold=True)
    number = "12"
    bbox = draw.textbbox((0, 0), number, font=number_font)
    text_w = bbox[2] - bbox[0]
    text_h = bbox[3] - bbox[1]
    draw.text(
        (card_box[0] + (card_box[2] - card_box[0] - text_w) / 2, int(650 * scale) + (int(112 * scale) - text_h) / 2 - int(8 * scale)),
        number,
        font=number_font,
        fill=(54, 43, 82, 255),
    )

    check_points = [(620, 765), (681, 816), (791, 685)]
    check_points = [(int(x * scale), int(y * scale)) for x, y in check_points]
    draw.line(check_points, fill=(23, 183, 255, 255), width=max(8, int(26 * scale)), joint="curve")
    draw.line(check_points, fill=(255, 255, 255, 210), width=max(2, int(8 * scale)), joint="curve")

    return image


def save_iconset(base):
    if ICONSET.exists():
        shutil.rmtree(ICONSET)
    ICONSET.mkdir(parents=True, exist_ok=True)

    specs = [
        ("icon_16x16.png", 16),
        ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32),
        ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128),
        ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256),
        ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512),
        ("icon_512x512@2x.png", 1024),
    ]
    for name, target_size in specs:
        resized = base.resize((target_size, target_size), Image.Resampling.LANCZOS)
        resized.save(ICONSET / name)


def main():
    ASSETS.mkdir(parents=True, exist_ok=True)
    icon = draw_icon()
    icon.save(BASE_PNG)
    save_iconset(icon)
    if ICNS.exists():
        ICNS.unlink()
    subprocess.run(["iconutil", "-c", "icns", str(ICONSET), "-o", str(ICNS)], check=True)
    print(f"Wrote {BASE_PNG}")
    print(f"Wrote {ICNS}")


if __name__ == "__main__":
    main()
