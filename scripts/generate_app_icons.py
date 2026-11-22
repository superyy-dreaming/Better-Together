#!/usr/bin/env python3
"""Generate native launcher icons from the user-approved stamp artwork.

Usage: python3 scripts/generate_app_icons.py
Requires Pillow. The original artwork is local; no network or AI calls occur.
"""
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "assets/brand/better-together-icon-source.jpg"
BACKGROUND = "#114634"
PAPER = "#F6F3EA"
DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}


def load_artwork():
    with Image.open(SOURCE) as source:
        image = ImageOps.exif_transpose(source).convert("RGB")
    if image.width != image.height or image.width < 1024:
        raise ValueError("The approved icon source must be square and at least 1024px.")
    return image


def adaptive_foreground(artwork, pixels):
    # Android uses a 108dp canvas and a 66dp safe region. In the supplied
    # artwork, the stamp/check/anchor fit within the middle 60dp at this scale.
    # Keep the complete artwork, inset to 84dp; only background decoration can
    # fall outside the launcher mask. Do not bake a circle or rounded mask in.
    layer = Image.new("RGB", (pixels, pixels), BACKGROUND)
    artwork_size = round(pixels * 84 / 108)
    offset = (pixels - artwork_size) // 2
    layer.paste(
        artwork.resize((artwork_size, artwork_size), Image.Resampling.LANCZOS),
        (offset, offset),
    )
    return layer


def save_proof(master, adaptive):
    output = ROOT / "output/brand"
    output.mkdir(parents=True, exist_ok=True)
    master.save(output / "better-together-icon.png")
    sheet = Image.new("RGB", (1080, 630), PAPER)
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.load_default(size=18)
    for x, pixels in [(24, 384), (450, 180), (680, 96), (842, 60), (974, 48)]:
        sheet.paste(master.resize((pixels, pixels), Image.Resampling.LANCZOS), (x, 50))
        draw.text((x, 20), f"{pixels}px", fill=BACKGROUND, font=font)
    # Preview OEM masks at the normal 72dp viewport within the 108dp layer.
    viewport = adaptive.crop((72, 72, 360, 360)).resize((144, 144), Image.Resampling.LANCZOS)
    for x, shape in [(450, "circle"), (650, "rounded")]:
        mask = Image.new("L", (144, 144))
        mask_draw = ImageDraw.Draw(mask)
        if shape == "circle":
            mask_draw.ellipse((0, 0, 143, 143), fill=255)
        else:
            mask_draw.rounded_rectangle((0, 0, 143, 143), radius=34, fill=255)
        sheet.paste(viewport, (x, 400), mask)
        draw.text((x, 560), f"Android {shape}", fill=BACKGROUND, font=font)
    draw.text((24, 592), "Approved artwork; RGB icons; launcher masks applied only in this proof.", fill=BACKGROUND, font=font)
    sheet.save(output / "icon-size-proof.png")


def main():
    artwork = load_artwork()
    master = artwork.resize((1024, 1024), Image.Resampling.LANCZOS)
    asset_dir = ROOT / "app/ios/Runner/Assets.xcassets/AppIcon.appiconset"
    manifest = json.loads((asset_dir / "Contents.json").read_text())
    for item in manifest["images"]:
        points = float(item["size"].split("x")[0])
        scale = float(item["scale"].rstrip("x"))
        pixels = round(points * scale)
        master.resize((pixels, pixels), Image.Resampling.LANCZOS).save(asset_dir / item["filename"])

    res = ROOT / "app/android/app/src/main/res"
    for density, scale in DENSITIES.items():
        folder = res / f"mipmap-{density}"
        folder.mkdir(parents=True, exist_ok=True)
        pixels = round(48 * scale)
        master.resize((pixels, pixels), Image.Resampling.LANCZOS).save(folder / "ic_launcher.png")
        adaptive_foreground(artwork, round(108 * scale)).save(folder / "ic_launcher_foreground.png")

    adaptive = res / "mipmap-anydpi-v26"
    adaptive.mkdir(exist_ok=True)
    # An opaque full-color raster is not a valid monochrome silhouette: using
    # it as the monochrome layer would produce a solid square in themed icons.
    (adaptive / "ic_launcher.xml").write_text('''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@color/icon_background" />
    <foreground android:drawable="@mipmap/ic_launcher_foreground" />
</adaptive-icon>
''')
    (res / "values/icon_colors.xml").write_text(f'''<?xml version="1.0" encoding="utf-8"?>
<resources><color name="icon_background">{BACKGROUND}</color></resources>
''')
    save_proof(master, adaptive_foreground(artwork, 432))
    print(f"Generated {len(manifest['images'])} iOS entries and 5 Android densities.")
    print(f"Proof: {ROOT / 'output/brand/icon-size-proof.png'}")


if __name__ == "__main__":
    main()
