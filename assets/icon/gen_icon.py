"""Render every StreamSports launcher asset from one mark.

SUPERSEDED: the shipped launcher art is now the designed pack (TV frame,
on-field football, Barlow Condensed wordmark, #0F5BFF). This script draws the
earlier broadcast-ring mark, so running it would overwrite the current PNGs.
Kept only as the record of that pass; do not run it against assets/.

The mark is a broadcast ring with a play glyph inside it: a stream you can
start, drawn at sizes that survive a 48 px launcher tile. Everything is
generated here so no hand-edited PNG can drift from the others:

    python assets/icon/gen_icon.py

Outputs
  assets/icon/icon_flat.png             master 1024, opaque, for in-app use
  assets/icon/icon_background.png       adaptive background layer
  assets/icon/icon_foreground.png       adaptive foreground layer (transparent)
  assets/icon/icon_monochrome.png       Android 13 themed-icon source (white)
  assets/icon/icon_store_512.png        listing artwork, 512, opaque
  assets/icon/logo_transparent.png      Projectivy / any launcher that wants a
  assets/icon/banner_transparent.png    cut-out logo over its own backdrop;
                                        the *_light variants are the same art
                                        in navy, for light backgrounds
  android/app/src/main/res/mipmap-*     legacy square and round launchers
  android/app/src/main/res/drawable-*   adaptive layers per density
  android/app/src/main/res/drawable-nodpi/streamsports_banner.png
                                        Android TV / Fire TV banner, 1280x720
  ios, macos, web, windows               their own icon sets at their sizes
"""
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]

# Palette: deep navy ground, sky-to-indigo broadcast gradient.
NAVY_TOP = (12, 19, 33)
NAVY_BOTTOM = (21, 33, 56)
ACCENT_A = (56, 189, 248)
ACCENT_B = (99, 102, 241)
WHITE = (255, 255, 255)

SS = 4  # supersample factor for smooth edges

# density: (legacy launcher px, adaptive layer px)
DENSITIES = {
    'mdpi': (48, 108),
    'hdpi': (72, 162),
    'xhdpi': (96, 216),
    'xxhdpi': (144, 324),
    'xxxhdpi': (192, 432),
}

BANNER = (1280, 720)


def gradient(size, start, end, steps=192):
    """A smooth diagonal gradient from [start] (top-left) to [end]."""
    small = Image.new('RGB', (steps, steps))
    px = small.load()
    span = 2 * (steps - 1)
    for y in range(steps):
        for x in range(steps):
            t = (x + y) / span
            px[x, y] = tuple(
                round(start[i] + (end[i] - start[i]) * t) for i in range(3))
    return small.resize(size, Image.Resampling.BICUBIC)


def _ring_mask(size, radius, stroke):
    mask = Image.new('L', (size, size), 0)
    box = [size / 2 - radius, size / 2 - radius,
           size / 2 + radius, size / 2 + radius]
    ImageDraw.Draw(mask).ellipse(box, outline=255, width=max(1, round(stroke)))
    return mask


def _triangle_mask(size, points, radius):
    """The play glyph, as a mask: a triangle whose corners are rounded.

    Blurring and re-thresholding rounds every corner evenly. Adding circles at
    the vertices instead leaves visible bulbs where they overshoot the edges.
    """
    mask = Image.new('L', (size, size), 0)
    ImageDraw.Draw(mask).polygon(points, fill=255)
    if radius <= 0:
        return mask
    mask = mask.filter(ImageFilter.GaussianBlur(radius * 0.75))
    return mask.point(lambda v: 255 if v >= 190 else 0)


def layer(px, transparent=False, monochrome=False, glyph_scale=1.0,
          ink=WHITE):
    """The mark at [px] pixels square, without any resampling."""
    canvas = Image.new('RGBA', (px, px), (0, 0, 0, 0))
    if not transparent and not monochrome:
        canvas.paste(gradient((px, px), NAVY_TOP, NAVY_BOTTOM), (0, 0))

    # Everything is laid out on a 108-unit grid; glyph_scale shrinks the
    # artwork around the centre, which is what the adaptive foreground needs
    # to stay inside Android's safe zone.
    u = px / 108 * glyph_scale
    centre = px / 2

    def at(x, y):
        return (centre + (x - 54) * u, centre + (y - 54) * u)

    ring = _ring_mask(px, 33 * u, 6.5 * u)
    tri_points = [at(44, 34), at(76, 54), at(44, 74)]
    triangle = _triangle_mask(px, tri_points, 3.2 * u)
    glyph = Image.new('L', (px, px), 0)
    glyph.paste(ring, (0, 0))
    glyph.paste(triangle, (0, 0), triangle)

    tint = (Image.new('RGBA', (px, px), WHITE + (255,)) if monochrome
            else gradient((px, px), ACCENT_A, ACCENT_B).convert('RGBA'))
    canvas.paste(tint, (0, 0), ring)

    # The play glyph is always white; the monochrome layer is a single ink.
    if monochrome:
        canvas.paste(tint, (0, 0), triangle)
    else:
        canvas.paste(Image.new('RGBA', (px, px), tuple(ink) + (255,)), (0, 0),
                     triangle)
    return canvas


