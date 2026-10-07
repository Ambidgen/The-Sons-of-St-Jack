#!/usr/bin/env python3
"""Generate ORIGINAL woodcut-style placeholder SVG art for The Sons of St. Jack.

Stdlib only. Deterministic (same input -> same files). Every shape is drawn
from primitives here, so the output is project-owned with no third-party rights.

Style: monochrome ink on parchment, hatched shading, with SELECTIVE colour --
fire, blood, water, leaves and gold are the only things allowed to be coloured
(and Ser Gauntley, the storybook hero, who is the one fully coloured person).

    python3 tools/make_placeholders.py                  # write everything
    python3 tools/make_placeholders.py --only char,icon  # just some folders
    python3 tools/make_placeholders.py --list

Godot does NOT render <text> in SVGs -- never put words in these files.
"""
import argparse
import json
import math
import os
import random

# ---------------------------------------------------------------- palette
INK = "#16120e"
PAPER = "#e9dfc7"
P2 = "#cfc2a2"
P3 = "#a8987a"
P4 = "#6f6350"
P5 = "#3b332a"
BLOOD = "#a3261f"
FIRE = "#e0701f"
FIRE_LT = "#f2b24a"
WATER = "#2f5f8f"
WATER_LT = "#6f9cc4"
LEAF = "#3d6b35"
LEAF_LT = "#5e8f4b"
GOLD = "#c9a227"
STEEL = "#d8d2c2"
HERO_BLUE = "#2f4f8f"
HERO_RED = "#b8322a"
GROUND = {"grass": "#d6c9a6", "mud": "#8b7c63", "snow": "#efeadf", "ash": "#6b6358", "cobble": "#b3a584"}

SW = 2.0  # outline width in viewBox units


class Art:
    """Collects <defs> (clip paths, gradients) while a drawing is built."""

    def __init__(self):
        self.defs = []
        self.n = 0

    def uid(self, prefix):
        self.n += 1
        return f"{prefix}{self.n}"

    def hatch(self, clip_shape, x, y, w, h, spacing=3.0, width=0.9, color=INK, opacity=1.0, angle="d"):
        """Parallel engraving lines inside clip_shape (shape given WITHOUT stroke)."""
        cid = self.uid("c")
        self.defs.append(f'<clipPath id="{cid}">{clip_shape}</clipPath>')
        lines = []
        t = x - h
        while t < x + w + h:
            if angle == "d":      # down-right diagonal
                lines.append(f'<line x1="{t:.1f}" y1="{y}" x2="{t + h:.1f}" y2="{y + h}"/>')
            elif angle == "u":    # up-right diagonal
                lines.append(f'<line x1="{t:.1f}" y1="{y + h}" x2="{t + h:.1f}" y2="{y}"/>')
            t += spacing
        if angle == "h":
            lines = []
            yy = y
            while yy < y + h:
                lines.append(f'<line x1="{x}" y1="{yy:.1f}" x2="{x + w}" y2="{yy:.1f}"/>')
                yy += spacing
        if angle == "v":
            lines = []
            xx = x
            while xx < x + w:
                lines.append(f'<line x1="{xx:.1f}" y1="{y}" x2="{xx:.1f}" y2="{y + h}"/>')
                xx += spacing
        return (f'<g clip-path="url(#{cid})" stroke="{color}" stroke-width="{width}" opacity="{opacity}" '
                f'stroke-linecap="round">{"".join(lines)}</g>')

    def svg(self, width, height, body, viewbox):
        d = f"<defs>{''.join(self.defs)}</defs>" if self.defs else ""
        return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
                f'viewBox="{viewbox}">{d}{body}</svg>\n')


# ---------------------------------------------------------------- primitives
def _st(stroke, w=SW):
    return f' stroke="{INK}" stroke-width="{w}" stroke-linejoin="round" stroke-linecap="round"' if stroke else ""


def circle(cx, cy, r, fill, stroke=True, extra=""):
    return f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="{fill}"{_st(stroke)}{extra}/>'


def ellipse(cx, cy, rx, ry, fill, stroke=True, extra=""):
    return f'<ellipse cx="{cx}" cy="{cy}" rx="{rx}" ry="{ry}" fill="{fill}"{_st(stroke)}{extra}/>'


def rect(x, y, w, h, fill, rx=0, stroke=True, extra=""):
    return f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}"{_st(stroke)}{extra}/>'


def poly(points, fill, stroke=True, extra=""):
    pts = " ".join(f"{x},{y}" for x, y in points)
    return f'<polygon points="{pts}" fill="{fill}"{_st(stroke)}{extra}/>'


def path(d, fill, stroke=True, extra="", w=SW):
    return f'<path d="{d}" fill="{fill}"{_st(stroke, w)}{extra}/>'


def line(x1, y1, x2, y2, color=INK, w=SW, extra=""):
    return (f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{color}" stroke-width="{w}" '
            f'stroke-linecap="round"{extra}/>')


def shadow(cx=32, cy=59, rx=15, ry=3.5):
    return ellipse(cx, cy, rx, ry, INK, False, ' opacity="0.3"')


# ---------------------------------------------------------------- figures
BUILDS = {
    #          head cx,cy,r   torso top,bot  leg bottom  shoulder  hip
    "child": dict(hy=26, hr=8.5, tt=35, tb=48, lb=58, sh=8.5, hip=9),
    "youth": dict(hy=21, hr=8, tt=29.5, tb=46, lb=58, sh=10, hip=9.5),
    "adult": dict(hy=15.5, hr=7.8, tt=24, tb=44, lb=58, sh=12, hip=10.5),
    "slight": dict(hy=15.5, hr=7.5, tt=24, tb=44, lb=58, sh=10, hip=10),
    "big": dict(hy=13.5, hr=8, tt=22, tb=45, lb=59, sh=15, hip=13),
    "tall": dict(hy=10.5, hr=7, tt=18.5, tb=44, lb=59, sh=9.5, hip=8.5),
}


# Parts of a figure, back to front. A flat sprite is these concatenated; a rig
# sheet puts each in its own cell so the game can move them at the joints.
FIG_ORDER = ["shadow", "leg_l", "leg_r", "skirt", "cloak", "torso", "arm_l", "held_l", "head", "arm_r", "held_r"]


