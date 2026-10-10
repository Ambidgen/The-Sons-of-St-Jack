"""Turn the extracted character sprites into articulated 2D rigs for the game.

For each sprite (tools/sprites/work/cut/<key>.png, from extract_sprites.py):
  1. scale it to the game's texel density (K px per art unit) at the character's height,
  2. cut it into body parts -- head, torso, arms (with whatever they hold), legs, or a
     skirt for robes -- with a seeded watershed that follows the ink outlines,
  3. give every part some hidden material behind its neighbours (the torso continues
     under the arms and the neck, the legs continue up under the hem), so nothing tears
     open when a limb moves, and ink the edges that a moving limb uncovers,
  4. write a rig sheet (one cell per part) and the bone layout to assets/sprites/rigs.json,
     which overrides the old SVG rigs of the same name. The game's Rig node builds a
     textured mesh per part, hangs it on a bone at its joint and animates it.
Also writes the flat sprite (assets/sprites/char/<key>.png) and a review overlay.

Seeds come from body measurements; tools/sprites/rig_overrides.json corrects them
per character where the automatic guess is wrong (all coordinates in scaled pixels).
Run from the project folder:  python3 tools/sprites/rig_sprites.py [key ...]
"""
import json, os, sys
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage
from skimage.segmentation import watershed
from skimage.filters import sobel
import cv2

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
from measure import body_metrics  # noqa: E402

WORK = os.path.join(HERE, 'work')
OUT = os.path.join(ROOT, 'assets', 'sprites')
K = 4.0            # sheet px per art unit (the old rigs' unit: 64 a frame, ~53 for an adult)
MARGIN = 10        # px of empty canvas around the figure in every cell
INK = np.array([22, 18, 14], np.float64)   # #16120e, the placeholder ink

# Height of each character in art units (field scale: 1 unit = 1 px on the map).
# Mostly the old SVG figures' heights, so the scenes keep their proportions.
HEIGHT = {
    'derrick_child': 43.0, 'derrick_youth': 47.8, 'derrick_lad': 52.0, 'derrick_man': 53.0,
    'mother': 51.0, 'father': 53.5, 'kid_a': 41.0, 'kid_b': 41.0, 'villager': 53.0, 'villager_f': 50.5,
    'baker': 56.0, 'monk': 52.5, 'wat': 47.8, 'gauntley': 55.0, 'gauntley_helm': 57.5, 'man_at_arms': 54.0,
    'edric': 51.0, 'ostry': 55.0, 'hild': 50.0, 'levy': 53.0, 'looter': 53.0, 'jack': 59.5, 'jacob': 56.5,
    'wick': 50.0, 'son_a': 53.0, 'son_b': 56.0, 'son_c': 52.0, 'simon': 52.0, 'dog': 30.0,
}
# Seated figures keep the scale of their standing selves.
SEATED = {'derrick_child_sit': 'derrick_child', 'derrick_man_sit': 'derrick_man', 'jack_kneel': 'jack'}
LABELS = {'head': 1, 'torso': 2, 'arm_l': 3, 'arm_r': 4, 'leg_l': 5, 'leg_r': 6, 'skirt': 7, 'tail': 8,
          'hind_l': 9, 'hind_r': 10}
LEGS = ('leg_l', 'leg_r', 'hind_l', 'hind_r')


def premul_resize(img, size):
    a = np.asarray(img, np.float64) / 255.0
    pm = np.dstack([a[..., :3] * a[..., 3:4], a[..., 3]])
    out = cv2.resize(pm, size, interpolation=cv2.INTER_AREA)
    al = np.clip(out[..., 3], 0, 1)
    rgb = out[..., :3] / np.maximum(al, 1e-4)[..., None]
    return np.dstack([np.clip(rgb, 0, 1), al])


def decontaminate(rgba, solid=0.6):
    """Give every see-through pixel the colour of the nearest solid one. The keyed
    edge pixels keep a trace of the magenta background in their colour; once filtered
    or inpainted from, that trace turns into a purple fringe."""
    a = rgba[..., 3]
    hard = a >= solid
    if not hard.any():
        return rgba
    _, (iy, ix) = ndimage.distance_transform_edt(~hard, return_indices=True)
    out = rgba.copy()
    soft = ~hard
    out[soft, :3] = rgba[iy[soft], ix[soft], :3]
    return out


