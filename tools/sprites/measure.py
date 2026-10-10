"""Body measurements shared by the sprite tools: feet line, body centre and head top,
ignoring thin things held beside the body (spears, staffs) so they don't count as height."""
import numpy as np


def body_metrics(alpha, thresh=0.5):
    m = alpha > thresh
    H, W = m.shape
    ys = np.nonzero(m.any(1))[0]
    bottom = int(ys.max())
    # the feet: centre of the opaque columns in the lowest 6% of the figure
    band = m[max(0, bottom - int(0.06 * (bottom - ys.min() + 1))):bottom + 1]
    cols = np.nonzero(band.any(0))[0]
    cx = float((cols.min() + cols.max()) / 2.0)
    # head top: first row whose run through the centre is reasonably wide
    fig_w = np.nonzero(m.any(0))[0]
    fig_w = fig_w.max() - fig_w.min() + 1
    top = int(ys.min())
    for y in range(int(ys.min()), bottom):
        row = m[y]
        x = int(round(cx))
        if not row[x]:
            continue
        l = x
        while l > 0 and row[l - 1]:
            l -= 1
        r = x
        while r < W - 1 and row[r + 1]:
            r += 1
        if r - l + 1 >= 0.12 * fig_w:
            top = y
            break
    return {'bottom': bottom, 'top': top, 'cx': cx, 'height': bottom - top + 1}
