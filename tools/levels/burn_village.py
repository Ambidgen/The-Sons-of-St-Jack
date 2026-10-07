"""Derive the burned village (Dawn, after the raid) and its ember glow from the idyll painting.
Run from the project folder:  python3 tools/levels/burn_village.py   (needs numpy, scipy, Pillow)"""
import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage
src = 'assets/levels/village_road.png'
im = np.asarray(Image.open(src).convert('RGB'), dtype=np.float32) / 255.0
H, W, _ = im.shape
r, g, b = im[..., 0], im[..., 1], im[..., 2]
mx = im.max(-1); mn = im.min(-1)
sat = np.where(mx > 1e-4, (mx - mn) / np.maximum(mx, 1e-4), 0)
hue = np.zeros_like(mx)
d = np.maximum(mx - mn, 1e-6)
hue = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) * 60
yy, xx = np.mgrid[0:H, 0:W]
road_band = (yy > 300) & (yy < 520)
thatch = (hue > 22) & (hue < 58) & (sat > 0.12) & (sat < 0.55) & (mx > 0.48) & ~road_band
# timber/wood of houses near thatch is charred too: grow the mask a little
thatch = ndimage.binary_opening(thatch, iterations=1)
lab, n = ndimage.label(thatch)
sizes = ndimage.sum(thatch, lab, range(1, n + 1))
objs = ndimage.find_objects(lab)
keep = np.zeros(n + 1, bool)
for i, (sl, sz) in enumerate(zip(objs, sizes)):
    x0, x1, y0, y1 = sl[1].start, sl[1].stop, sl[0].start, sl[0].stop
    # the roofs: the far row of cottages, and the two big roofs in the foreground
    # (not the straw verges, which also read as thatch)
    if sz > 600 and (y1 <= 240 or (2040 <= x0 and x1 <= 2530 and y0 >= 500)):
        keep[i + 1] = True
thatch = keep[lab]
roof = ndimage.binary_dilation(thatch, iterations=6)
soot = ndimage.gaussian_filter(roof.astype(np.float32), 18)
rng = np.random.default_rng(7)
noise = ndimage.gaussian_filter(rng.random((H, W)).astype(np.float32), 1.2)
lum = 0.299 * r + 0.587 * g + 0.114 * b
out = im.copy()
# overall: smoke-greyed, a touch darker
grey = lum[..., None]
out = out * 0.65 + grey * 0.35
out *= 0.92
# soot around burned roofs
out *= (1.0 - 0.45 * np.clip(soot, 0, 1))[..., None]
# charred thatch: near black with the stroke texture kept, ashen highlights
char = (0.10 + 0.22 * lum + 0.06 * noise)[..., None] * np.array([1.0, 0.92, 0.86])
ash = (lum > 0.72)[..., None] * 0.25
burnt = np.clip(char + ash * np.array([0.9, 0.88, 0.85]), 0, 1)
m = roof[..., None].astype(np.float32)
m = ndimage.gaussian_filter(m[..., 0], 1.5)[..., None]
out = out * (1 - m) + burnt * m
out = np.clip(out, 0, 1)
Image.fromarray((out * 255).astype(np.uint8)).save('assets/levels/village_burned.png', optimize=True)
# glow: embers inside the charred roofs, brightest low on the roofs
glow = np.zeros((H, W, 3), np.float32)
ys, xs = np.nonzero(thatch)
idx = rng.choice(len(ys), size=min(260, len(ys)), replace=False)
pts = np.zeros((H, W), np.float32)
pts[ys[idx], xs[idx]] = rng.uniform(0.3, 1.0, len(idx))
e = np.clip(ndimage.gaussian_filter(pts, 1.6) * 14, 0, 1) * 0.7           # coals
e2 = np.clip(ndimage.gaussian_filter(pts, 9.0) * 90, 0, 1) * 0.22          # their glow
under = ndimage.gaussian_filter(thatch.astype(np.float32), 6) * 0.10        # the whole roof smouldering
v = np.clip(e + e2 + under, 0, 0.85)
glow[..., 0] = v * 1.0
glow[..., 1] = v * 0.45
glow[..., 2] = v * 0.12
Image.fromarray((np.clip(glow, 0, 1) * 255).astype(np.uint8)).save('assets/levels/village_embers.png', optimize=True)
print('roof px', int(thatch.sum()), 'components kept', int(keep.sum()))
