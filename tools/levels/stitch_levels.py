from PIL import Image, ImageDraw, ImageStat, ImageEnhance
import os

SRC = "/home/user/grimdark_levels_3part"
OUT = "/home/user/grimdark_levels_3part/composites"
os.makedirs(OUT, exist_ok=True)

LEVELS = {
    "L1_village_road":  [("L1_T1_village_road_west.png", 0.505),
                         ("L1_T2_village_road_core.png", 0.535),
                         ("L1_T3_village_road_east.png", 0.465)],
    "L2_forest_road":   [("L2_T1_forest_road_west.png", 0.505),
                         ("L2_T2_forest_road_core.png", 0.470),
                         ("L2_T3_forest_road_east.png", 0.425)],
    "L3_city_road":     [("L3_T1_city_road_west.png", 0.500),
                         ("L3_T2_city_road_core.png", 0.500),
                         ("L3_T3_city_road_east.png", 0.490)],
}
OVERLAP = 170
WSCALE  = 1568
FLIP    = Image.FLIP_TOP_BOTTOM

def shifted(im, dy):
    """shift content vertically by dy px (+, down) with mirrored fill at the exposed edge"""
    w, h = im.size
    if dy == 0:
        return im
    c = Image.new("RGB", (w, h))
    if dy > 0:
        c.paste(im.crop((0, 0, w, h - dy)), (0, dy))
        c.paste(im.crop((0, 0, w, dy)).transpose(FLIP), (0, 0))
    else:
        d = -dy
        c.paste(im.crop((0, d, w, h)), (0, 0))
        c.paste(im.crop((0, h - d, w, h)).transpose(FLIP), (0, h - d))
    return c

def match_tone(im, ref):
    """soft 45% pull of im's mean colour toward ref's"""
    a = ImageStat.Stat(im).mean
    b = ImageStat.Stat(ref).mean
    chans = [ImageEnhance.Brightness(im.getchannel(i)).enhance(
                1.0 + 0.45 * ((b[i] + 1e-6) / (a[i] + 1e-6) - 1.0)) for i in range(3)]
    return Image.merge("RGB", chans)

for name, tiles in LEVELS.items():
    raw = []
    for fn, road in tiles:
        im = Image.open(os.path.join(SRC, fn)).convert("RGB")
        w, h = im.size
        raw.append([im.resize((WSCALE, round(h * WSCALE / w)), Image.LANCZOS), road])

    target = sum(r for _, r in raw) / len(raw)          # centre the shift range
    imgs = [shifted(im, round((target - road) * im.size[1])) for im, road in raw]
    imgs = [imgs[0]] + [match_tone(im, imgs[0]) for im in imgs[1:]]

    h = imgs[0].size[1]
    total_w = WSCALE * 3 - OVERLAP * 2
    strip = Image.new("RGB", (total_w, h))
    strip.paste(imgs[0], (0, 0))
    x = WSCALE - OVERLAP
    for im in imgs[1:]:
        grad = Image.new("L", (OVERLAP, h))
        d = ImageDraw.Draw(grad)
        for px in range(OVERLAP):
            d.line([(px, 0), (px, h)], fill=int(255 * px / OVERLAP))
        strip.paste(im.crop((OVERLAP, 0, WSCALE, h)), (x + OVERLAP, 0))
        strip.paste(im.crop((0, 0, OVERLAP, h)), (x, 0), grad)
        x += WSCALE - OVERLAP

    strip.save(os.path.join(OUT, f"{name}_strip.png"), optimize=True)
    strip.resize((2400, round(h * 2400 / total_w)), Image.LANCZOS).save(
        os.path.join(OUT, f"{name}_strip_preview.png"), optimize=True)
    print(name, "->", strip.size, "| shift target road y:", round(target, 3))