def figure_parts(spec, art):
    """Front-facing woodcut person on a 64-unit grid, split into limbs.
    Returns (parts: name -> svg, joints: name -> (x, y)). spec keys: build, garment,
    color, hair, hair_color, head, beard, left, right, tabard, emblem, blood, chain, sit, mood."""
    B = BUILDS[spec.get("build", "adult")]
    cx, hy, hr = 32, B["hy"], B["hr"]
    tt, tb, lb, sh, hip = B["tt"], B["tb"], B["lb"], B["sh"], B["hip"]
    sit = spec.get("sit", False)
    if sit:
        tb += 6
    col = spec.get("color", P3)
    garment = spec.get("garment", "tunic")
    P = {k: [] for k in FIG_ORDER}
    shadow_y = 59 if not sit else 58
    P["shadow"].append(shadow(32, shadow_y, 15 if spec.get("build") != "big" else 19))
    long_skirt = garment in ("robe", "dress", "coat")

    # --- legs / skirt
    hip_x = 4
    if sit:
        hip_x = 6
        P["leg_l"].append(ellipse(cx - 6, tb + 3, 6, 3.5, spec.get("legs", P4)))
        P["leg_r"].append(ellipse(cx + 6, tb + 3, 6, 3.5, spec.get("legs", P4)))
    elif long_skirt:
        hip_x = 5
        hem = lb - 1
        for side, key in ((-1, "leg_l"), (1, "leg_r")):
            # a dark shin, hidden by the hem until the leg swings; then the shoe
            P[key].append(rect(cx + side * 5 - 2.4, tb - 2, 4.8, hem - tb + 1, P5, 1.5, False))
            P[key].append(ellipse(cx + side * 5, lb, 4, 1.8, INK, False))
        skirt = f"M{cx - hip},{tb - 4} L{cx + hip},{tb - 4} L{cx + hip + 4},{hem} L{cx - hip - 4},{hem} Z"
        P["skirt"].append(path(skirt, col))
        P["skirt"].append(art.hatch(path(skirt, "#000", False), cx + 1, tb - 4, hip + 5, hem - tb + 4, 2.6, 0.8))
    else:
        legc = spec.get("legs", P4)
        P["leg_l"].append(rect(cx - 7, tb - 2, 6, lb - tb + 1, legc, 1.5))
        P["leg_l"].append(rect(cx - 7.5, lb - 4, 7, 4.5, INK, 1.5, False))
        P["leg_r"].append(rect(cx + 1, tb - 2, 6, lb - tb + 1, legc, 1.5))
        P["leg_r"].append(rect(cx + 0.5, lb - 4, 7, 4.5, INK, 1.5, False))

    # --- cloak behind the body
    if spec.get("cloak"):
        cl = f"M{cx - sh - 1},{tt + 1} L{cx + sh + 1},{tt + 1} L{cx + sh + 6},{lb - 2} L{cx - sh - 6},{lb - 2} Z"
        P["cloak"].append(path(cl, spec["cloak"]))

    # --- torso
    T = P["torso"]
    top = tt
    bot = tb if not long_skirt else tb - 2
    torso = (f"M{cx - sh},{top + 4} Q{cx - sh},{top} {cx - sh + 5},{top} L{cx + sh - 5},{top} "
             f"Q{cx + sh},{top} {cx + sh},{top + 4} L{cx + hip},{bot} L{cx - hip},{bot} Z")
    if garment == "rags":
        torso = (f"M{cx - sh},{top + 4} Q{cx - sh},{top} {cx - sh + 5},{top} L{cx + sh - 5},{top} "
                 f"Q{cx + sh},{top} {cx + sh},{top + 4} L{cx + hip},{bot} L{cx + hip - 3},{bot - 3} "
                 f"L{cx + 3},{bot + 1} L{cx},{bot - 3} L{cx - 4},{bot + 1} L{cx - hip},{bot - 2} Z")
    T.append(path(torso, col))
    T.append(art.hatch(path(torso, "#000", False), cx + 2, top, sh + 2, bot - top + 2, 2.4, 0.8))
    if garment == "mail":
        for yy in range(int(top) + 4, int(bot) - 1, 3):
            for xx in range(int(cx - sh) + 2, int(cx + sh) - 1, 3):
                T.append(f'<path d="M{xx},{yy} q1.5,1.6 3,0" fill="none" stroke="{INK}" stroke-width="0.6"/>')
    if garment == "gambeson":
        for xx in range(int(cx - sh) + 3, int(cx + sh), 4):
            T.append(line(xx, top + 3, xx, bot - 1, INK, 0.7))
    if garment == "coat":
        T.append(path(f"M{cx - 3},{top} L{cx + 3},{top} L{cx + 2},{bot} L{cx - 2},{bot} Z", PAPER, True, "", 1.2))
        # fur collar
        T.append(path(f"M{cx - sh - 2},{top + 6} Q{cx - sh},{top - 3} {cx},{top + 2} "
                      f"Q{cx + sh},{top - 3} {cx + sh + 2},{top + 6} Q{cx},{top + 5} {cx - sh - 2},{top + 6} Z", P2))
        T.append(art.hatch(path(f"M{cx - sh - 2},{top + 6} Q{cx - sh},{top - 3} {cx},{top + 2} "
                                f"Q{cx + sh},{top - 3} {cx + sh + 2},{top + 6} Z", "#000", False),
                           cx - sh - 2, top - 3, 2 * sh + 4, 10, 1.6, 0.6, INK, 1, "v"))
    if garment == "apron" or spec.get("apron"):
        ap = f"M{cx - 6},{top + 6} L{cx + 6},{top + 6} L{cx + 7},{lb - 3 if long_skirt else bot + 4} L{cx - 7},{lb - 3 if long_skirt else bot + 4} Z"
        T.append(path(ap, PAPER, True, "", 1.3))
    if garment == "rags":
        T.append(rect(cx - sh + 3, top + 8, 5, 5, P2, 0, True, ' stroke-width="1"'))
        T.append(rect(cx + 2, top + 12, 4, 6, P5, 0, True, ' stroke-width="1"'))
    if spec.get("tabard"):
        tc = spec["tabard"]
        tab = f"M{cx - 6},{top} L{cx + 6},{top} L{cx + 7},{bot + 3} L{cx - 7},{bot + 3} Z"
        T.append(path(tab, tc))
        dev = spec.get("device")
        if dev == "sun":
            T.append(circle(cx, top + 9, 3, GOLD, True, ' stroke-width="1"'))
            for a in range(0, 360, 45):
                r1, r2 = 3.8, 5.6
                T.append(line(cx + r1 * math.cos(math.radians(a)), top + 9 + r1 * math.sin(math.radians(a)),
                              cx + r2 * math.cos(math.radians(a)), top + 9 + r2 * math.sin(math.radians(a)), GOLD, 1))
    if spec.get("belt", True) and garment not in ("robe", "coat", "dress"):
        by = top + (bot - top) * 0.62
        T.append(rect(cx - hip - 0.5, by, 2 * hip + 1, 2.6, spec.get("belt_color", INK), 0, False))
    if garment == "robe":
        T.append(line(cx - hip + 1, top + (bot - top) * 0.55, cx + hip - 1, top + (bot - top) * 0.55, P2, 1.6))
    if spec.get("emblem"):     # the Sons: a gold coin pierced by a nail
        ex, ey = cx - sh + 4, top + 7
        T.append(circle(ex, ey, 2.6, GOLD, True, ' stroke-width="0.9"'))
        T.append(line(ex - 3.5, ey - 3.5, ex + 3.5, ey + 3.5, INK, 1.1))
    if spec.get("chain"):
        T.append(path(f"M{cx - 7},{top + 1} Q{cx},{top + 12} {cx + 7},{top + 1}", "none", False,
                      f' stroke="{GOLD}" stroke-width="1.8" stroke-dasharray="1.4 1"'))
        T.append(circle(cx, top + 10, 2.2, GOLD, True, ' stroke-width="0.9"'))
    if spec.get("belt_item") == "wooden_sword":
        T.append(line(cx - hip + 1, top + (bot - top) * 0.5, cx - hip - 5, bot + 7, P3, 3.2))
        T.append(line(cx - hip - 1.5, top + (bot - top) * 0.62, cx - hip + 3, top + (bot - top) * 0.72, INK, 1.4))
    if spec.get("blood"):
        rng = random.Random(spec.get("blood"))
        for _ in range(5):
            T.append(circle(cx + rng.uniform(-sh, sh), rng.uniform(top + 2, bot), rng.uniform(0.6, 1.6), BLOOD, False))

    # --- arms (sleeves) + hands, and whatever they hold (its own part: a wrist)
    arm_len = (bot - top) * (0.78 if not sit else 0.6)
    sleeve = spec.get("sleeve", col)
    for side, key, hand in ((-1, "arm_l", "left"), (1, "arm_r", "right")):
        ax = cx + side * (sh + 1.5) - 3.2
        P[key].append(rect(ax, top + 1, 6.4, arm_len, sleeve, 3))
        P[key].append(circle(cx + side * (sh + 1.5), top + arm_len + 1.5, 2.6, PAPER, True, ' stroke-width="1.4"'))
        P["held" + key[3:]].append(held(spec.get(hand), cx + side * (sh + 1.5), top + arm_len + 1.5, art, side))

    # --- head
    H = P["head"]
    H.append(rect(cx - 2.5, hy + hr - 3, 5, 5, PAPER, 0, True, ' stroke-width="1.4"'))
    head_gear = spec.get("head")
    if head_gear == "hood" or head_gear == "hood_down":
        hc = spec.get("hood_color", col)
        H.append(path(f"M{cx - hr - 3},{hy + hr + 3} Q{cx - hr - 4},{hy - hr - 3} {cx},{hy - hr - 3} "
                      f"Q{cx + hr + 4},{hy - hr - 3} {cx + hr + 3},{hy + hr + 3} Z", hc))
    H.append(circle(cx, hy, hr, PAPER))
    H.append(art.hatch(circle(cx, hy, hr, "#000", False), cx + hr * 0.5, hy - hr, hr, 2 * hr, 2.0, 0.45, INK, 0.5))
    hair = spec.get("hair", "short")
    hcol = spec.get("hair_color", INK)
    if head_gear not in ("hood", "helm_plume", "helm", "coif", "kerchief"):
        if hair in ("short", "shaggy", "long", "slick"):
            H.append(path(f"M{cx - hr - 0.6},{hy + 1} Q{cx - hr - 1},{hy - hr - 2.5} {cx},{hy - hr - 1.6} "
                          f"Q{cx + hr + 1},{hy - hr - 2.5} {cx + hr + 0.6},{hy + 1} "
                          f"L{cx + hr - 1.8},{hy - 2.5} Q{cx},{hy - hr + 1.2} {cx - hr + 1.8},{hy - 2.5} Z", hcol, True, "", 1.2))
            H.append(line(cx - 3, hy - hr - 0.4, cx + 1, hy - hr - 1.2, PAPER, 0.7, ' opacity="0.7"'))
        if hair == "shaggy":
            H.append(poly([(cx - hr + 1, hy - 3), (cx - 3, hy - 1), (cx - 1, hy - 4), (cx + 2, hy - 1),
                           (cx + 4, hy - 4), (cx + hr - 1, hy - 2), (cx + hr - 1, hy - 5), (cx - hr + 1, hy - 5)], hcol, False))
        if hair == "long":
            H.append(path(f"M{cx - hr - 0.6},{hy} L{cx - hr - 2},{hy + hr + 4} L{cx - hr + 2.5},{hy + hr + 2} Z", hcol, True, "", 1))
            H.append(path(f"M{cx + hr + 0.6},{hy} L{cx + hr + 2},{hy + hr + 4} L{cx + hr - 2.5},{hy + hr + 2} Z", hcol, True, "", 1))
        if hair == "tonsure":
            H.append(path(f"M{cx - hr - 0.3},{hy + 1} Q{cx - hr},{hy - 5} {cx - 4},{hy - hr + 1} L{cx - 3},{hy - 3} Z", hcol, False))
            H.append(path(f"M{cx + hr + 0.3},{hy + 1} Q{cx + hr},{hy - 5} {cx + 4},{hy - hr + 1} L{cx + 3},{hy - 3} Z", hcol, False))
        if hair == "bald":
            H.append(path(f"M{cx - hr + 0.5},{hy + 2} Q{cx - hr},{hy - 2} {cx - hr + 2},{hy - 3}", "none", True, "", 1.4))
            H.append(path(f"M{cx + hr - 0.5},{hy + 2} Q{cx + hr},{hy - 2} {cx + hr - 2},{hy - 3}", "none", True, "", 1.4))
    # face
    mood = spec.get("mood", "plain")
    ey = hy + (0.8 if head_gear != "helm_plume" else 1.2)
    H.append(circle(cx - 3, ey, 1.05, INK, False))
    H.append(circle(cx + 3, ey, 1.05, INK, False))
    if mood == "stern":
        H.append(line(cx - 5, ey - 2.6, cx - 1.5, ey - 1.6, INK, 1.1))
        H.append(line(cx + 5, ey - 2.6, cx + 1.5, ey - 1.6, INK, 1.1))
    elif mood == "sad":
        H.append(line(cx - 5, ey - 1.6, cx - 1.6, ey - 2.6, INK, 1))
        H.append(line(cx + 5, ey - 1.6, cx + 1.6, ey - 2.6, INK, 1))
    elif mood == "kind":
        H.append(path(f"M{cx - 5},{ey - 2.2} q1.7,-1.2 3.4,0", "none", True, "", 0.9))
        H.append(path(f"M{cx + 1.6},{ey - 2.2} q1.7,-1.2 3.4,0", "none", True, "", 0.9))
    elif mood == "grin":
        H.append(path(f"M{cx - 5},{ey - 2.0} q1.7,-1.4 3.4,0", "none", True, "", 0.9))
        H.append(path(f"M{cx + 1.6},{ey - 2.0} q1.7,-1.4 3.4,0", "none", True, "", 0.9))
    elif mood == "sly":
        H.append(line(cx - 5, ey - 1.8, cx - 1.5, ey - 2.2, INK, 1))
        H.append(line(cx + 5, ey - 2.8, cx + 1.5, ey - 1.8, INK, 1))
    mouth = {"kind": f"M{cx - 2.2},{hy + 4.4} q2.2,1.6 4.4,0", "sly": f"M{cx - 2.4},{hy + 4.8} q2.8,0.6 4.8,-1",
             "sad": f"M{cx - 2},{hy + 5.2} q2,-1.3 4,0"}.get(mood, f"M{cx - 1.8},{hy + 4.8} L{cx + 1.8},{hy + 4.8}")
    H.append(path(mouth, "none", True, "", 1))
    beard = spec.get("beard")
    if beard:
        bc = INK if beard is True else beard
        H.append(path(f"M{cx - hr + 1},{hy + 1} Q{cx - hr + 1},{hy + hr + 4} {cx},{hy + hr + 4.5} "
                      f"Q{cx + hr - 1},{hy + hr + 4} {cx + hr - 1},{hy + 1} Q{cx + 3},{hy + 6.5} {cx},{hy + 6} "
                      f"Q{cx - 3},{hy + 6.5} {cx - hr + 1},{hy + 1} Z", bc, True, "", 1))
        H.append(path(f"M{cx - 2.2},{hy + 4.4} L{cx + 2.2},{hy + 4.4}", "none", False,
                      f' stroke="{PAPER}" stroke-width="0.9"'))
    if mood == "grin":   # a wide smile with something strange in the teeth
        H.append(path(f"M{cx - 3.4},{hy + 3.6} Q{cx},{hy + 7.4} {cx + 3.4},{hy + 3.6} Z", PAPER, True, "", 0.9))
        H.append(line(cx - 3.0, hy + 4.3, cx + 3.0, hy + 4.3, INK, 0.5))
        H.append(rect(cx + 0.6, hy + 3.7, 1.3, 1.4, GOLD, 0, False))
    if spec.get("stubble"):
        for i in range(9):
            a = math.radians(20 + i * 16)
            H.append(circle(cx + (hr - 2) * math.cos(a), hy + 1.5 + (hr - 3) * math.sin(a), 0.45, INK, False))
    # headgear
    if head_gear in ("helm_plume", "helm"):
        H.append(path(f"M{cx - hr - 1},{hy + 1} Q{cx - hr - 1},{hy - hr - 3} {cx},{hy - hr - 3} "
                      f"Q{cx + hr + 1},{hy - hr - 3} {cx + hr + 1},{hy + 1} L{cx + hr - 1.2},{hy - 1.5} "
                      f"L{cx - hr + 1.2},{hy - 1.5} Z", STEEL))
        H.append(rect(cx - 1, hy - 2, 2, 5, STEEL, 0, True, ' stroke-width="1"'))
        H.append(art.hatch(path(f"M{cx},{hy - hr - 3} Q{cx + hr + 1},{hy - hr - 3} {cx + hr + 1},{hy + 1} "
                                f"L{cx},{hy - 1.5} Z", "#000", False), cx, hy - hr - 3, hr + 2, hr + 4, 1.7, 0.6))
        if head_gear == "helm_plume":
            pc = spec.get("plume", HERO_RED)
            H.append(path(f"M{cx},{hy - hr - 3} Q{cx + 3},{hy - hr - 12} {cx + 11},{hy - hr - 9} "
                          f"Q{cx + 5},{hy - hr - 7} {cx + 3},{hy - hr - 2} Z", pc, True, "", 1.4))
    if head_gear == "coif":
        H.append(path(f"M{cx - hr - 1.5},{hy + hr + 2} L{cx - hr - 1.5},{hy - 1} Q{cx - hr - 1.5},{hy - hr - 2.5} "
                      f"{cx},{hy - hr - 2.5} Q{cx + hr + 1.5},{hy - hr - 2.5} {cx + hr + 1.5},{hy - 1} "
                      f"L{cx + hr + 1.5},{hy + hr + 2} L{cx + hr - 2},{hy + hr + 2} L{cx + hr - 2},{hy - 1} "
                      f"Q{cx},{hy - hr + 2.5} {cx - hr + 2},{hy - 1} L{cx - hr + 2},{hy + hr + 2} Z", P2))
        H.append(art.hatch(path(f"M{cx - hr - 1.5},{hy + hr + 2} L{cx - hr - 1.5},{hy - 1} Q{cx - hr - 1.5},{hy - hr - 2.5} "
                                f"{cx},{hy - hr - 2.5} Q{cx + hr + 1.5},{hy - hr - 2.5} {cx + hr + 1.5},{hy - 1} "
                                f"L{cx + hr + 1.5},{hy + hr + 2} Z", "#000", False),
                           cx - hr - 2, hy - hr - 3, 2 * hr + 4, 2 * hr + 6, 1.5, 0.5, INK, 0.9, "h"))
    if head_gear == "kerchief":
        kc = spec.get("kerchief", PAPER)
        H.append(path(f"M{cx - hr - 1},{hy + 2} Q{cx - hr - 1},{hy - hr - 2.5} {cx},{hy - hr - 2.5} "
                      f"Q{cx + hr + 1},{hy - hr - 2.5} {cx + hr + 1},{hy + 2} L{cx + hr - 1.5},{hy - 2} "
                      f"Q{cx},{hy - hr + 1} {cx - hr + 1.5},{hy - 2} Z", kc))
        H.append(path(f"M{cx + hr},{hy} L{cx + hr + 4},{hy + 5} L{cx + hr + 1},{hy + 6} Z", kc, True, "", 1))
    if head_gear == "cap":
        H.append(path(f"M{cx - hr},{hy - 2} Q{cx - hr},{hy - hr - 3.5} {cx + 1},{hy - hr - 3} "
                      f"Q{cx + hr + 2},{hy - hr - 2} {cx + hr},{hy - 2} Z", spec.get("cap_color", P4)))
    if head_gear == "kettle":
        H.append(path(f"M{cx - hr - 4},{hy - 2} L{cx + hr + 4},{hy - 2} L{cx + hr},{hy - 4} "
                      f"Q{cx},{hy - hr - 6} {cx - hr},{hy - 4} Z", STEEL))
    if head_gear == "hood":
        hc = spec.get("hood_color", col)
        H.append(path(f"M{cx - hr - 2},{hy + 3} Q{cx - hr - 3},{hy - hr - 3} {cx},{hy - hr - 3} "
                      f"Q{cx + hr + 3},{hy - hr - 3} {cx + hr + 2},{hy + 3} L{cx + hr - 1.5},{hy + 1} "
                      f"Q{cx + hr - 2},{hy - hr + 1} {cx},{hy - hr + 1.5} Q{cx - hr + 2},{hy - hr + 1} "
                      f"{cx - hr + 1.5},{hy + 1} Z", hc))

    joints = {
        "shadow": (32, shadow_y), "pelvis": (cx, tb), "skirt": (cx, tb - 4), "cloak": (cx, tt + 1),
        "hip_l": (cx - hip_x, tb - 2), "hip_r": (cx + hip_x, tb - 2),
        "shoulder_l": (cx - sh - 1.5, top + 3), "shoulder_r": (cx + sh + 1.5, top + 3),
        "neck": (cx, hy + hr - 1),
        "hand_l": (cx - sh - 1.5, top + arm_len + 1.5), "hand_r": (cx + sh + 1.5, top + arm_len + 1.5),
    }
    return {k: "".join(v) for k, v in P.items()}, joints