def mark(size, transparent=False, monochrome=False, glyph_scale=1.0,
         ink=WHITE):
    return layer(size * SS, transparent=transparent, monochrome=monochrome,
                 glyph_scale=glyph_scale, ink=ink).resize(
                     (size, size), Image.Resampling.LANCZOS)


def badge(size, round_badge=False):
    """The opaque launcher tile: gradient ground, mark centred."""
    px = size * SS
    ground = gradient((px, px), NAVY_TOP, NAVY_BOTTOM).convert('RGBA')
    mask = Image.new('L', (px, px), 0)
    d = ImageDraw.Draw(mask)
    if round_badge:
        d.ellipse([0, 0, px - 1, px - 1], fill=255)
    else:
        d.rounded_rectangle([0, 0, px - 1, px - 1], radius=round(px * 22 / 108),
                            fill=255)
    tile = Image.new('RGBA', (px, px), (0, 0, 0, 0))
    tile.paste(ground, (0, 0), mask)
    glyph = layer(px, transparent=True,
                  glyph_scale=0.95 if round_badge else 1.06)
    tile.alpha_composite(glyph, (0, 0))
    return tile.resize((size, size), Image.Resampling.LANCZOS)


def _font(size):
    for candidate in ('C:/Windows/Fonts/segoeuib.ttf',
                      'C:/Windows/Fonts/seguisb.ttf',
                      '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'):
        try:
            return ImageFont.truetype(candidate, size)
        except OSError:
            continue
    return None


def _tracked(draw, xy, text, font, fill, tracking=0, stroke=0):
    x, y = xy
    for ch in text:
        draw.text((x, y), ch, font=font, fill=fill,
                  stroke_width=stroke,
                  stroke_fill=(7, 11, 20, 200) if stroke else None)
        x += draw.textlength(ch, font=font) + tracking


def _fit_font(draw, text, max_width, start=220, tracking=0):
    size = start
    while size > 24:
        font = _font(size)
        if font is None:
            return None
        width = sum(draw.textlength(c, font=font) + tracking for c in text)
        if width <= max_width:
            return font
        size -= 4
    return _font(24)


def _wordmark(draw, right_edge, centre_y, max_width, tracking, stroke=False,
              ink=WHITE):
    """Draw 'Stream' in [ink] and 'Sports' in accent, right-aligned."""
    font = _fit_font(draw, 'StreamSports', max_width, tracking=tracking)
    if font is None:
        return False
    box = font.getbbox('StreamSports')
    weight = max(1, round(font.size * 0.022)) if stroke else 0
    x = right_edge - sum(
        draw.textlength(c, font=font) + tracking for c in 'StreamSports')
    y = centre_y - (box[3] - box[1]) / 2 - box[1]
    _tracked(draw, (x, y), 'Stream', font, tuple(ink) + (255,), tracking,
             weight)
    x += sum(draw.textlength(c, font=font) + tracking for c in 'Stream')
    _tracked(draw, (x, y), 'Sports', font, ACCENT_A + (255,), tracking, weight)
    return True


def banner(width, height, transparent=False, ink=WHITE):
    w, h = width * SS, height * SS
    img = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    if not transparent:
        img.paste(gradient((w, h), NAVY_TOP, NAVY_BOTTOM), (0, 0))

    inset = round(h * 0.12)
    glyph_size = h - 2 * inset
    img.alpha_composite(
        layer(glyph_size, transparent=True, ink=ink), (inset, inset))

    d = ImageDraw.Draw(img)
    text_left = inset + glyph_size + round(w * 0.035)
    _wordmark(d, w - inset, h / 2, w - text_left - inset,
              tracking=h * 0.004, stroke=transparent, ink=ink)
    return img.resize((width, height), Image.Resampling.LANCZOS)


