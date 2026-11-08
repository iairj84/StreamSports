"""Derive the non-Android icon sets from the designed mark.

Source of truth is assets/icon/icon_source.svg (the pack's vector square
icon). When cairosvg is importable the SVG is rasterized at each size, which
stays sharp at 1024. Otherwise it falls back to resampling
assets/icon/icon_flat.png with a light unsharp pass.

    python assets/icon/gen_platform_icons.py

Writes the iOS app icon set at every size Contents.json asks for, the web
PWA icons (including mask-safe variants) and favicon, and the Windows .ico
when that platform folder exists.
"""
import io
import json
import re
from pathlib import Path

from PIL import Image, ImageFilter

try:
    import cairosvg
except Exception:  # no cairo on this machine: fall back to the raster master
    cairosvg = None

ROOT = Path(__file__).resolve().parents[2]
SVG = ROOT / 'assets/icon/icon_source.svg'
MASTER = ROOT / 'assets/icon/icon_flat.png'
BLUE = (15, 91, 255)


def render(size):
    """A square, opaque icon at [size] pixels."""
    if cairosvg is not None and SVG.exists():
        png = cairosvg.svg2png(url=str(SVG), output_width=size, output_height=size)
        art = Image.open(io.BytesIO(png)).convert('RGBA')
        plate = Image.new('RGB', (size, size), BLUE)
        plate.paste(art, (0, 0), art)
        return plate
    with Image.open(MASTER) as src:
        art = src.convert('RGB')
    if art.width == size:
        return art.copy()
    out = art.resize((size, size), Image.Resampling.LANCZOS)
    if size > art.width:
        out = out.filter(ImageFilter.UnsharpMask(1.0, 55, 2))
    return out


def maskable(size):
    """PWA maskable: artwork inside the inner 80 %, brand blue behind it."""
    inner = round(size * 0.8)
    tile = Image.new('RGB', (size, size), BLUE)
    tile.paste(render(inner), ((size - inner) // 2, (size - inner) // 2))
    return tile


def ios_icons():
    folder = ROOT / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
    meta = json.loads((folder / 'Contents.json').read_text(encoding='utf-8'))
    written = []
    for entry in meta.get('images', []):
        name = entry.get('filename')
        if not name:
            continue
        points = float(re.match(r'[\d.]+', entry['size']).group())
        scale = float(entry['scale'].rstrip('x'))
        px = round(points * scale)
        render(px).save(folder / name)  # RGB: the App Store rejects alpha
        written.append((f'ios/.../{name}', px))
    return written


def web_icons():
    folder = ROOT / 'web/icons'
    written = []
    plan = (('Icon-192.png', 192, False), ('Icon-512.png', 512, False),
            ('Icon-maskable-192.png', 192, True),
            ('Icon-maskable-512.png', 512, True))
    for name, px, masked in plan:
        (maskable(px) if masked else render(px)).save(folder / name)
        written.append((f'web/icons/{name}', px))
    favicon = ROOT / 'web/favicon.png'
    if favicon.exists():
        with Image.open(favicon) as current:
            px = current.width
        render(px).save(favicon)
        written.append(('web/favicon.png', px))
    return written


def macos_icons():
    folder = ROOT / 'macos/Runner/Assets.xcassets/AppIcon.appiconset'
    meta = folder / 'Contents.json'
    if not meta.exists():
        return []
    entries = json.loads(meta.read_text(encoding='utf-8')).get('images', [])
    written = []
    for entry in entries:
        name = entry.get('filename')
        if not name:
            continue
        points = float(re.match(r'[\d.]+', entry['size']).group())
        px = round(points * float(entry['scale'].rstrip('x')))
        render(px).save(folder / name)
        written.append((f'macos/.../{name}', px))
    return written


def windows_icon():
    ico = ROOT / 'windows/runner/resources/app_icon.ico'
    if not ico.parent.exists():
        return []
    render(256).save(ico, sizes=[(s, s) for s in (16, 24, 32, 48, 64, 128, 256)])
    return [('windows/runner/resources/app_icon.ico', 256)]


if __name__ == '__main__':
    print('renderer:', 'cairosvg (vector)' if cairosvg is not None and SVG.exists()
          else 'resampled icon_flat.png')
    for group in (ios_icons(), macos_icons(), web_icons(), windows_icon()):
        for name, px in group:
            print(f'  {name:<44} {px}px')