def figure(spec, art):
    """The whole figure as one drawing (portraits, riders, title art, HUD thumbnails)."""
    parts, _ = figure_parts(spec, art)
    return "".join(parts[k] for k in FIG_ORDER)


def biped_bones(j, sit=False):
    """Bone tree for a person: [name, parent, pivot]. Children draw after (over) parents,
    in list order -- so this is also the back-to-front order of the parts."""
    return [["shadow", "", j["shadow"]], ["body", "", j["pelvis"]],
            ["leg_l", "body", j["hip_l"]], ["leg_r", "body", j["hip_r"]], ["skirt", "body", j["skirt"]],
            ["upper", "body", j["pelvis"]], ["cloak", "upper", j["cloak"]], ["torso", "upper", j["pelvis"]],
            ["arm_l", "upper", j["shoulder_l"]], ["held_l", "arm_l", j["hand_l"]], ["head", "upper", j["neck"]],
            ["arm_r", "upper", j["shoulder_r"]], ["held_r", "arm_r", j["hand_r"]]]


def held(kind, x, y, art, side):
    if not kind:
        return ""
    o = []
    if kind == "wooden_sword":
        o += [line(x, y, x + side * 2, y - 17, P3, 3.4), line(x, y, x + side * 2, y - 17, INK, 0.8, ' opacity="0.6"'),
              line(x - 3, y - 3, x + 3, y - 3, INK, 1.8)]
    elif kind == "stick":
        o += [line(x, y + 4, x + side * 3, y - 22, P4, 2.8), poly([(x + side * 3 - 1.5, y - 22), (x + side * 3 + 1.5, y - 22),
                                                                   (x + side * 4, y - 25), (x + side * 2.5, y - 23.5)], P4, True, ' stroke-width="0.9"')]
    elif kind == "sword":
        o += [poly([(x - 1.4, y - 3), (x + 1.4, y - 3), (x + 1, y - 24), (x, y - 27), (x - 1, y - 24)], STEEL, True, ' stroke-width="1.2"'),
              line(x - 4, y - 3, x + 4, y - 3, INK, 2), line(x, y - 2, x, y + 2, P5, 2)]
    elif kind == "big_blade":
        o += [poly([(x - 3, y - 4), (x + 3, y - 4), (x + 3.4, y - 34), (x - 3.4, y - 34)], STEEL, True, ' stroke-width="1.4"'),
              line(x - 1, y - 8, x - 1, y - 32, INK, 0.7), line(x - 6, y - 4, x + 6, y - 4, INK, 2.4),
              line(x, y - 3, x, y + 5, P5, 2.6)]
    elif kind == "spear":
        o += [line(x, y + 12, x, y - 38, P4, 2), poly([(x - 2, y - 38), (x + 2, y - 38), (x, y - 46)], STEEL, True, ' stroke-width="1"')]
    elif kind == "pitchfork":
        o += [line(x, y + 12, x, y - 30, P3, 2), path(f"M{x - 4},{y - 38} L{x - 4},{y - 30} L{x + 4},{y - 30} L{x + 4},{y - 38} M{x},{y - 30} L{x},{y - 38}",
                                                      "none", True, "", 1.3)]
    elif kind == "axe":
        o += [line(x, y + 4, x, y - 20, P3, 2.4), path(f"M{x},{y - 18} Q{x + side * 9},{y - 22} {x + side * 8},{y - 12} Z", STEEL, True, "", 1.3)]
    elif kind == "knife":
        o += [poly([(x - 1, y - 1), (x + 1, y - 1), (x + 0.6, y - 9), (x, y - 11)], STEEL, True, ' stroke-width="0.9"'),
              line(x, y, x, y + 3, P5, 2)]
    elif kind == "torch":
        o += [line(x, y + 4, x, y - 12, P4, 2.4), path(f"M{x - 3},{y - 12} Q{x - 4},{y - 18} {x},{y - 24} Q{x + 4},{y - 18} {x + 3},{y - 12} Z", FIRE, True, "", 1),
              path(f"M{x - 1.2},{y - 13} Q{x},{y - 18} {x + 1.2},{y - 13} Z", FIRE_LT, False)]
    elif kind == "lantern":
        o += [line(x, y, x, y + 3, INK, 1), rect(x - 3, y + 3, 6, 7, FIRE_LT, 1, True, ' stroke-width="1.2"')]
    elif kind == "rag_hand":
        o += [path(f"M{x - 3},{y - 3} L{x + 4},{y - 4} L{x + 3},{y + 3} L{x - 4},{y + 2} Z", BLOOD, True, "", 1.1)]
    elif kind == "ledger":
        o += [rect(x - 4, y - 5, 8, 10, P5, 1, True, ' stroke-width="1.2"'), line(x - 4, y - 1, x + 4, y - 1, GOLD, 1.2)]
    elif kind == "bowl":
        o += [path(f"M{x - 5},{y - 3} Q{x},{y + 4} {x + 5},{y - 3} Z", P3, True, "", 1.3)]
    elif kind == "shield":
        c = HERO_BLUE
        o += [path(f"M{x - 7},{y - 13} L{x + 7},{y - 13} L{x + 7},{y - 4} Q{x + 7},{y + 5} {x},{y + 9} Q{x - 7},{y + 5} {x - 7},{y - 4} Z", c, True, "", 1.6),
              circle(x, y - 5, 2.8, GOLD, True, ' stroke-width="0.9"')]
    elif kind == "buckler":
        o += [circle(x, y - 2, 6, P3, True), circle(x, y - 2, 2, STEEL, True, ' stroke-width="1"')]
    elif kind == "bow":
        o += [path(f"M{x + side * 2},{y - 24} Q{x + side * 9},{y - 6} {x + side * 2},{y + 12}", "none", True, "", 1.6),
              line(x + side * 2, y - 24, x + side * 2, y + 12, P2, 0.7)]
    return "".join(o)


def figure_svg(spec, size):
    art = Art()
    body = figure(spec, art)
    return art.svg(size, size, body, "0 0 64 64")


def portrait_svg(spec, size=160):
    art = Art()
    B = BUILDS[spec.get("build", "adult")]
    hy = B["hy"]
    vb_y = hy - 14
    body = figure(spec, art)
    disc = circle(32, hy + 3, 19.5, PAPER, False)
    ring = art.hatch(circle(32, hy + 3, 19.5, "#000", False), 12, hy - 17, 40, 40, 2.2, 0.6, P3, 1, "u")
    edge = circle(32, hy + 3, 19.5, "none", True, ' stroke-width="1.6"')
    return art.svg(size, size, disc + ring + body + edge, f"12 {vb_y} 40 40")


# ---------------------------------------------------------------- animals
RIDER_PARTS = ["cloak", "torso", "arm_l", "held_l", "head", "arm_r", "held_r"]   # a rider's legs are hidden by the horse


