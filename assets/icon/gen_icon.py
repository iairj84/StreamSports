"""Render the StreamSports launcher icon and TV banner.

No upstream VesperTV artwork is used: the mark is a play glyph inside a quiet
television outline. Run from the repository root with Pillow installed:

    python assets/icon/gen_icon.py
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
BACKGROUND = '#0B1220'
FRAME = '#223049'
ACCENT = '#38BDF8'
SS = 4  # supersample factor for smooth edges

# density: (launcher px, adaptive layer px)
DENSITIES = {
    'mdpi': (48, 108),
    'hdpi': (72, 162),
    'xhdpi': (96, 216),
    'xxhdpi': (144, 324),
    'xxxhdpi': (192, 432),
}


def mark(size, transparent=False, monochrome=False):
    w = size * SS
    img = Image.new('RGBA', (w, w), (0, 0, 0, 0) if transparent else BACKGROUND)
    d = ImageDraw.Draw(img)
    u = w / 108
    ink = '#FFFFFF' if monochrome else ACCENT
    frame = ink if monochrome else FRAME

    # Screen outline, inset from the adaptive-icon safe zone.
    d.rounded_rectangle([int(18 * u), int(28 * u), int(90 * u), int(76 * u)],
                        radius=int(9 * u), outline=frame, width=int(3 * u))
    # Play glyph.
    d.polygon([(int(46 * u), int(40 * u)), (int(71 * u), int(52 * u)),
               (int(46 * u), int(64 * u))], fill=ink)
    # Stand.
    d.rounded_rectangle([int(44 * u), int(79 * u), int(64 * u), int(85 * u)],
                        radius=int(3 * u), fill=frame)
    return img.resize((size, size), Image.Resampling.LANCZOS)


def wordmark(width, height):
    img = Image.new('RGBA', (width * SS, height * SS), BACKGROUND)
    d = ImageDraw.Draw(img)
    badge = mark(height * SS, transparent=True)
    img.alpha_composite(badge, (int(10 * SS), 0))
    text = 'StreamSports'
    font = None
    for candidate in ('C:/Windows/Fonts/segoeuib.ttf',
                      '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'):
        try:
            font = ImageFont.truetype(candidate, int(height * 0.30 * SS))
            break
        except OSError:
            continue
    if font is not None:
        d.text((int(height * 1.10 * SS), int(height * 0.33 * SS)), text,
               font=font, fill='#E2E8F0')
    return img.resize((width, height), Image.Resampling.LANCZOS)


def main():
    assets = ROOT / 'assets/icon'
    mark(1024).convert('RGB').save(assets / 'icon_flat.png')
    mark(1024, transparent=True).save(assets / 'icon_foreground.png')
    Image.new('RGB', (1024, 1024), BACKGROUND).save(assets / 'icon_background.png')

    res = ROOT / 'android/app/src/main/res'
    for density, (launcher, layer) in DENSITIES.items():
        (res / f'mipmap-{density}').mkdir(parents=True, exist_ok=True)
        mark(launcher).convert('RGB').save(res / f'mipmap-{density}/ic_launcher.png')
        mark(launcher).convert('RGB').save(
            res / f'mipmap-{density}/ic_launcher_round.png')
        drawable = res / f'drawable-{density}'
        drawable.mkdir(parents=True, exist_ok=True)
        mark(layer, transparent=True).save(drawable / 'ic_launcher_foreground.png')
        mark(layer, transparent=True, monochrome=True).save(
            drawable / 'ic_launcher_monochrome.png')
        Image.new('RGB', (layer, layer), BACKGROUND).save(
            drawable / 'ic_launcher_background.png')

    wordmark(320, 180).convert('RGB').save(res / 'drawable-nodpi/streamsports_banner.png')

    for pattern in (
        'ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png',
        'macos/Runner/Assets.xcassets/AppIcon.appiconset/*.png',
        'web/icons/*.png',
        'web/favicon.png',
    ):
        for path in ROOT.glob(pattern):
            with Image.open(path) as old:
                size = old.width
            mark(size).convert('RGB').save(path)

    windows = ROOT / 'windows/runner/resources/app_icon.ico'
    if windows.parent.exists():
        mark(256).save(windows, sizes=[(s, s) for s in (16, 24, 32, 48, 64, 128, 256)])

    print('StreamSports icons written')


if __name__ == '__main__':
    main()