def tidy_labels(lab, a):
    """Faint edge pixels follow the part their solid neighbour belongs to, and stray
    islands of torso (edge crumbs outside an arm's outline) join the part they touch."""
    solid = (a >= 0.5) & (lab > 0)
    if solid.any():
        _, (iy, ix) = ndimage.distance_transform_edt(~solid, return_indices=True)
        faint = (lab > 0) & ~solid
        lab[faint] = lab[iy[faint], ix[faint]]
    t = lab == LABELS['torso']
    comp, n = ndimage.label(t)
    if n > 1:
        sizes = ndimage.sum(t, comp, range(1, n + 1))
        keep = int(np.argmax(sizes)) + 1
        stray = t & (comp != keep)
        other = (lab > 0) & ~t
        if other.any():
            _, (iy, ix) = ndimage.distance_transform_edt(~other, return_indices=True)
            lab[stray] = lab[iy[stray], ix[stray]]
    return lab


def run_at(mask, y, x):
    """Left/right ends of the opaque run through (x, y), or None."""
    row = mask[y]
    if x < 0 or x >= row.size or not row[x]:
        return None
    l = x
    while l > 0 and row[l - 1]:
        l -= 1
    r = x
    while r < row.size - 1 and row[r + 1]:
        r += 1
    return l, r