def horse_parts(art, rider=None):
    """Side view horse facing right on a 96x80 grid, split into limbs, with an optional
    rider (a figure spec) cut into parts of its own. Returns (order, parts, bones)."""
    P = {"shadow": ellipse(46, 76, 30, 3.5, INK, False, ' opacity="0.3"')}
    legs = []
    for name, lx, back in (("leg_hf", 28, True), ("leg_hn", 38, False), ("leg_ff", 62, True), ("leg_fn", 70, False)):
        P[name] = rect(lx, 46, 4.6, 28, P5 if back else INK, 1.5) + rect(lx - 0.8, 71, 6.2, 4, INK, 1, False)
        legs.append([name, "body", (lx + 2.3, 47)])
    P["tail"] = path("M24,34 Q12,40 16,62 Q20,48 26,42 Z", INK)
    body_d = "M22,40 Q20,28 34,27 L60,27 Q72,26 74,34 L74,44 Q70,50 60,50 L32,50 Q22,50 22,40 Z"
    P["torso"] = path(body_d, INK) + art.hatch(path(body_d, "#000", False), 22, 27, 52, 23, 3.0, 0.8, PAPER, 0.45, "u")
    head_d = "M66,32 L74,14 Q78,8 84,12 L92,22 Q94,27 89,28 L82,26 L76,40 Z"
    P["head"] = (path(head_d, INK) + path("M68,30 L75,12 L70,12 L64,26 Z", P5)          # mane
                 + circle(83, 17, 1.2, PAPER, False) + line(88, 25, 76, 20, P3, 1))       # eye, bridle
    order = ["shadow"] + [l[0] for l in legs] + ["tail", "torso", "head"]
    bones = [["shadow", "", (46, 76)], ["body", "", (48, 40)]] + legs + \
            [["tail", "body", (24, 35)], ["torso", "body", (48, 40)], ["head", "body", (70, 33)]]
    if rider:
        rspec = dict(rider)
        rparts, rj = figure_parts(rspec, art)
        cid = art.uid("r")
        art.defs.append(f'<clipPath id="{cid}"><rect x="0" y="0" width="64" height="{BUILDS[rspec.get("build", "adult")]["tb"] + 2}"/></clipPath>')
        seat = lambda p: (round(24 + 0.9 * p[0], 2), round(-8 + 0.9 * p[1], 2))
        bones.append(["rider", "body", seat(rj["pelvis"])])
        for k in RIDER_PARTS:
            if rparts[k]:
                P["rider_" + k] = f'<g transform="translate(24,-8) scale(0.9)"><g clip-path="url(#{cid})">{rparts[k]}</g></g>'
                order.append("rider_" + k)
                pivot = {"cloak": "cloak", "torso": "pelvis", "arm_l": "shoulder_l", "head": "neck", "arm_r": "shoulder_r",
                         "held_l": "hand_l", "held_r": "hand_r"}[k]
                parent = {"held_l": "rider_arm_l", "held_r": "rider_arm_r"}.get(k, "rider")
                bones.append(["rider_" + k, parent, seat(rj[pivot])])
        P["rider_leg"] = path("M40,30 Q46,46 52,30 Z", rspec.get("color", P3)) + rect(46, 40, 5, 6, INK, 1, False)
        order.append("rider_leg")
        bones.append(["rider_leg", "rider", (46, 31)])
    return order, P, bones


def horse(art, rider=None):
    order, parts, _ = horse_parts(art, rider)
    return "".join(parts[k] for k in order)


def horse_svg(rider=None, px=128):
    art = Art()
    return art.svg(px, int(px * 80 / 96), horse(art, rider), "0 0 96 80")


def hound_parts(art, wolf=False):
    """Side-view canine facing right, 64 grid. The dog is starved; the wolf is shaggy."""
    P = {"shadow": shadow(32, 58, 22, 3.5)}
    col = P4 if wolf else P3
    legs = []
    for name, lx, back in (("leg_hf", 16, True), ("leg_hn", 22, False), ("leg_ff", 42, True), ("leg_fn", 48, False)):
        P[name] = rect(lx, 40, 3.4, 17, P5 if back else col, 1.2, True, ' stroke-width="1.4"')
        legs.append([name, "body", (lx + 1.7, 41)])
    P["tail"] = path("M12,34 Q2,28 4,18 Q8,28 16,30 Z", col, True, "", 1.6)
    body = ("M12,34 Q12,26 22,26 L42,26 Q52,24 54,32 L52,42 Q44,44 40,40 L26,40 Q20,46 14,42 Z" if not wolf else
            "M11,34 Q10,23 22,23 L42,23 Q54,21 55,32 L53,44 Q46,46 40,42 L26,42 Q18,48 12,43 Z")
    t = [path(body, col)]
    if wolf:
        t.append(art.hatch(path(body, "#000", False), 10, 20, 46, 28, 2.0, 0.7, INK, 0.9, "d"))
        for i in range(8):
            t.append(line(16 + i * 4.5, 23 - (i % 2), 18 + i * 4.5, 19 - (i % 2), INK, 1))
    else:
        for i in range(5):  # ribs
            t.append(path(f"M{25 + i * 3.4},{27} q-1.5,6 0,12", "none", True, "", 0.9))
    P["torso"] = "".join(t)
    head = ("M48,30 L54,20 L55,13 L58,19 L62,20 L64,28 L60,33 L52,35 Z" if not wolf else
            "M47,28 L53,16 L54,8 L58,15 L63,17 L64,26 L60,32 L50,35 Z")
    h = [path(head, col)]
    if wolf:
        h.append(art.hatch(path(head, "#000", False), 46, 8, 20, 28, 2.0, 0.6, INK, 0.9))
    h.append(circle(58, 22 if not wolf else 20, 1.4, FIRE_LT if wolf else INK, False))
    h.append(path("M60,30 L62,33 L58,33 Z" if not wolf else "M59,29 L63,32 L57,32 Z", PAPER, False))
    P["head"] = "".join(h)
    order = ["shadow"] + [l[0] for l in legs] + ["tail", "torso", "head"]
    bones = [["shadow", "", (32, 58)], ["body", "", (32, 36)]] + legs + \
            [["tail", "body", (13, 32)], ["torso", "body", (32, 36)], ["head", "body", (50, 31)]]
    return order, P, bones


def hound(art, wolf=False):
    order, parts, _ = hound_parts(art, wolf)
    return "".join(parts[k] for k in order)


def hound_svg(wolf, px):
    art = Art()
    return art.svg(px, px, hound(art, wolf), "0 0 64 64")


def crow_parts(art):
    P = {"shadow": ellipse(32, 52, 12, 2, INK, False, ' opacity="0.25"'),
         "torso": path("M18,40 Q20,28 32,28 Q40,28 44,24 L50,26 L44,30 Q46,40 36,44 L24,44 L14,50 Z", INK)
         + circle(44, 25, 1, PAPER, False),
         "legs": line(28, 44, 26, 52, INK, 1.4) + line(32, 44, 33, 52, INK, 1.4)}
    order = ["shadow", "torso", "legs"]
    bones = [["shadow", "", (32, 52)], ["body", "", (30, 44)], ["torso", "body", (30, 44)], ["legs", "", (30, 44)]]
    return order, P, bones


def crow_svg(px=64):
    art = Art()
    order, parts, _ = crow_parts(art)
    return art.svg(px, px, "".join(parts[k] for k in ("torso", "legs")), "0 0 64 64")


# ---------------------------------------------------------------- rigs
# A rig sheet is one SVG strip: each body part in its own cell, drawn in the same
# frame coordinates as the flat sprite, so the game can rebuild the figure as a set
# of textured meshes and move them at the joints. rigs.json describes every sheet.
RIGS = {}       # art key ("char/derrick_man_field") -> rig description for rigs.json


def rig_svg(name, kind, build, frame, px, pad=16, extra=None):
    """build(art) -> (order, parts, bones). Writes the description into RIGS and returns the SVG."""
    art = Art()
    order, parts, bones = build(art)
    fw, fh = frame
    s = px / fw
    names = [n for n in order if parts.get(n)]
    cw_px = math.ceil((fw + 2 * pad) * s - 1e-6)
    ch_px = math.ceil((fh + 2 * pad) * s - 1e-6)
    cw, ch = cw_px / s, ch_px / s
    cid = art.uid("cell")
    art.defs.append(f'<clipPath id="{cid}"><rect x="{-pad}" y="{-pad}" width="{cw:.4f}" height="{ch:.4f}"/></clipPath>')
    body = "".join(f'<g transform="translate({i * cw + pad:.4f},{pad})"><g clip-path="url(#{cid})">{parts[n]}</g></g>'
                   for i, n in enumerate(names))
    desc = {"sheet": "rig/" + name, "kind": kind, "s": round(s, 6), "pad": pad, "cell": [cw_px, ch_px],
            "frame": [fw, fh], "cells": {n: i for i, n in enumerate(names)},
            "bones": [[b[0], b[1], [round(b[2][0], 2), round(b[2][1], 2)]] for b in bones]}
    desc.update(extra or {})
    RIGS[name] = desc
    return art.svg(len(names) * cw_px, ch_px, body, f"0 0 {len(names) * cw:.4f} {ch:.4f}")


def figure_rig(name, spec, px):
    def build(art):
        parts, j = figure_parts(spec, art)
        return FIG_ORDER, parts, biped_bones(j)
    return rig_svg(name, "biped", build, (64, 64), px, 16, {"sit": bool(spec.get("sit")),
                   "mesh": {"skirt": [2, 3], "cloak": [2, 3], "leg_l": [1, 2], "leg_r": [1, 2]}})


# ---------------------------------------------------------------- characters
CHARS = {
    "derrick_child": dict(build="child", garment="tunic", color=P2, hair="shaggy", right="wooden_sword", mood="plain"),
    "derrick_child_sit": dict(build="child", garment="tunic", color=P2, hair="shaggy", mood="sad", sit=True),
    "derrick_youth": dict(build="youth", garment="rags", color=P4, hair="shaggy", belt_item="wooden_sword", mood="sad"),
    "derrick_lad": dict(build="slight", garment="tunic", color=P3, sleeve=P4, hair="shaggy", right="stick", belt_item="wooden_sword", mood="stern"),
    "derrick_man": dict(build="adult", garment="gambeson", color=P4, hair="shaggy", stubble=True, right="knife",
                       belt_item="wooden_sword", mood="stern", blood=3),
    "derrick_man_sit": dict(build="adult", garment="gambeson", color=P4, hair="shaggy", stubble=True,
                           mood="sad", blood=5, sit=True),
    "mother": dict(build="slight", garment="dress", color=P3, head="kerchief", apron=True, mood="kind"),
    "father": dict(build="adult", garment="tunic", color=P4, hair="short", beard=True, right="axe", mood="stern"),
    "gauntley": dict(build="adult", garment="mail", color=STEEL, sleeve=STEEL, tabard=HERO_BLUE, device="sun",
                     hair="short", hair_color="#5a3a22", beard="#5a3a22", right="sword", left="shield",
                     mood="kind", cloak=HERO_RED),
    "gauntley_helm": dict(build="adult", garment="mail", color=STEEL, sleeve=STEEL, tabard=HERO_BLUE, device="sun",
                          head="helm_plume", right="sword", left="shield", mood="stern", cloak=HERO_RED),
    "man_at_arms": dict(build="adult", garment="mail", color=P2, sleeve=P2, tabard=P3, head="coif", right="spear", mood="stern"),
    "kid_a": dict(build="child", garment="dress", color=PAPER, hair="long", mood="kind"),
    "kid_b": dict(build="child", garment="tunic", color=P4, head="cap", right="stick", mood="plain"),
    "villager": dict(build="adult", garment="tunic", color=P3, hair="short", beard=P4, mood="plain"),
    "villager_f": dict(build="slight", garment="dress", color=P4, head="kerchief", kerchief=P2, mood="plain"),
    "monk": dict(build="adult", garment="robe", color=P5, hair="tonsure", mood="stern", left="bowl"),
    "baker": dict(build="big", garment="tunic", color=PAPER, apron=True, hair="bald", mood="stern", right="stick"),
    "ostry": dict(build="big", garment="tunic", color=P3, head="cap", beard="#8a8070", right="pitchfork", mood="stern"),
    "hild": dict(build="slight", garment="dress", color=P4, head="kerchief", apron=True, left="bowl", mood="kind"),
    "edric": dict(build="adult", garment="tunic", color=P3, sleeve=P2, hair="short", mood="stern", right="stick"),
    "wat": dict(build="youth", garment="tunic", color=P2, hair="shaggy", mood="sly"),
    "levy": dict(build="adult", garment="gambeson", color=P3, head="coif", mood="sad", blood=7),
    "looter": dict(build="adult", garment="rags", color=P5, head="hood", hood_color=P5, right="knife", mood="sly", blood=11, stubble=True),
    "wick": dict(build="slight", garment="gambeson", color=P3, hair="shaggy", emblem=True, right="sword", mood="sly"),
    "jacob": dict(build="big", garment="mail", color=P2, sleeve=P2, tabard=INK, hair="bald", beard="#8a8070",
                  emblem=True, right="big_blade", mood="stern"),
    "jack": dict(build="tall", garment="coat", color=INK, sleeve=P5, hair="slick", beard=True, chain=True,
                 emblem=True, left="ledger", mood="kind"),
    "jack_kneel": dict(build="tall", garment="coat", color=INK, sleeve=P5, hair="slick", beard=True, chain=True,
                       emblem=True, mood="kind", sit=True),
    # the alley in Coldharbour
    "bearded": dict(build="big", garment="gambeson", color=P4, sleeve=P5, hair="short", beard=True, emblem=True,
                    right="knife", mood="grin"),
    "wiry": dict(build="slight", garment="rags", color=P5, hair="shaggy", emblem=True, right="knife", mood="sly", stubble=True),
    "grabber": dict(build="adult", garment="gambeson", color=P3, head="hood", hood_color=P4, emblem=True, mood="stern"),
    "grabber_hurt": dict(build="adult", garment="gambeson", color=P3, head="hood", hood_color=P4, emblem=True,
                         mood="sad", blood=17, left="rag_hand"),
    "son_a": dict(build="adult", garment="mail", color=P2, sleeve=P3, tabard=P5, head="kettle", emblem=True, right="sword", mood="plain"),
    "son_b": dict(build="big", garment="gambeson", color=P5, hair="bald", beard="#8a8070", emblem=True, right="axe", mood="stern"),
    "son_c": dict(build="slight", garment="tunic", color=P4, head="coif", emblem=True, right="spear", mood="plain"),
    "simon": dict(build="adult", garment="gambeson", color=P5, hair="short", emblem=True, left="lantern", mood="plain"),
    "osric": dict(build="big", garment="mail", color=P2, sleeve=P3, tabard=P5, head="kettle", emblem=True, right="spear", mood="stern"),
    "nora": dict(build="slight", garment="tunic", color=P4, head="hood", hood_color=P5, emblem=True, left="bow", mood="plain"),
    "daryl": dict(build="adult", garment="gambeson", color=P4, hair="short", hair_color="#8a8070", beard="#8a8070", emblem=True, right="axe", mood="sad"),
}
SPEAKERS = ["derrick_child", "derrick_youth", "derrick_lad", "derrick_man", "mother", "father", "gauntley",
            "man_at_arms", "kid_a", "kid_b", "villager", "monk", "baker", "ostry", "hild", "edric", "wat",
            "levy", "looter", "wick", "jacob", "jack", "simon", "osric", "nora", "daryl",
            "bearded", "wiry", "grabber", "grabber_hurt"]