def preview():
    """A contact sheet for review; not shipped with the app."""
    tiles = [
        ('1024', badge(1024)),
        ('192', badge(192)),
        ('48', badge(48)),
        ('round 192', badge(192, round_badge=True)),
        ('adaptive fg', mark(192, transparent=True, glyph_scale=0.98)),
        ('monochrome', mark(192, transparent=True, monochrome=True)),
        ('transparent logo', mark(192, transparent=True, glyph_scale=0.96)),
    ]
    pad, label_h = 24, 22
    width = pad + sum(t.width + pad for _, t in tiles)
    height = pad + 1024 + label_h + pad
    sheet = Image.new('RGB', (width, height), (242, 244, 248))
    x = pad
    for _, tile in tiles:
        sheet.paste(tile.convert('RGB'), (x, pad), tile)
        x += tile.width + pad
    d = ImageDraw.Draw(sheet)
    font = _font(18)
    x = pad
    if font is not None:
        for name, tile in tiles:
            d.text((x, pad + 1024 + 4), name, font=font, fill=(40, 48, 64))
            x += tile.width + pad
    sheet.save(ROOT / 'build/icon_preview.png')


def main():
    assets = ROOT / 'assets/icon'

    mark(1024).convert('RGB').save(assets / 'icon_flat.png')
    mark(1024, transparent=True).save(assets / 'icon_foreground.png')
    mark(1024, transparent=True, monochrome=True).save(
        assets / 'icon_monochrome.png')
    gradient((1024, 1024), NAVY_TOP, NAVY_BOTTOM).save(
        assets / 'icon_background.png')
    badge(512).convert('RGB').save(assets / 'icon_store_512.png')

    # Transparent marks for launchers that composite their own backdrop
    # (Projectivy in particular).
    mark(1024, transparent=True, glyph_scale=0.96).save(
        assets / 'logo_transparent.png')
    mark(1024, transparent=True, glyph_scale=0.96, ink=NAVY_TOP).save(
        assets / 'logo_transparent_light.png')
    banner(*BANNER, transparent=True).save(assets / 'banner_transparent.png')
    banner(*BANNER, transparent=True, ink=NAVY_TOP).save(
        assets / 'banner_transparent_light.png')

    res = ROOT / 'android/app/src/main/res'
    for density, (launcher, layer_px) in DENSITIES.items():
        (res / f'mipmap-{density}').mkdir(parents=True, exist_ok=True)
        badge(launcher).convert('RGB').save(
            res / f'mipmap-{density}/ic_launcher.png')
        badge(launcher, round_badge=True).convert('RGB').save(
            res / f'mipmap-{density}/ic_launcher_round.png')
        drawable = res / f'drawable-{density}'
        drawable.mkdir(parents=True, exist_ok=True)
        # 62/108 keeps the ring inside the adaptive safe zone.
        mark(layer_px, transparent=True, glyph_scale=0.98).save(
            drawable / 'ic_launcher_foreground.png')
        mark(layer_px, transparent=True, monochrome=True, glyph_scale=0.98).save(
            drawable / 'ic_launcher_monochrome.png')
        gradient((layer_px, layer_px), NAVY_TOP, NAVY_BOTTOM).save(
            drawable / 'ic_launcher_background.png')

    banner(*BANNER).convert('RGB').save(
        res / 'drawable-nodpi/streamsports_banner.png')

    for pattern in (
        'ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png',
        'macos/Runner/Assets.xcassets/AppIcon.appiconset/*.png',
        'web/icons/*.png',
        'web/favicon.png',
    ):
        for path in ROOT.glob(pattern):
            with Image.open(path) as old:
                size = old.width
            if 'maskable' in path.name:
                # Maskable icons keep their artwork inside the inner 80 %.
                tile = badge(size)
                inner = round(size * 0.8)
                shrunk = tile.resize((inner, inner), Image.Resampling.LANCZOS)
                tile = Image.new('RGB', (size, size), NAVY_TOP)
                tile.paste(shrunk, ((size - inner) // 2, (size - inner) // 2))
                tile.save(path)
            else:
                badge(size).convert('RGB').save(path)

    windows = ROOT / 'windows/runner/resources/app_icon.ico'
    if windows.parent.exists():
        badge(256).save(
            windows, sizes=[(s, s) for s in (16, 24, 32, 48, 64, 128, 256)])

    preview()
    print('StreamSports icons written')


if __name__ == '__main__':
    main()