def auto_seeds(a, kind):
    m = a > 0.5
    bm = body_metrics(a)
    top, bot, cx = bm['top'], bm['bottom'], int(round(bm['cx']))
    h = bot - top
    seeds = {}
    if kind == 'dog':
        neck = top + int(0.42 * h)
        seeds['head'] = [(cx, top + int(0.22 * h))]
        seeds['torso'] = [(cx, top + int(0.55 * h)), (cx + int(0.25 * h), top + int(0.62 * h))]
        y = bot - int(0.10 * h)
        r = run_at(m, y, cx)
        lx = cx - int(0.10 * h)
        seeds['leg_l'] = [(cx - int(0.12 * h), bot - int(0.08 * h))]
        seeds['leg_r'] = [(cx + int(0.02 * h), bot - int(0.08 * h))]
        return seeds, {'neck': neck, 'top': top, 'bot': bot, 'cx': cx, 'skirt': False, 'hem': top + int(0.7 * h)}
    if kind == 'seated':
        widths = [(run_at(m, y, cx) or (0, -1)) for y in range(top, bot)]
        lo, hi = top + int(0.25 * h), top + int(0.55 * h)
        neck = min(range(lo, hi), key=lambda y: widths[y - top][1] - widths[y - top][0])
        seeds['head'] = [(cx, (top + neck) // 2)]
        seeds['torso'] = [(cx, neck + int(0.2 * h)), (cx, bot - int(0.1 * h))]
        return seeds, {'neck': neck, 'top': top, 'bot': bot, 'cx': cx, 'skirt': False, 'hem': bot}
    # standing person
    widths = {}
    for y in range(top, bot + 1):
        r = run_at(m, y, cx)
        widths[y] = (r[1] - r[0] + 1) if r else 0
    lo, hi = top + int(0.20 * h), top + int(0.42 * h)
    neck = min(range(lo, hi), key=lambda y: widths[y])
    # legs: a gap at the centre line, searching up from the feet
    crotch = None
    y = bot - 2
    gap_rows = 0
    while y > top + 0.5 * h:
        if not m[y, cx]:
            gap_rows += 1
            crotch = y
        elif gap_rows > 3:
            break
        y -= 1
    skirt = crotch is None or (bot - crotch) < 0.12 * h
    seeds['head'] = [(cx, (top + neck) // 2)]
    chest = neck + int(0.16 * h)
    belly = neck + int(0.30 * h)
    seeds['torso'] = [(cx, chest), (cx, belly)]
    # arms: the outermost material at upper-arm and forearm height
    for side, sgn in (('arm_l', -1), ('arm_r', 1)):
        pts = []
        for f in (0.12, 0.26, 0.40):
            yy = neck + int(f * h)
            if f > 0.3 and yy >= (crotch if crotch else bot) - 6:
                continue
            r = run_at(m, yy, cx)
            if r:
                x = r[0] + 5 if sgn < 0 else r[1] - 5
                pts.append((x, yy))
        seeds[side] = pts
    if skirt:
        seeds['skirt'] = [(cx, bot - int(0.15 * h)), (cx, bot - int(0.28 * h))]
        hem = bot - int(0.06 * h)
        # shoes peeping out under the hem
        yy = bot - 3
        r = run_at(m, yy, cx - 4) or run_at(m, yy, cx + 4)
        seeds['leg_l'] = [(cx - int(0.06 * h), bot - 3)] if m[bot - 3, max(0, cx - int(0.06 * h))] else []
        seeds['leg_r'] = [(cx + int(0.06 * h), bot - 3)] if m[bot - 3, min(m.shape[1] - 1, cx + int(0.06 * h))] else []
    else:
        hem = crotch
        y = bot - int(0.08 * h)
        rl = None
        for x in range(cx, 0, -1):
            if m[y, x]:
                rl = run_at(m, y, x)
                break
        rr = None
        for x in range(cx, m.shape[1]):
            if m[y, x]:
                rr = run_at(m, y, x)
                break
        seeds['leg_l'] = [((rl[0] + rl[1]) // 2, y)] if rl else []
        seeds['leg_r'] = [((rr[0] + rr[1]) // 2, y)] if rr else []
        yk = (crotch + bot) // 2
        for side, sgn in (('leg_l', -1), ('leg_r', 1)):
            for x in (range(cx, 0, -1) if sgn < 0 else range(cx, m.shape[1])):
                if m[yk, x]:
                    r = run_at(m, yk, x)
                    seeds[side].append(((r[0] + r[1]) // 2, yk))
                    break
    return seeds, {'neck': neck, 'top': top, 'bot': bot, 'cx': cx, 'skirt': skirt, 'hem': hem}


def poly_mask(shape, pts):
    m = np.zeros(shape, np.uint8)
    cv2.fillPoly(m, [np.array(pts, np.int32)], 1)
    return m.astype(bool)


def segment(rgba, seeds, geo, ov):
    """Geometry first: the arms are the polygons drawn for this character (they take
    whatever the hand holds), the head is above the neck line, legs below the hem
    (split between the two leg seeds along the ink), a robe's skirt below the waist;
    everything else is torso."""
    a = rgba[..., 3]
    H, W = a.shape
    opaque = a > 0.08
    yy, xx = np.mgrid[0:H, 0:W]
    lab = np.where(opaque, LABELS['torso'], 0).astype(np.int32)
    arms = {}
    for arm in ('arm_l', 'arm_r'):
        if ov.get(arm):
            arms[arm] = poly_mask(a.shape, ov[arm]) & opaque
    any_arm = np.zeros_like(opaque)
    for m in arms.values():
        any_arm |= m
    if 'head' in seeds:
        head = opaque & (yy <= geo['neck'] + ov.get('chin', 0)) & ~any_arm
        if ov.get('head_x'):
            head &= (xx >= ov['head_x'][0]) & (xx <= ov['head_x'][1])
        lab[head] = LABELS['head']
    if geo.get('skirt'):
        waist = geo.get('waist', geo['neck'] + 0.42 * (geo['bot'] - geo['neck']))
        lab[opaque & (yy >= waist) & ~any_arm] = LABELS['skirt']
        if geo.get('feet'):
            # the shoes showing under the hem step on their own: one blob per foot,
            # or a single blob split at the centre line
            feet = opaque & (yy >= geo['feet']) & ~any_arm
            comp, n = ndimage.label(feet)
            sizes = ndimage.sum(feet, comp, range(1, n + 1))
            big = [i + 1 for i, sz in enumerate(sizes) if sz >= 12]
            if len(big) >= 2:
                for c in big:
                    cxs = xx[comp == c].mean()
                    lab[comp == c] = LABELS['leg_l'] if cxs < geo['cx'] else LABELS['leg_r']
            else:
                lab[feet & (xx < geo['cx'])] = LABELS['leg_l']
                lab[feet & (xx >= geo['cx'])] = LABELS['leg_r']
    elif 'leg_l' in seeds or 'leg_r' in seeds:
        below = opaque & (yy >= geo['hem']) & ~any_arm
        markers = np.zeros(a.shape, np.int32)
        for leg in ('leg_l', 'leg_r'):
            for (x, y) in seeds.get(leg, []):
                markers[((xx - x) ** 2 + (yy - y) ** 2 <= 9) & below] = LABELS[leg]
        rgb = rgba[..., :3]
        lum = 0.299 * rgb[..., 0] + 0.587 * rgb[..., 1] + 0.114 * rgb[..., 2]
        elev = ndimage.gaussian_filter(1.0 - lum, 0.7) + 0.6 * sobel(lum) + 0.004 * np.abs(xx - geo['cx'])
        legs = watershed(elev, markers, mask=below)
        lab[legs > 0] = legs[legs > 0]
    if 'tail' in ov:
        lab[poly_mask(a.shape, ov['tail']) & opaque] = LABELS['tail']
    if 'legs_poly' in ov:   # explicit leg polygons (the dog's front legs)
        for leg, pts in ov['legs_poly'].items():
            lab[poly_mask(a.shape, pts) & opaque] = LABELS[leg]
    for arm, m in arms.items():
        lab[m] = LABELS[arm]
    for part, x0, y0, x1, y1 in ov.get('boxes', []):   # never takes what an arm holds
        sub = lab[y0:y1, x0:x1]
        sub[(sub > 0) & ~any_arm[y0:y1, x0:x1]] = LABELS[part]
    return lab


def ink_edge(layer, cut_mask, width=1.6):
    """Darken the opaque pixels of `layer` that border `cut_mask` (where a neighbour was
    lifted away), so a moving limb uncovers an inked edge instead of raw paint."""
    a = layer[..., 3]
    near = ndimage.distance_transform_edt(~cut_mask) <= width
    edge = near & (a > 0.3)
    layer[edge, :3] = layer[edge, :3] * 0.25 + (INK / 255.0) * 0.75
    return layer


def build_layers(rgba, lab, geo, kind):
    H, W = lab.shape
    a = rgba[..., 3]
    layers = {}
    present = {p: (lab == i) for p, i in LABELS.items() if (lab == i).sum() > 30}
    yy, xx = np.mgrid[0:H, 0:W]
    for part, sel in present.items():
        # every part overlaps its neighbours by a couple of pixels of the same drawing,
        # so filtering never opens a hairline seam where two parts meet
        grown = ndimage.binary_dilation(sel, iterations=2) & (a > 0.08)
        lay = np.zeros((H, W, 4))
        lay[grown] = rgba[grown]
        layers[part] = lay
    # torso: continue the body under the arms (convex hull of the torso) and under the
    # chin, filled from the torso's own pixels
    if 'torso' in layers:
        t = present['torso']
        hull = cv2.convexHull(np.column_stack(np.nonzero(t))[:, ::-1].astype(np.int32))
        hull_mask = np.zeros((H, W), np.uint8)
        cv2.fillConvexPoly(hull_mask, hull, 1)
        hull_mask = hull_mask.astype(bool)
        neck_band = (yy >= geo['neck'] - 7) & (yy <= geo['neck'] + 2) & present.get('head', np.zeros_like(t))
        # only a band of body under each arm: enough to cover the shoulder seam and the
        # body's side when the arm swings away, not the whole space the arm hangs in
        near_body = ndimage.distance_transform_edt(~t) <= 2.5 * K
        under_arms = hull_mask & near_body & (present.get('arm_l', np.zeros_like(t)) | present.get('arm_r', np.zeros_like(t)))
        fill = (under_arms | neck_band) & ~t
        if fill.any():
            img = (rgba[..., :3] * 255).astype(np.uint8)
            src_ok = t & (a >= 0.6)
            src = img.copy()
            src[~src_ok] = 0
            filled = cv2.inpaint(src, (~src_ok).astype(np.uint8) * 255, 6, cv2.INPAINT_TELEA)
            lay = layers['torso']
            lay[fill, :3] = filled[fill] / 255.0
            lay[fill, 3] = 1.0
            # the neck band keeps the real pixels (it sits under the head anyway)
            lay[neck_band, :3] = rgba[neck_band, :3]
            # the uncovered side of the body gets an ink line where the arm used to be
            arms = (present.get('arm_l', np.zeros_like(t)) | present.get('arm_r', np.zeros_like(t))) & (lay[..., 3] < 0.5)
            layers['torso'] = ink_edge(lay, arms & (a > 0.3), 1.3)
    arms_any = present.get('arm_l', np.zeros((H, W), bool)) | present.get('arm_r', np.zeros((H, W), bool))
    for leg in LEGS:
        if leg not in layers:
            continue
        sel = present[leg]
        lay = layers[leg]
        # a blade or staff drawn across the leg leaves a hole when the arm moves: close it
        closed = ndimage.binary_closing(sel, structure=np.ones((13, 13), bool))
        hole = closed & arms_any & ~sel
        if hole.any():
            img = (rgba[..., :3] * 255).astype(np.uint8)
            src_ok = sel & (a >= 0.6)
            src = img.copy()
            src[~src_ok] = 0
            filled = cv2.inpaint(src, (~src_ok).astype(np.uint8) * 255, 5, cv2.INPAINT_TELEA)
            lay[hole, :3] = filled[hole] / 255.0
            lay[hole, 3] = 1.0
        # continue the leg up under the hem (or the robe, or the dog's chest) by
        # repeating its top rows, so a lifted or swinging leg never shows its cut end
        ys = np.nonzero(sel.any(1))[0]
        if ys.size == 0:
            continue
        y0 = ys.min()
        rows = min(12 if geo['skirt'] else 14, y0)
        src_row = lay[min(y0 + 3, H - 1)].copy()
        for dy in range(1, rows + 1):
            y = y0 - dy
            take = (src_row[:, 3] > 0.5) & (lay[y, :, 3] < 0.5)
            lay[y, take] = src_row[take]
    return layers


def joints(lab, geo, kind):
    """Bone joints in scaled px: where each part pivots."""
    j = {}
    cx, top, bot, neck = geo['cx'], geo['top'], geo['bot'], geo['neck']

    def pts(part):
        ys, xs = np.nonzero(lab == LABELS[part])
        return ys, xs

    j['shadow'] = (cx, bot)
    hem = geo['hem'] if not geo['skirt'] else bot - 0.25 * (bot - top)
    waist = neck + 0.42 * (bot - neck) if kind != 'seated' else bot - 0.2 * (bot - top)
    if kind == 'dog':
        waist = geo['top'] + 0.6 * (bot - top)
    j['body'] = (cx, waist)
    j['upper'] = (cx, waist)
    j['torso'] = (cx, waist)
    ys, xs = pts('head')
    if ys.size:
        low = ys > ys.max() - 8
        j['head'] = (float(np.median(xs[low])), float(min(neck, ys.max())))
    else:
        j['head'] = (cx, neck)
    j['skirt'] = (cx, waist)
    for arm, sgn in (('arm_l', -1), ('arm_r', 1)):
        ys, xs = pts(arm)
        if ys.size == 0:
            continue
        y_top = ys.min()
        band = ys < y_top + 0.18 * (ys.max() - y_top + 1)
        xs_band = xs[band]
        inner = xs_band.max() if sgn < 0 else xs_band.min()
        outer = xs_band.min() if sgn < 0 else xs_band.max()
        sx = inner + 0.35 * (outer - inner)
        j[arm] = (float(sx), float(y_top + 0.35 * abs(outer - inner)))
        if geo.get('s' + arm[-1]):
            j[arm] = tuple(geo['s' + arm[-1]])
        # the hand: lowest stretch of the arm nearest the body line
        j['held_' + arm[-1]] = (float(np.median(xs[ys > ys.max() - 6])), float(ys.max() - 4))
    for leg in LEGS:
        ys, xs = pts(leg)
        if ys.size == 0:
            continue
        y_top = ys.min()
        j[leg] = (float(np.median(xs[ys < y_top + 6])), float(y_top + 2))
    return j


PAPER = (233, 223, 199)     # #e9dfc7, the placeholder portraits' disc
HATCH = (168, 152, 122)     # #a8987a


def write_portrait(key, src, f, geo, head_x, size=256):
    """Head and shoulders in the round frame the dialogue box and HUD expect: a paper
    disc, faint hatching, the figure cut at the disc, an ink ring. Taken from the full
    resolution drawing, not the game-scale one."""
    ss = 4                                   # supersampling for clean edges
    S = size * ss
    top, neck = geo['top'], geo['neck']
    hh = neck - top
    D = 2.6 * hh                             # disc diameter, in canvas px
    disc_top = top - 0.17 * D
    # canvas px -> source px
    x0 = (head_x - D / 2 - MARGIN) / f
    y0 = (disc_top - MARGIN) / f
    side = D / f
    R = 0.4875 * S
    c = S / 2
    crop = src.crop((int(round(x0)), int(round(y0)), int(round(x0 + side)), int(round(y0 + side))))
    fig = crop.resize((int(2 * R), int(2 * R)), Image.LANCZOS)
    disc = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    mask = Image.new('L', (S, S), 0)
    ImageDraw.Draw(mask).ellipse([c - R, c - R, c + R, c + R], fill=255)
    paper = Image.new('RGBA', (S, S), PAPER + (255,))
    d = ImageDraw.Draw(paper)
    step = int(S * 0.055)
    for x in range(-S, 2 * S, step):
        d.line([(x, S), (x + S, 0)], fill=HATCH + (255,), width=max(1, int(S * 0.012)))
    paper.alpha_composite(fig, (int(c - R), int(c - R)))
    disc.paste(paper, (0, 0), mask)
    ring = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    w = int(S * 0.035)
    ImageDraw.Draw(ring).ellipse([c - R, c - R, c + R, c + R],
                                 outline=tuple(int(v) for v in INK) + (255,), width=w)
    disc.alpha_composite(ring)
    disc = disc.resize((size, size), Image.LANCZOS)
    os.makedirs(os.path.join(OUT, 'portrait'), exist_ok=True)
    disc.save(os.path.join(OUT, 'portrait', key + '.png'), optimize=True)


def main(only):
    info = json.load(open(os.path.join(WORK, 'extract.json')))
    ovs = json.load(open(os.path.join(HERE, 'rig_overrides.json'))) if os.path.exists(os.path.join(HERE, 'rig_overrides.json')) else {}
    os.makedirs(os.path.join(OUT, 'rig'), exist_ok=True)
    os.makedirs(os.path.join(OUT, 'char'), exist_ok=True)
    os.makedirs(os.path.join(WORK, 'review'), exist_ok=True)
    rigs_path = os.path.join(OUT, 'rigs.json')
    rigs = json.load(open(rigs_path))['rigs'] if os.path.exists(rigs_path) else {}
    placeholder = json.load(open(os.path.join(ROOT, 'assets', 'placeholder', 'rigs.json')))['rigs']
    for key, inf in info.items():
        if only and key not in only:
            continue
        ov = ovs.get(key, {})
        kind = 'dog' if key == 'dog' else ('seated' if key in SEATED else 'person')
        src = Image.open(os.path.join(WORK, 'cut', key + '.png')).convert('RGBA')
        if key in SEATED:
            base = info[SEATED[key]]
            units = HEIGHT[SEATED[key]] / base['body']['height']   # units per source px
        else:
            units = HEIGHT[key] / inf['body']['height']
        f = units * K
        W0, H0 = src.size
        size = (max(1, int(round(W0 * f))), max(1, int(round(H0 * f))))
        sc = premul_resize(src, size)
        Hs, Ws = sc.shape[:2]
        canvas = np.zeros((Hs + 2 * MARGIN, Ws + 2 * MARGIN, 4))
        canvas[MARGIN:MARGIN + Hs, MARGIN:MARGIN + Ws] = sc
        canvas = decontaminate(canvas)
        seeds, geo = auto_seeds(canvas[..., 3], kind)
        geo.update({k: v for k, v in ov.get('geo', {}).items()})
        for part, pts in ov.get('seeds', {}).items():
            seeds[part] = [tuple(p) for p in pts]
        for part in ov.get('drop', []):
            seeds.pop(part, None)
        if geo.get('skirt') and 'skirt' not in seeds:
            seeds['skirt'] = [(geo['cx'], geo['bot'] - 20)]
        lab = tidy_labels(segment(canvas, seeds, geo, ov), canvas[..., 3])
        layers = build_layers(canvas, lab, geo, kind)
        jts = joints(lab, geo, kind)
        for name, p in ov.get('joints', {}).items():
            jts[name] = tuple(p)
        if kind == 'person':
            write_portrait(key, src, f, geo, jts['head'][0])
        # ---- rig sheet: one full-canvas cell per part (the Rig trims each cell to its pixels)
        order = ['shadow', 'hind_l', 'hind_r', 'tail', 'leg_l', 'leg_r', 'skirt', 'torso', 'arm_l', 'head', 'arm_r']
        parts = [p for p in order if p == 'shadow' or p in layers]
        CH, CW = canvas.shape[:2]
        sheet = np.zeros((CH, CW * len(parts), 4))
        for i, p in enumerate(parts):
            if p == 'shadow':
                sh = np.zeros((CH, CW, 4))
                sx, sy = jts['shadow']
                rx = 0.32 * (np.ptp(np.nonzero((canvas[..., 3] > 0.5).any(0))[0]) + 1) if kind != 'seated' else 0.42 * CW
                rx = min(rx, 15 * K)
                ry = 3.2 * K
                yy, xx = np.mgrid[0:CH, 0:CW]
                e = ((xx - sx) / rx) ** 2 + ((yy - (sy - 0.5 * K)) / ry) ** 2
                al = np.clip(1.0 - e, 0, 1) ** 0.6 * 0.32
                sh[..., :3] = INK / 255.0
                sh[..., 3] = al
                sheet[:, i * CW:(i + 1) * CW] = sh
            else:
                sheet[:, i * CW:(i + 1) * CW] = layers[p]
        out = (np.clip(sheet, 0, 1) * 255).round().astype(np.uint8)
        Image.fromarray(out, 'RGBA').save(os.path.join(OUT, 'rig', key + '.png'), optimize=True)
        flat = (np.clip(canvas, 0, 1) * 255).round().astype(np.uint8)
        Image.fromarray(flat, 'RGBA').save(os.path.join(OUT, 'char', key + '.png'), optimize=True)
        # ---- bones, in art units, frame = the canvas
        fw, fh = CW / K, CH / K

        def u(p):
            return [round(p[0] / K, 2), round(p[1] / K, 2)]

        bones = [['shadow', '', u(jts['shadow'])], ['body', '', u(jts['body'])]]
        for leg in LEGS:
            if leg in layers:
                bones.append([leg, 'body', u(jts[leg])])
        if 'skirt' in layers:
            bones.append(['skirt', 'body', u(jts['skirt'])])
        if 'tail' in layers:
            bones.append(['tail', 'body', u(jts.get('tail', jts['body']))])
        bones.append(['upper', 'body', u(jts['upper'])])
        bones.append(['torso', 'upper', u(jts['torso'])])
        for arm in ('arm_l', 'arm_r'):
            if arm in layers:
                bones.append([arm, 'upper', u(jts[arm])])
        if 'head' in layers:
            bones.append(['head', 'upper', u(jts['head'])])
        cells = {p: i for i, p in enumerate(parts)}
        # which hand holds the weapon (the bigger arm part: it carries the blade), which
        # way the figure "faces" (towards that hand) and how it strikes (a pole held up
        # past the shoulder thrusts, anything else chops)
        area = {a_: int((lab == LABELS[a_]).sum()) for a_ in ('arm_l', 'arm_r') if a_ in layers}
        weapon = ov.get('weapon', '')
        if not weapon and area:
            if len(area) == 1:
                weapon = next(iter(area))
            else:
                weapon = 'arm_l' if area['arm_l'] > 1.3 * area['arm_r'] else 'arm_r'
        faces = ov.get('faces', -1 if (weapon == 'arm_l' or kind == 'dog') else 1)
        strike = ov.get('strike', '')
        if not strike and weapon:
            ys_w = np.nonzero(lab == LABELS[weapon])[0]
            strike = 'thrust' if ys_w.size and ys_w.min() < jts[weapon][1] - 15 else 'chop'
        base = {'sheet': 'sprites/rig/' + key, 'kind': 'frontdog' if kind == 'dog' else 'biped', 'view': 'front',
                'k': K, 'pad': 0, 'cell': [CW, CH], 'frame': [round(fw, 2), round(fh, 2)],
                'origin': u(jts['shadow']), 'cells': cells, 'bones': bones, 'sit': kind == 'seated',
                'mesh': {'skirt': [2, 4], 'leg_l': [1, 2], 'leg_r': [1, 2], 'torso': [2, 2], 'tail': [2, 1]},
                'weapon': weapon, 'faces': faces, 'strike': strike or 'chop', 'sprite': True}
        # battle size as the placeholder had it (big builds and the dog are drawn larger)
        battle = dict(base, s=placeholder.get(key, {}).get('s', 1.75))
        field = dict(base, s=1.0)
        rigs[key] = battle
        rigs[key + '_field'] = field
        # ---- review overlay
        colors = {1: (255, 210, 60), 2: (80, 160, 255), 3: (255, 80, 80), 4: (255, 120, 220), 5: (90, 230, 120),
                  6: (40, 200, 200), 7: (200, 140, 255), 8: (255, 160, 0), 9: (160, 255, 60), 10: (0, 120, 120)}
        rv = Image.fromarray(flat, 'RGBA').convert('RGB')
        ovl = np.zeros((CH, CW, 3), np.uint8)
        for i, c in colors.items():
            ovl[lab == i] = c
        rv = Image.blend(rv, Image.fromarray(ovl), 0.42)
        rv = rv.resize((CW * 2, CH * 2), Image.NEAREST)
        d = ImageDraw.Draw(rv)
        for y in range(0, CH, 10):
            d.line([(0, y * 2), (6 if y % 50 else 14, y * 2)], fill=(255, 255, 255))
            if y % 50 == 0:
                d.text((16, y * 2 - 6), str(y), fill=(255, 255, 255))
        for x in range(0, CW, 10):
            d.line([(x * 2, 0), (x * 2, 6 if x % 50 else 14)], fill=(255, 255, 255))
            if x % 50 == 0:
                d.text((x * 2 + 2, 14), str(x), fill=(255, 255, 255))
        for part, pts in seeds.items():
            for (x, y) in pts:
                d.ellipse([x * 2 - 4, y * 2 - 4, x * 2 + 4, y * 2 + 4], outline=(0, 0, 0), fill=colors[LABELS[part]])
        for name, p in jts.items():
            d.line([(p[0] * 2 - 6, p[1] * 2), (p[0] * 2 + 6, p[1] * 2)], fill=(0, 0, 0), width=2)
            d.line([(p[0] * 2, p[1] * 2 - 6), (p[0] * 2, p[1] * 2 + 6)], fill=(0, 0, 0), width=2)
        d.line([(0, geo['neck'] * 2), (CW * 2, geo['neck'] * 2)], fill=(255, 255, 0))
        d.line([(0, geo['hem'] * 2), (CW * 2, geo['hem'] * 2)], fill=(0, 255, 0))
        d.text((4, CH * 2 - 14), key, fill=(255, 255, 255))
        rv.save(os.path.join(WORK, 'review', key + '.png'))
        print('%-18s %3dx%3d  parts %-52s skirt=%-5s weapon=%s faces=%d %s' % (key, CW, CH, ','.join(parts[1:]), geo['skirt'],
              weapon or '-', faces, strike))
    json.dump({'note': 'sprite rigs (tools/sprites/rig_sprites.py); override rigs of the same name in assets/placeholder/rigs.json',
               'rigs': dict(sorted(rigs.items()))}, open(rigs_path, 'w'), indent=1)


if __name__ == '__main__':
    main(set(sys.argv[1:]))