# ---------------------------------------------------------------- tiles (seamless, 48 grid -> 64 px)
TILE_PX = 64


def _scatter(seed, n, fn, lo=5, hi=43):
    rng = random.Random(seed)
    return "".join(fn(rng.uniform(lo, hi), rng.uniform(lo, hi), rng) for _ in range(n))


def tile(kind):
    T = 48
    art = Art()
    b = []
    if kind in GROUND:
        base = GROUND[kind]
        b.append(rect(0, 0, T, T, base, 0, False))
        if kind == "grass":
            b.append(_scatter("g", 7, lambda x, y, r: f'<path d="M{x:.1f},{y:.1f} l-1.5,-4 M{x:.1f},{y:.1f} l1.5,-4.5 M{x:.1f},{y:.1f} l0,-5" '
                                                      f'stroke="{P4}" stroke-width="1.1" stroke-linecap="round" fill="none"/>', 6, 42))
        elif kind == "mud":
            b.append(_scatter("m", 6, lambda x, y, r: ellipse(round(x, 1), round(y, 1), r.uniform(2, 5), r.uniform(1, 2), P5, False, ' opacity="0.6"'), 6, 42))
            b.append(_scatter("m2", 4, lambda x, y, r: line(round(x, 1), round(y, 1), round(x + 6, 1), round(y + 0.5, 1), INK, 0.8, ' opacity="0.6"'), 6, 36))
        elif kind == "snow":
            b.append(_scatter("s", 8, lambda x, y, r: circle(round(x, 1), round(y, 1), 0.8, "#b8bcc4", False), 4, 44))
            b.append(_scatter("s2", 3, lambda x, y, r: path(f"M{x:.1f},{y:.1f} q4,-2 8,0", "none", False, f' stroke="#c9ccd2" stroke-width="1"'), 4, 36))
        elif kind == "ash":
            b.append(_scatter("a", 14, lambda x, y, r: circle(round(x, 1), round(y, 1), r.uniform(0.5, 1.4), INK, False, ' opacity="0.7"'), 4, 44))
            b.append(_scatter("a2", 3, lambda x, y, r: line(round(x, 1), round(y, 1), round(x + 5, 1), round(y - 2, 1), INK, 1.4), 6, 38))
        elif kind == "cobble":
            rng = random.Random("cob")
            for row in range(4):
                off = 6 if row % 2 else 0
                for col in range(-1, 4):
                    x = col * 12 + off + rng.uniform(-1, 1)
                    y = row * 12 + rng.uniform(-0.5, 0.5)
                    b.append(rect(round(x + 1, 1), round(y + 1, 1), 10, 10, P2 if (row + col) % 3 else P3, 3, True, ' stroke-width="1"'))
    elif kind == "road":
        b.append(rect(0, 0, T, T, "#c4b490", 0, False))
        for y in (13, 35):
            b.append(line(0, y, T, y, P3, 2.4))
        b.append(_scatter("r", 5, lambda x, y, r: ellipse(round(x, 1), round(y, 1), 1.5, 1, P4, False), 4, 44))
    elif kind == "road_snow":
        b.append(rect(0, 0, T, T, "#d8d6d0", 0, False))
        for y in (14, 34):
            b.append(line(0, y, T, y, "#8f8a80", 2.2))
    elif kind == "road_mud":
        b.append(rect(0, 0, T, T, "#7d6e56", 0, False))
        for y in (13, 35):
            b.append(line(0, y, T, y, P5, 2.6))
        b.append(_scatter("rm", 5, lambda x, y, r: ellipse(round(x, 1), round(y, 1), 3, 1.2, INK, False, ' opacity="0.5"'), 4, 44))
    elif kind == "floor":
        b.append(rect(0, 0, T, T, "#8a6d4a", 0, False))
        for y in (0, 12, 24, 36):
            b.append(line(0, y, T, y, INK, 1.4))
        for (x, y) in ((16, 0), (40, 12), (8, 24), (30, 36)):
            b.append(line(x, y, x, y + 12, INK, 1.2))
        b.append(_scatter("fl", 6, lambda x, y, r: line(round(x, 1), round(y, 1), round(x + 7, 1), round(y, 1), P5, 0.6), 2, 40))
    elif kind == "wall_stone":
        b.append(rect(0, 0, T, T, P3, 0, False))
        for row in range(4):
            y = row * 12
            b.append(line(0, y, T, y, INK, 1.8))
            off = 12 if row % 2 else 0
            for x in range(off, T + 1, 24):
                b.append(line(x, y, x, y + 12, INK, 1.8))
        b.append(art.hatch(rect(0, 0, T, T, "#000", 0, False), 0, 0, T, T, 4, 0.5, INK, 0.4))
    elif kind == "wall_timber":
        b.append(rect(0, 0, T, T, P5, 0, False))
        for x in range(0, T, 8):
            b.append(line(x, 0, x, T, INK, 1.4))
        b.append(rect(0, 36, T, 12, INK, 0, False))
    elif kind in ("roof", "roof_burned"):
        burned = kind == "roof_burned"
        b.append(rect(0, 0, T, T, P3 if not burned else "#2a241f", 0, False))
        rng = random.Random(kind)
        for row in range(6):
            y = row * 8 + 2
            for i in range(9):
                x = i * 6 + (3 if row % 2 else 0)
                b.append(line(x, y, x - 2, y + 6, INK if not burned else "#57493d", 1.1))
        if burned:
            for x in (6, 20, 34):
                b.append(line(x, 0, x + 6, T, INK, 3))
            b.append(_scatter("em", 4, lambda x, y, r: circle(round(x, 1), round(y, 1), 1, FIRE, False), 6, 42))
    elif kind in ("house_wall", "house_window", "house_burned"):
        burned = kind == "house_burned"
        b.append(rect(0, 0, T, T, P2 if not burned else "#3a322b", 0, False))
        b.append(rect(0, 0, T, 5, INK, 0, False))                 # eave shadow
        for x in (0, 24):
            b.append(line(x + 2, 5, x + 2, T, INK if not burned else "#1a1512", 3))
        b.append(line(0, 26, T, 26, INK if not burned else "#1a1512", 2.6))
        b.append(line(2, 46, 24, 26, INK if not burned else "#1a1512", 2))
        if kind == "house_window":
            b.append(rect(28, 12, 14, 12, FIRE_LT, 1, True))
            b.append(line(35, 12, 35, 24, INK, 1.4))
            b.append(line(28, 18, 42, 18, INK, 1.4))
        if burned:
            b.append(_scatter("hb", 10, lambda x, y, r: circle(round(x, 1), round(y, 1), r.uniform(0.6, 2), INK, False), 4, 44))
    elif kind == "water":
        b.append(rect(0, 0, T, T, WATER, 0, False))
        for y in (10, 24, 38):
            for x0 in (2, 26):
                b.append(f'<path d="M{x0},{y} q5,-3 10,0 t10,0" stroke="{WATER_LT}" stroke-width="1.6" fill="none" stroke-linecap="round"/>')
    elif kind == "crops":
        b.append(rect(0, 0, T, T, "#b89a4a", 0, False))
        rng = random.Random("crop")
        for i in range(12):
            x = 3 + i * 3.8
            h = rng.uniform(12, 18)
            for y0 in (22, 46):
                b.append(line(round(x, 1), y0, round(x + 1, 1), round(y0 - h, 1), "#6d5520", 1.2))
                b.append(ellipse(round(x + 1, 1), round(y0 - h, 1), 1.2, 2.6, GOLD, False))
    elif kind == "stubble":
        b.append(rect(0, 0, T, T, "#c9b27a", 0, False))
        for i in range(8):
            for y0 in (12, 28, 44):
                b.append(line(3 + i * 6, y0, 4 + i * 6, y0 - 4, "#6d5520", 1.2))
    return art.svg(TILE_PX, TILE_PX, "".join(b), f"0 0 {T} {T}")


