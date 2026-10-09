"""Extract the character sprites from assets/sprites/sheets/*.png.

Keys out the #FF00FF background (with despill, so the ink edges keep their colour),
splits each 2 x 2 sheet into its four figures and trims each one.
Writes tools/sprites/work/cut/<key>.png (RGBA, trimmed) and work/extract.json.
Run from the project folder:  python3 tools/sprites/extract_sprites.py
"""
import json, os
import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
WORK = os.path.join(ROOT, 'tools', 'sprites', 'work')
SLOTS = {'top_left': (0, 0), 'top_right': (1, 0), 'bottom_left': (0, 1), 'bottom_right': (1, 1)}
KEY = np.array([255.0, 0.0, 255.0])


def key_out(rgb):
    """Alpha from distance to magenta; colour un-mixed from the magenta behind it."""
    d = np.sqrt(((rgb - KEY) ** 2).sum(-1))
    a = np.clip((d - 60.0) / (170.0 - 60.0), 0.0, 1.0)
    # magenta-ness: green far below red and blue is the signature of the background
    spill = np.clip((np.minimum(rgb[..., 0], rgb[..., 2]) - rgb[..., 1] - 40.0) / 120.0, 0.0, 1.0)
    a = np.minimum(a, 1.0 - spill * (a < 0.999))
    safe = np.maximum(a, 1e-3)[..., None]
    fg = (rgb - (1.0 - a[..., None]) * KEY) / safe
    fg = np.clip(fg, 0.0, 255.0)
    return fg, a


def main():
    man = json.load(open(os.path.join(ROOT, 'assets', 'sprites', 'manifest.json')))
    os.makedirs(os.path.join(WORK, 'cut'), exist_ok=True)
    info = {}
    for sh in man['sheets']:
        if sh.get('status') != 'generated':
            continue
        im = np.asarray(Image.open(os.path.join(ROOT, sh['file'])).convert('RGB'), dtype=np.float64)
        H, W, _ = im.shape
        fg, a = key_out(im)
        # figures: the big blobs on the whole sheet (they can cross the quadrant lines),
        # each assigned to the slot its centre falls in; specks join the nearest figure
        solid = ndimage.binary_dilation(a > 0.5, iterations=3)
        lab, n = ndimage.label(solid)
        sizes = ndimage.sum(solid, lab, range(1, n + 1))
        coms = ndimage.center_of_mass(solid, lab, range(1, n + 1))
        boxes = ndimage.find_objects(lab)
        big = [i for i in range(n) if sizes[i] > sizes.max() * 0.05]
        owner = {}
        for i in range(n):
            if i in big:
                owner[i] = i
                continue
            sl = boxes[i]
            best, bd = None, 1e9
            for j in big:
                sj = boxes[j]
                dx = max(sj[1].start - sl[1].stop, sl[1].start - sj[1].stop, 0)
                dy = max(sj[0].start - sl[0].stop, sl[0].start - sj[0].stop, 0)
                if max(dx, dy) < bd:
                    best, bd = j, max(dx, dy)
            if bd <= 12:
                owner[i] = best
        slot_of = {}
        for j in big:
            cy_, cx_ = coms[j]
            slot_of[(int(cx_ >= W / 2), int(cy_ >= H / 2))] = j
        for sp in sh['sprites']:
            j = slot_of.get(SLOTS[sp['slot']])
            if j is None:
                print('  no figure in', sh['id'], sp['slot'])
                continue
            ids = [i + 1 for i, o in owner.items() if o == j]
            mask = np.isin(lab, ids)
            qa = a * mask
            ys, xs = np.nonzero(qa > 0.02)
            bx0, bx1, by0, by1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
            rgba = np.dstack([fg, qa * 255.0])[by0:by1, bx0:bx1]
            out = Image.fromarray(rgba.round().astype(np.uint8), 'RGBA')
            out.save(os.path.join(WORK, 'cut', sp['key'] + '.png'))
            info[sp['key']] = {'sheet': sh['id'], 'slot': sp['slot'], 'size': [int(bx1 - bx0), int(by1 - by0)],
                               'sheet_box': [int(bx0), int(by0), int(bx1), int(by1)]}
            print(sp['key'], info[sp['key']]['size'])
    json.dump(info, open(os.path.join(WORK, 'extract.json'), 'w'), indent=1)


if __name__ == '__main__':
    main()