# ---------------------------------------------------------------- props (transparent, drawn over ground)
def prop(kind):
    art = Art()
    b = []
    vb = "0 0 48 48"
    w, h = TILE_PX, TILE_PX
    if kind == "tree":
        b += [ellipse(24, 44, 14, 3, INK, False, ' opacity="0.3"'), rect(20, 28, 8, 16, P4, 2)]
        canopy = "M24,2 Q40,4 42,18 Q46,30 32,32 Q24,36 16,32 Q2,30 6,18 Q8,4 24,2 Z"
        b += [path(canopy, LEAF), art.hatch(path(canopy, "#000", False), 24, 0, 24, 36, 2.4, 0.8, INK, 0.8),
              path("M14,10 Q18,6 24,7", "none", False, f' stroke="{LEAF_LT}" stroke-width="2.4" stroke-linecap="round"')]
    elif kind == "pine_snow":
        b += [ellipse(24, 44, 12, 3, INK, False, ' opacity="0.3"'), rect(21, 34, 6, 10, P5, 1)]
        for i, (y, wdt) in enumerate(((4, 8), (14, 13), (24, 18))):
            tri = [(24, y - 2), (24 + wdt, y + 12), (24 - wdt, y + 12)]
            b += [poly(tri, "#23331f"), path(f"M{24 - wdt + 3},{y + 11} L{24},{y + 1} L{24 + wdt - 5},{y + 9}", "none", False,
                                             ' stroke="#efeadf" stroke-width="2" stroke-linecap="round"')]
    elif kind == "dead_tree":
        b += [ellipse(24, 44, 10, 2.5, INK, False, ' opacity="0.3"'),
              path("M22,44 L22,24 L12,12 M22,24 L22,14 L28,4 M22,20 L32,12 L38,14 M22,30 L14,26", "none", True, "", 3)]
    elif kind == "bush":
        bush = "M6,40 Q2,28 12,24 Q16,14 26,18 Q38,14 42,26 Q48,34 42,40 Z"
        b += [path(bush, LEAF), art.hatch(path(bush, "#000", False), 24, 12, 26, 30, 2.4, 0.8, INK, 0.7)]
    elif kind == "well":
        b += [ellipse(24, 42, 16, 3, INK, False, ' opacity="0.3"'), rect(8, 22, 32, 18, P3, 3),
              ellipse(24, 22, 16, 5, INK), line(10, 22, 10, 4, P4, 2.6), line(38, 22, 38, 4, P4, 2.6),
              path("M6,6 L24,0 L42,6", "none", True, "", 2.4)]
        b.append(art.hatch(rect(8, 22, 32, 18, "#000", 3, False), 8, 24, 32, 16, 3, 0.7, INK, 1, "h"))
    elif kind == "cart":
        b += [ellipse(24, 44, 20, 3, INK, False, ' opacity="0.3"'), rect(2, 18, 44, 14, P3, 1),
              art.hatch(rect(2, 18, 44, 14, "#000", 1, False), 2, 18, 44, 14, 3, 0.7, INK, 1, "v"),
              circle(12, 36, 7, P4), circle(12, 36, 1.6, INK, False), circle(36, 36, 7, P4), circle(36, 36, 1.6, INK, False)]
    elif kind == "bread_cart":
        b += [ellipse(24, 44, 20, 3, INK, False, ' opacity="0.3"'), rect(2, 20, 44, 12, P3, 1),
              ellipse(12, 18, 6, 4, "#c78a3a"), ellipse(24, 16, 6, 4, "#c78a3a"), ellipse(36, 18, 6, 4, "#c78a3a"),
              circle(12, 37, 6, P4), circle(36, 37, 6, P4)]
    elif kind == "crate":
        b += [ellipse(24, 44, 16, 3, INK, False, ' opacity="0.3"'), rect(8, 14, 32, 28, P3, 1),
              line(8, 14, 40, 42, INK, 2), line(40, 14, 8, 42, INK, 2)]
    elif kind == "barrel":
        b += [ellipse(24, 44, 12, 3, INK, False, ' opacity="0.3"'), rect(12, 12, 24, 30, P4, 8),
              line(12, 20, 36, 20, INK, 2), line(12, 34, 36, 34, INK, 2), ellipse(24, 12, 12, 3, P3, True)]
    elif kind == "sack":
        b += [ellipse(24, 44, 12, 3, INK, False, ' opacity="0.3"'), path("M12,42 Q8,24 18,18 L16,12 L32,12 L30,18 Q40,24 36,42 Z", P2)]
    elif kind == "hay":
        hay = "M4,42 Q2,22 24,18 Q46,22 44,42 Z"
        b += [path(hay, "#c9a95a"), art.hatch(path(hay, "#000", False), 2, 16, 44, 28, 2.4, 0.8, "#6d5520", 1, "u")]
    elif kind == "grave":
        b += [ellipse(24, 44, 10, 2.5, INK, False, ' opacity="0.3"'), rect(21, 10, 6, 34, P4, 1), rect(12, 18, 24, 6, P4, 1)]
    elif kind == "shroud":
        sh = "M4,40 Q2,32 10,30 Q18,26 30,28 Q44,28 44,36 Q46,42 36,42 L10,42 Q4,42 4,40 Z"
        b += [path(sh, PAPER), art.hatch(path(sh, "#000", False), 4, 26, 42, 18, 2.2, 0.7, P3, 1, "h"),
              path("M8,34 Q20,30 40,34", "none", True, "", 1)]
    elif kind == "fallen":
        b += [path("M4,38 Q6,30 16,32 L30,30 Q40,28 44,34 L42,40 L8,42 Z", P5), circle(40, 30, 5, P3),
              line(4, 44, 30, 20, P4, 2), circle(20, 38, 2, BLOOD, False), circle(26, 40, 1.4, BLOOD, False)]
    elif kind == "spears":
        b += [line(8, 44, 20, 6, P4, 2.2), line(24, 44, 30, 14, P4, 2.2), line(36, 44, 44, 20, P4, 2.2),
              poly([(18.5, 8), (21.5, 9), (17, 1)], STEEL, True, ' stroke-width="1"')]
    elif kind == "lord_banner":
        b += [line(10, 46, 30, 4, P4, 2.6), path("M29,6 L46,12 L40,22 L24,16 Z", BLOOD, True, "", 1.6),
              art.hatch(path("M29,6 L46,12 L40,22 L24,16 Z", "#000", False), 24, 6, 22, 16, 2.4, 0.6, INK, 0.7)]
    elif kind == "campfire":
        b += [ellipse(24, 40, 16, 4, INK, False, ' opacity="0.35"'), line(10, 40, 38, 32, P5, 4), line(10, 32, 38, 40, P5, 4),
              path("M14,34 Q10,22 20,12 Q20,22 24,20 Q24,8 32,2 Q30,16 36,20 Q40,28 34,36 Z", FIRE, True, "", 1.6),
              path("M20,34 Q18,26 24,20 Q26,28 30,26 Q32,32 28,36 Z", FIRE_LT, False)]
    elif kind == "hearth":
        b += [rect(2, 8, 44, 38, P3, 2), rect(10, 20, 28, 26, INK, 2),
              path("M16,44 Q14,34 22,28 Q22,36 26,34 Q28,26 32,24 Q34,34 32,44 Z", FIRE, False)]
    elif kind == "hatch":
        b += [rect(6, 6, 36, 36, P4, 1), line(6, 18, 42, 18, INK, 1.8), line(6, 30, 42, 30, INK, 1.8),
              circle(34, 24, 2.5, INK, False)]
    elif kind == "hatch_open":
        b += [rect(6, 6, 36, 36, INK, 1), line(8, 12, 40, 12, P5, 1.4), line(8, 24, 40, 24, P5, 1.4),
              line(8, 36, 40, 36, P5, 1.4)]
    elif kind == "bed":
        b += [rect(4, 4, 40, 40, P4, 2), rect(8, 8, 32, 12, PAPER, 3), rect(6, 20, 36, 22, P3, 2),
              art.hatch(rect(6, 20, 36, 22, "#000", 2, False), 6, 20, 36, 22, 3, 0.7, INK, 1)]
    elif kind == "table":
        b += [ellipse(24, 44, 18, 3, INK, False, ' opacity="0.3"'), rect(4, 12, 40, 26, P4, 2),
              ellipse(16, 22, 5, 3, P2), ellipse(30, 26, 6, 3.5, "#c78a3a")]
    elif kind == "stool":
        b += [ellipse(24, 30, 9, 6, P4), line(18, 34, 16, 44, INK, 2), line(30, 34, 32, 44, INK, 2)]
    elif kind == "door":
        b += [path("M10,48 L10,14 Q24,2 38,14 L38,48 Z", P5), line(24, 8, 24, 48, INK, 1.4),
              circle(33, 32, 1.8, GOLD, False)]
    elif kind == "almshouse_door":
        b += [path("M8,48 L8,12 Q24,0 40,12 L40,48 Z", P5), line(16, 8, 16, 48, INK, 1.2), line(24, 4, 24, 48, INK, 1.2),
              line(32, 8, 32, 48, INK, 1.2), rect(20, 20, 8, 6, FIRE_LT, 1, True, ' stroke-width="1"')]
    elif kind == "fence":
        b += [line(0, 22, 48, 22, P4, 3), line(0, 34, 48, 34, P4, 3), rect(6, 14, 5, 28, P4, 1), rect(36, 14, 5, 28, P4, 1)]
    elif kind == "fence_v":
        b += [line(20, 0, 20, 48, P4, 3), line(28, 0, 28, 48, P4, 3), rect(18, 6, 12, 6, P4, 1), rect(18, 34, 12, 6, P4, 1)]
    elif kind == "wooden_sword":
        b += [line(10, 38, 36, 12, P3, 4.4), line(10, 38, 36, 12, INK, 1, ' opacity="0.5"'), line(12, 30, 20, 38, INK, 2.4)]
    elif kind == "bread":
        b += [ellipse(24, 30, 12, 7, "#c78a3a"), path("M16,28 Q24,22 32,28", "none", True, "", 1)]
    elif kind == "tent":
        w, h = 128, 128
        vb = "0 0 96 96"
        tent = "M4,92 L48,10 L92,92 Z"
        b += [ellipse(48, 92, 44, 4, INK, False, ' opacity="0.35"'), path(tent, P2),
              art.hatch(path(tent, "#000", False), 48, 10, 46, 84, 3.2, 1, INK, 0.9),
              path("M36,92 L48,52 L60,92 Z", INK), line(48, 10, 48, 2, P5, 2.4)]
    elif kind == "gibbet":
        w, h = 64, 128
        vb = "0 0 48 96"
        b += [ellipse(18, 94, 12, 2, INK, False, ' opacity="0.35"'), rect(14, 6, 6, 88, P5, 1), rect(14, 6, 30, 5, P5, 1),
              line(20, 20, 30, 11, P5, 3), line(38, 11, 38, 30, INK, 1.2),
              path("M33,30 L43,30 L44,56 L32,56 Z", "none", True, "", 1.6), line(33, 38, 43, 38, INK, 1), line(33, 46, 44, 46, INK, 1),
              rect(10, 58, 14, 16, PAPER, 0, True, ' stroke-width="1.2"'),
              line(12, 62, 22, 62, INK, 0.8), line(12, 65, 21, 65, INK, 0.8), line(12, 68, 22, 68, INK, 0.8),
              circle(17, 71.5, 1.8, GOLD, True, ' stroke-width="0.6"')]
    elif kind == "sons_banner":
        w, h = 64, 128
        vb = "0 0 48 96"
        flag = "M10,8 L44,8 L44,52 L27,44 L10,52 Z"
        b += [ellipse(8, 94, 8, 2, INK, False, ' opacity="0.35"'), rect(6, 2, 4, 92, P5, 1), path(flag, INK),
              circle(27, 26, 7, GOLD, True, ' stroke-width="1.2"'), line(18, 17, 36, 35, PAPER, 2.2),
              art.hatch(path(flag, "#000", False), 10, 8, 34, 44, 3, 0.6, P5, 1, "v")]
    elif kind == "stake_rope":
        b += [rect(22, 6, 4, 38, P4, 1), path("M26,12 Q36,16 30,24 Q24,30 34,34", "none", True, "", 1.4)]
    elif kind == "crow":
        return crow_svg()
    elif kind == "horse":
        return horse_svg(None, 128)
    return art.svg(w, h, "".join(b), vb)


PROPS_TALL = {"tent", "gibbet", "sons_banner"}


# ---------------------------------------------------------------- icons (32px)
def icon(kind):
    art = Art()
    b = []
    if kind == "attack":
        b += [poly([(24, 3), (29, 3), (29, 8), (13, 24), (8, 19)], STEEL), line(6, 17, 15, 26, P4, 4), line(5, 27, 9, 23, INK, 4)]
    elif kind == "skill":   # a fist
        b += [path("M8,14 Q8,8 13,8 L22,8 Q27,8 27,13 L27,22 Q27,28 20,28 L13,28 Q8,28 8,22 Z", PAPER),
              line(13, 8, 13, 16, INK, 1.2), line(18, 8, 18, 16, INK, 1.2), line(23, 8, 23, 16, INK, 1.2)]
    elif kind == "item":    # a pouch
        b += [path("M9,12 Q4,28 16,29 Q28,28 23,12 Z", P3), path("M9,12 L23,12 L20,6 L12,6 Z", P4), line(8, 12, 24, 12, INK, 2)]
    elif kind == "defend":
        b += [path("M5,5 L27,5 L27,15 Q27,26 16,30 Q5,26 5,15 Z", P2),
              art.hatch(path("M16,5 L27,5 L27,15 Q27,26 16,30 Z", "#000", False), 16, 5, 12, 26, 2.2, 0.8)]
    elif kind == "flee":
        b += [path("M4,16 L18,6 L18,12 L28,12 L28,20 L18,20 L18,26 Z", P2)]
    elif kind == "bleed":
        b += [path("M16,3 Q26,16 25,21 Q24,29 16,29 Q8,29 7,21 Q6,16 16,3 Z", BLOOD), path("M11,20 Q11,15 14,12", "none", False, f' stroke="{PAPER}" stroke-width="1.6" opacity="0.6"')]
    elif kind == "dazed":
        b += [path("M16,16 m-9,0 a9,9 0 1,1 18,0 a7,7 0 1,1 -14,0 a5,5 0 1,1 10,0 a3,3 0 1,1 -6,0", "none", True, "", 2.2)]
    elif kind == "maimed":
        b += [path("M6,10 Q4,5 8,5 Q10,2 12,6 L20,18 Q24,16 26,20 Q28,24 24,26 Q24,30 20,27 L12,14 Q8,16 6,10 Z", PAPER),
              path("M14,11 L17,15 L15,17 L18,21", "none", False, f' stroke="{BLOOD}" stroke-width="2" stroke-linecap="round"')]
    elif kind == "fear":
        b += [path("M3,16 Q16,4 29,16 Q16,28 3,16 Z", PAPER), circle(16, 16, 5, INK, False), circle(17.5, 14.5, 1.5, PAPER, False)]
    elif kind == "last_stand":
        b += [line(8, 30, 8, 3, P4, 2.6), path("M9,4 L27,8 L9,16 Z", BLOOD)]
    elif kind == "guard":
        b += [path("M7,6 L25,6 L25,15 Q25,24 16,28 Q7,24 7,15 Z", P3)]
    elif kind == "grit":
        b += [path("M16,2 Q24,12 24,20 Q24,30 16,30 Q8,30 8,20 Q8,14 12,10 Q12,16 16,17 Q14,10 16,2 Z", "#c49a3a")]
    elif kind == "bread":
        b += [ellipse(16, 18, 12, 8, "#c78a3a"), path("M8,17 Q16,11 24,17", "none", True, "", 1.2)]
    elif kind == "rag":
        b += [path("M6,8 L26,6 L24,14 L28,22 L6,26 L9,17 Z", PAPER), line(9, 12, 22, 11, P3, 1), line(10, 20, 22, 19, P3, 1)]
    elif kind == "gouge":
        b += [path("M6,26 Q10,10 24,6", "none", True, "", 3), circle(24, 6, 3, PAPER), circle(10, 24, 2, BLOOD, False)]
    elif kind == "skull":
        b += [path("M6,15 Q6,4 16,4 Q26,4 26,15 L23,19 L23,25 L9,25 L9,19 Z", PAPER), circle(12, 14, 2.6, INK, False),
              circle(20, 14, 2.6, INK, False), path("M17,4 L15,9 L18,12", "none", True, "", 1.3)]
    elif kind == "riposte":
        b += [line(5, 27, 27, 5, STEEL, 3.4), line(5, 5, 27, 27, STEEL, 3.4), line(5, 27, 27, 5, INK, 1), line(5, 5, 27, 27, INK, 1)]
    elif kind == "wild":
        b += [path("M4,24 Q10,4 28,8", "none", True, "", 2.6), path("M8,28 Q16,14 28,16", "none", True, "", 1.6)]
    elif kind == "evade":
        b += [path("M6,26 Q16,2 26,26", "none", True, "", 2.4), poly([(22, 24), (28, 28), (26, 20)], INK)]
    elif kind == "coin":
        b += [circle(16, 16, 11, GOLD), line(8, 8, 24, 24, INK, 2)]
    elif kind == "cursor":  # points right
        b += [poly([(4, 5), (28, 16), (4, 27), (10, 16)], PAPER)]
    elif kind == "cursor_down":
        b += [poly([(5, 4), (16, 10), (27, 4), (16, 28)], GOLD)]
    return art.svg(32, 32, "".join(b), "0 0 32 32")


# ---------------------------------------------------------------- fx
def fx(kind):
    if kind == "rain":
        return ('<svg xmlns="http://www.w3.org/2000/svg" width="4" height="30" viewBox="0 0 4 30">'
                f'<line x1="2" y1="1" x2="2" y2="29" stroke="{P2}" stroke-width="1.6" stroke-linecap="round" opacity="0.8"/></svg>\n')
    if kind == "snow":
        return ('<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10" viewBox="0 0 10 10">'
                '<circle cx="5" cy="5" r="3.6" fill="#f4f1ea"/></svg>\n')
    if kind == "ash":
        return ('<svg xmlns="http://www.w3.org/2000/svg" width="8" height="8" viewBox="0 0 8 8">'
                '<polygon points="1,3 6,1 7,6 2,7" fill="#4a443c"/></svg>\n')
    if kind == "ember":
        return ('<svg xmlns="http://www.w3.org/2000/svg" width="6" height="6" viewBox="0 0 6 6">'
                f'<circle cx="3" cy="3" r="2.4" fill="{FIRE_LT}"/></svg>\n')
    if kind in ("smoke", "fog"):
        w, h = (64, 64) if kind == "smoke" else (512, 200)
        c = "#3a332c" if kind == "smoke" else "#d9d4c8"
        return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">'
                f'<defs><radialGradient id="g" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="{c}" stop-opacity="0.85"/>'
                f'<stop offset="0.6" stop-color="{c}" stop-opacity="0.35"/><stop offset="1" stop-color="{c}" stop-opacity="0"/></radialGradient></defs>'
                f'<ellipse cx="{w / 2}" cy="{h / 2}" rx="{w / 2}" ry="{h / 2}" fill="url(#g)"/></svg>\n')
    return ""


# ---------------------------------------------------------------- backgrounds (1280x720)
def _engraved_sky(rng, w, top, bottom, dense_at_top=True, color=INK, maxw=2.4):
    """Horizontal engraving lines, thick and dense at one end, thin and sparse at the other."""
    out = []
    y = top
    while y < bottom:
        t = (y - top) / max(1, bottom - top)
        k = (1 - t) if dense_at_top else t
        gap = 5 + (1 - k) * 12
        width = 0.5 + k * maxw
        x = rng.uniform(-40, 0)
        while x < w:
            seg = rng.uniform(120, 420)
            out.append(f'<line x1="{x:.0f}" y1="{y:.1f}" x2="{x + seg:.0f}" y2="{y + rng.uniform(-1, 1):.1f}" '
                       f'stroke="{color}" stroke-width="{width:.2f}" stroke-linecap="round"/>')
            x += seg + rng.uniform(6, 40)
        y += gap
    return "".join(out)


def _ground_lines(rng, w, top, bottom, color=INK):
    out = []
    y = top + 6
    while y < bottom:
        t = (y - top) / max(1, bottom - top)
        width = 0.6 + t * 2.4
        x = rng.uniform(-40, 0)
        while x < w:
            seg = rng.uniform(80, 300)
            out.append(f'<line x1="{x:.0f}" y1="{y:.1f}" x2="{x + seg:.0f}" y2="{y:.1f}" stroke="{color}" '
                       f'stroke-width="{width:.2f}" opacity="0.8"/>')
            x += seg + rng.uniform(10, 60)
        y += 9 + (1 - t) * 10
    return "".join(out)


def _tree_silhouette(x, base, hgt, color=INK, leaves=None):
    o = [f'<path d="M{x - 6},{base} L{x - 4},{base - hgt * 0.5} L{x - 18},{base - hgt * 0.8} M{x - 4},{base - hgt * 0.55} '
         f'L{x + 2},{base - hgt} M{x + 1},{base - hgt * 0.6} L{x + 20},{base - hgt * 0.85}" stroke="{color}" stroke-width="7" '
         f'fill="none" stroke-linecap="round"/>', f'<rect x="{x - 7}" y="{base - hgt * 0.5}" width="12" height="{hgt * 0.5}" fill="{color}"/>']
    if leaves:
        o.append(f'<ellipse cx="{x}" cy="{base - hgt * 0.8}" rx="{hgt * 0.45}" ry="{hgt * 0.32}" fill="{leaves}" stroke="{INK}" stroke-width="4"/>')
    return "".join(o)


def _house_silhouette(x, base, wdt, hgt, color=INK, window=None):
    o = [f'<rect x="{x}" y="{base - hgt}" width="{wdt}" height="{hgt}" fill="{color}"/>',
         f'<polygon points="{x - 14},{base - hgt} {x + wdt / 2},{base - hgt - hgt * 0.8} {x + wdt + 14},{base - hgt}" fill="{color}"/>']
    if window:
        o.append(f'<rect x="{x + wdt * 0.35}" y="{base - hgt * 0.7}" width="{wdt * 0.2}" height="{hgt * 0.25}" fill="{window}"/>')
    return "".join(o)


def background(kind, w=1280, h=720):
    rng = random.Random(kind)
    art = Art()
    b = []
    if kind == "green":       # Harrowgate, midsummer
        b += [rect(0, 0, w, h, PAPER, 0, False), _engraved_sky(rng, w, 0, 330, True, P3, 1.6),
              circle(1040, 110, 60, PAPER, True, ' stroke-width="4"')]
        for a in range(0, 360, 15):
            b.append(line(1040 + 72 * math.cos(math.radians(a)), 110 + 72 * math.sin(math.radians(a)),
                          1040 + 100 * math.cos(math.radians(a)), 110 + 100 * math.sin(math.radians(a)), INK, 2.4))
        b.append('<path d="M0,360 Q300,300 640,340 T1280,330 L1280,720 L0,720 Z" fill="#d6c9a6"/>')
        for x in (90, 300, 820, 1010):
            b.append(_house_silhouette(x, 360, 130, 70, P4))
        b.append(_tree_silhouette(620, 380, 170, INK, LEAF))
        b.append(_tree_silhouette(1200, 380, 150, INK, LEAF))
        b.append(f'<rect y="370" width="{w}" height="{h - 370}" fill="#d6c9a6"/>')
        b.append(_ground_lines(rng, w, 380, 720, P4))
    elif kind == "alley":     # Ashford, rain
        b += [rect(0, 0, w, h, "#2a2520", 0, False)]
        b += [f'<polygon points="0,0 360,120 360,560 0,720" fill="{INK}"/>',
              f'<polygon points="1280,0 920,120 920,560 1280,720" fill="{INK}"/>',
              f'<rect x="360" y="120" width="560" height="440" fill="#3b332a"/>',
              f'<rect x="580" y="230" width="90" height="70" fill="{FIRE_LT}"/>',
              line(625, 230, 625, 300, INK, 5), line(580, 265, 670, 265, INK, 5)]
        b.append(f'<polygon points="0,720 360,560 920,560 1280,720" fill="#4a4138"/>')
        for y in range(570, 720, 18):
            b.append(line(0, y, w, y, INK, 1.2, ' opacity="0.7"'))
        for i in range(160):
            x = rng.uniform(0, w)
            y = rng.uniform(0, h)
            b.append(line(round(x), round(y), round(x - 8), round(y + 34), P3, 1.2, ' opacity="0.55"'))
    elif kind == "alley_fire":  # Coldharbour: a dead end, the city burning behind the men
        gid = art.uid("fire")
        art.defs.append(f'<radialGradient id="{gid}" cx="0.5" cy="0.75" r="0.6"><stop offset="0" stop-color="{FIRE}" stop-opacity="0.8"/>'
                        f'<stop offset="0.5" stop-color="#5a2a10" stop-opacity="0.45"/><stop offset="1" stop-color="{INK}" stop-opacity="0"/></radialGradient>')
        b += [rect(0, 0, w, h, "#15110d", 0, False), f'<rect width="{w}" height="{h}" fill="url(#{gid})"/>']
        b += [f'<polygon points="0,0 380,110 380,560 0,720" fill="{INK}"/>',
              f'<polygon points="1280,0 900,110 900,560 1280,720" fill="{INK}"/>']
        for x in range(392, 900, 34):     # the rotting plank wall at the end
            b.append(rect(x, 140 + (x * 7) % 18, 30, 420 - (x * 7) % 18, "#3b2e22", 2, True, ' stroke-width="3"'))
            b.append(line(x + 8, 200 + (x * 13) % 120, x + 22, 230 + (x * 13) % 120, INK, 2))
        b.append(f'<polygon points="0,720 380,560 900,560 1280,720" fill="#2a221b"/>')
        for y in range(575, 720, 20):
            b.append(line(0, y, w, y, INK, 1.2, ' opacity="0.7"'))
        for i in range(40):
            b.append(circle(round(rng.uniform(300, 980)), round(rng.uniform(80, 600)), round(rng.uniform(1.5, 3.5), 1), FIRE_LT, False, ' opacity="0.8"'))
    elif kind == "farm":      # the Ostry farm, harvest dusk
        b += [rect(0, 0, w, h, "#e8d7a8", 0, False), _engraved_sky(rng, w, 0, 330, True, "#8a6a2a", 1.8),
              circle(640, 330, 90, FIRE_LT, True, ' stroke-width="4"')]
        for a in range(180, 361, 10):
            b.append(line(640 + 110 * math.cos(math.radians(a)), 330 + 110 * math.sin(math.radians(a)),
                          640 + 170 * math.cos(math.radians(a)), 330 + 170 * math.sin(math.radians(a)), "#8a6a2a", 2.4))
        b.append(f'<rect y="330" width="{w}" height="{h - 330}" fill="#b89a4a"/>')
        b.append(_house_silhouette(930, 340, 220, 110, INK, FIRE_LT))
        for i in range(90):
            x = rng.uniform(0, w)
            y = rng.uniform(360, 720)
            hgt = 10 + (y - 360) / 12
            b.append(line(round(x), round(y), round(x + 2), round(y - hgt), "#6d5520", 1.6))
            b.append(ellipse(round(x + 2), round(y - hgt), 2.4, 5, GOLD, False))
    elif kind == "wendmere":  # the field after the battle, fog
        b += [rect(0, 0, w, h, "#c9c4b6", 0, False), _engraved_sky(rng, w, 0, 380, True, "#8f8a7c", 1.2)]
        b.append(f'<rect y="380" width="{w}" height="{h - 380}" fill="#7d7160"/>')
        b.append(_ground_lines(rng, w, 385, 720, P5))
        for i in range(26):
            x = rng.uniform(0, w)
            y = rng.uniform(380, 520)
            b.append(line(round(x), round(y), round(x + rng.uniform(-60, 60)), round(y - rng.uniform(60, 160)), INK, 3))
        b.append(line(200, 520, 280, 250, INK, 5))
        b.append('<path d="M278,252 L360,280 L330,320 L262,300 Z" fill="%s" stroke="%s" stroke-width="4"/>' % (BLOOD, INK))
        for i in range(12):
            x = rng.uniform(80, 1200)
            y = rng.uniform(60, 240)
            b.append(f'<path d="M{x:.0f},{y:.0f} q8,-8 16,0 q8,-8 16,0" fill="none" stroke="{INK}" stroke-width="3"/>')
        b.append('<rect y="300" width="1280" height="200" fill="#d9d4c8" opacity="0.35"/>')
    elif kind == "snowroad":  # Coldharbour road, winter
        b += [rect(0, 0, w, h, "#e8e6e0", 0, False), _engraved_sky(rng, w, 0, 360, True, "#6f6f73", 1.4)]
        b.append('<path d="M0,370 Q320,340 640,360 T1280,350 L1280,720 L0,720 Z" fill="#f1eee6"/>')
        for x in (70, 210, 400, 880, 1060, 1230):
            b.append(_tree_silhouette(x, 390, rng.uniform(150, 260)))
        b.append('<polygon points="560,720 720,720 660,370 630,370" fill="#d8d6d0"/>')
        for i in range(140):
            b.append(circle(round(rng.uniform(0, w)), round(rng.uniform(0, h)), round(rng.uniform(1.5, 4), 1), "#ffffff", False, ' opacity="0.9"'))
    elif kind == "camp":      # the Sons' fire, night
        defs_id = art.uid("glow")
        art.defs.append(f'<radialGradient id="{defs_id}" cx="0.5" cy="0.62" r="0.55"><stop offset="0" stop-color="{FIRE}" stop-opacity="0.75"/>'
                        f'<stop offset="0.45" stop-color="#5a2a10" stop-opacity="0.5"/><stop offset="1" stop-color="{INK}" stop-opacity="0"/></radialGradient>')
        b += [rect(0, 0, w, h, "#120f0c", 0, False), _engraved_sky(rng, w, 0, 330, False, "#2e2822", 1.4),
              f'<rect width="{w}" height="{h}" fill="url(#{defs_id})"/>']
        for x in (120, 1000):
            b.append(f'<polygon points="{x},440 {x + 110},230 {x + 220},440" fill="{INK}" stroke="#3b332a" stroke-width="4"/>')
        b += [rect(560, 170, 8, 280, P5, 0, False), f'<path d="M568,176 L700,176 L700,300 L634,272 L568,300 Z" fill="{INK}" stroke="#3b332a" stroke-width="4"/>',
              circle(634, 222, 22, GOLD, True, ' stroke-width="3"'), line(604, 192, 664, 252, PAPER, 5)]
        b.append(f'<rect y="440" width="{w}" height="{h - 440}" fill="#231d17"/>')
        b.append(_ground_lines(rng, w, 445, 720, "#3b332a"))
    elif kind == "title":
        b += [rect(0, 0, w, h, "#d9ccad", 0, False), _engraved_sky(rng, w, 0, 470, True, INK, 2.6),
              circle(900, 400, 78, BLOOD, True, ' stroke-width="4"')]
        b.append('<path d="M0,470 Q260,400 520,440 Q780,480 1040,420 Q1180,390 1280,410 L1280,720 L0,720 Z" fill="#cfc2a2"/>')
        b.append('<path d="M760,432 Q800,380 870,400 Q930,420 960,440 Z" fill="%s"/>' % INK)
        b += [rect(846, 250, 10, 170, INK, 0, False), rect(846, 250, 70, 10, INK, 0, False), line(856, 290, 886, 260, INK, 7),
              line(904, 260, 904, 300, INK, 2), path("M892,300 L916,300 L918,350 L890,350 Z", "none", True, "", 3)]
        for (x, y) in ((930, 245), (960, 215), (1010, 240), (880, 205)):
            b.append(f'<path d="M{x},{y} q9,-9 18,0 q9,-9 18,0" fill="none" stroke="{INK}" stroke-width="3.5"/>')
        b.append('<polygon points="560,720 720,720 648,440 638,440" fill="#e9dfc7"/>')
        b.append(line(560, 720, 638, 440, INK, 2))
        b.append(line(720, 720, 648, 440, INK, 2))
        b.append(_ground_lines(rng, w, 480, 720, P4))
        g = figure(CHARS["derrick_man"], art)
        b.append(f'<g transform="translate(622,500) scale(0.62)">{g}</g>')
    return art.svg(w, h, "".join(b), f"0 0 {w} {h}")


# ---------------------------------------------------------------- manifest
ASSETS = {}
for cid, spec in CHARS.items():
    size = 144 if spec.get("build") == "big" else 112
    ASSETS[f"char/{cid}.svg"] = lambda s=spec, z=size: figure_svg(s, z)           # battle sprite
    ASSETS[f"char/{cid}_field.svg"] = lambda s=spec: figure_svg(s, TILE_PX)       # stage sprite
for cid in SPEAKERS:
    ASSETS[f"portrait/{cid}.svg"] = lambda s=CHARS[cid]: portrait_svg(s)
ASSETS["char/gauntley_mounted_field.svg"] = lambda: horse_svg(CHARS["gauntley_helm"], 128)
ASSETS["char/knight_mounted_field.svg"] = lambda: horse_svg(CHARS["man_at_arms"], 128)
ASSETS["char/dog.svg"] = lambda: hound_svg(False, 128)
ASSETS["char/dog_field.svg"] = lambda: hound_svg(False, 64)
ASSETS["char/wolf.svg"] = lambda: hound_svg(True, 160)
ASSETS["char/wolf_field.svg"] = lambda: hound_svg(True, 72)
# articulated rigs: every character body the game moves (see rig_svg / rigs.json)
for cid, spec in CHARS.items():
    size = 144 if spec.get("build") == "big" else 112
    ASSETS[f"rig/{cid}.svg"] = lambda c=cid, s=spec, z=size: figure_rig(c, s, z)
    ASSETS[f"rig/{cid}_field.svg"] = lambda c=cid, s=spec: figure_rig(c + "_field", s, TILE_PX)
ASSETS["rig/gauntley_mounted_field.svg"] = lambda: rig_svg("gauntley_mounted_field", "horse",
                                                           lambda art: horse_parts(art, CHARS["gauntley_helm"]), (96, 80), 128, 18)
ASSETS["rig/knight_mounted_field.svg"] = lambda: rig_svg("knight_mounted_field", "horse",
                                                         lambda art: horse_parts(art, CHARS["man_at_arms"]), (96, 80), 128, 18)
ASSETS["rig/horse.svg"] = lambda: rig_svg("horse", "horse", lambda art: horse_parts(art), (96, 80), 128, 18)
for name, wolf, px in (("dog", False, 128), ("dog_field", False, 64), ("wolf", True, 160), ("wolf_field", True, 72)):
    ASSETS[f"rig/{name}.svg"] = lambda n=name, w=wolf, z=px: rig_svg(n, "hound", lambda art: hound_parts(art, w), (64, 64), z)
ASSETS["rig/crow.svg"] = lambda: rig_svg("crow", "bird", crow_parts, (64, 64), 64)
for k in ("grass", "mud", "snow", "ash", "cobble", "road", "road_snow", "road_mud", "floor", "wall_stone",
          "wall_timber", "roof", "roof_burned", "house_wall", "house_window", "house_burned", "water", "crops", "stubble"):
    ASSETS[f"tile/{k}.svg"] = lambda k=k: tile(k)
for k in ("tree", "pine_snow", "dead_tree", "bush", "well", "cart", "bread_cart", "crate", "barrel", "sack", "hay",
          "grave", "shroud", "fallen", "spears", "lord_banner", "campfire", "hearth", "hatch", "hatch_open", "bed",
          "table", "stool", "door", "almshouse_door", "fence", "fence_v", "wooden_sword", "bread", "tent", "gibbet",
          "sons_banner", "stake_rope", "crow", "horse"):
    ASSETS[f"prop/{k}.svg"] = lambda k=k: prop(k)
for k in ("attack", "skill", "item", "defend", "flee", "bleed", "dazed", "maimed", "fear", "last_stand", "guard",
          "grit", "bread", "rag", "gouge", "skull", "riposte", "wild", "evade", "coin", "cursor", "cursor_down"):
    ASSETS[f"icon/{k}.svg"] = lambda k=k: icon(k)
for k in ("rain", "snow", "ash", "ember", "smoke", "fog"):
    ASSETS[f"fx/{k}.svg"] = lambda k=k: fx(k)
for k in ("green", "alley", "alley_fire", "farm", "wendmere", "snowroad", "camp", "title"):
    ASSETS[f"bg/{k}.svg"] = lambda k=k: background(k)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default="assets/placeholder")
    ap.add_argument("--only", default="", help="comma list of folders, e.g. char,icon")
    ap.add_argument("--list", action="store_true")
    a = ap.parse_args()
    only = {s.strip() for s in a.only.split(",") if s.strip()}
    made = []
    for rel, fn in ASSETS.items():
        if only and rel.split("/")[0] not in only:
            continue
        made.append(rel)
        if a.list:
            continue
        dst = os.path.join(a.out, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with open(dst, "w", encoding="utf-8") as f:
            f.write(fn())
    if not a.list and RIGS:
        with open(os.path.join(a.out, "rigs.json"), "w", encoding="utf-8") as f:
            json.dump({"note": "art key basename -> articulated rig sheet; see tools/make_placeholders.py rig_svg",
                       "rigs": RIGS}, f, indent=1)
    if not a.list:
        with open(os.path.join(a.out, "manifest.json"), "w", encoding="utf-8") as f:
            json.dump({"generator": "tools/make_placeholders.py", "license": "original, project-owned",
                       "tall_props": sorted(PROPS_TALL), "files": made}, f, indent=1)
    print(("would write " if a.list else "wrote ") + f"{len(made)} files to {a.out}")
    if a.list:
        print("\n".join(made))


if __name__ == "__main__":
    main()
