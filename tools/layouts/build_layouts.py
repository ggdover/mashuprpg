#!/usr/bin/env python3
"""Build the act layouts (data/layouts/act_<act>.json) from layout specs (tools/layouts/specs/).

    python3 tools/layouts/build_layouts.py              # every spec
    python3 tools/layouts/build_layouts.py desert       # one act
    python3 tools/layouts/build_layouts.py --preview    # also write docs/screenshots/acts/layouts/<act>.png

A layout says, per 2 x 2 m grid cell, which region of the act's outdoor map it belongs to ('.' = not
walkable). The act generator (scripts/world/acts/act_<act>.gd) reads it with WorldActGen.use_layout()
and fills every region with content; WorldActComposite then adds the town (the act's hub) at the
layout's town exit. Two kinds of specs:

  "drawing": a hand drawing like tools/layouts/drawings/act2_layout.png — closed outlines drawn in
     any paint program: every blob is an area you can walk in, blobs touching through gaps in their
     outlines are connected (the gaps are the paths between zones), outlines inside a blob are
     holes (not walkable). The spec gives the drawing's scale (metres per pixel), a seed point
     inside every region (where its label is written), the town's seed (the town blob is replaced
     by the act's real town; the exit is where it met the rest) and the dungeon box's seed + door
     (the dungeon is a separate area; the door is the spot on the region's edge next to it).
  "blobs": procedural shapes: rounded blobs (centre, size in metres) joined by paths (width).

Regions are split at the narrowest part of the passages between them (a seeded watershed on the
distance to the nearest non-walkable cell), so a zone border lies in the path between two zones.

Pure Python + Pillow. OWNER: acts framework.
"""

import heapq
import json
import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
SPECS = os.path.join(HERE, "specs")
OUT_DIR = os.path.join(REPO, "data", "layouts")
PREVIEW_DIR = os.path.join(REPO, "docs", "screenshots", "acts", "layouts")
LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
N4 = ((1, 0), (-1, 0), (0, 1), (0, -1))
N8 = N4 + ((1, 1), (1, -1), (-1, 1), (-1, -1))


# ----------------------------------------------------------------------------------- small grid helpers

class Grid:
    """A w x h byte grid (list of bytearrays would be slower to index; one flat bytearray)."""

    def __init__(self, w, h, fill=0):
        self.w = w
        self.h = h
        self.a = bytearray([fill]) * (w * h)

    def get(self, x, y):
        return self.a[y * self.w + x]

    def set(self, x, y, v):
        self.a[y * self.w + x] = v

    def inside(self, x, y):
        return 0 <= x < self.w and 0 <= y < self.h


def distance_field(mask):
    """Chamfer (3-4) distance in cells from every walkable cell to the nearest non-walkable one."""
    w, h = mask.w, mask.h
    big = 1 << 28
    d = [0 if mask.a[i] == 0 else big for i in range(w * h)]
    for y in range(h):
        for x in range(w):
            i = y * w + x
            if d[i] == 0:
                continue
            best = d[i]
            if x > 0:
                best = min(best, d[i - 1] + 3)
            else:
                best = 3
            if y > 0:
                best = min(best, d[i - w] + 3)
                if x > 0:
                    best = min(best, d[i - w - 1] + 4)
                if x < w - 1:
                    best = min(best, d[i - w + 1] + 4)
            else:
                best = 3
            d[i] = best
    for y in range(h - 1, -1, -1):
        for x in range(w - 1, -1, -1):
            i = y * w + x
            if d[i] == 0:
                continue
            best = d[i]
            if x < w - 1:
                best = min(best, d[i + 1] + 3)
            else:
                best = min(best, 3)
            if y < h - 1:
                best = min(best, d[i + w] + 3)
                if x < w - 1:
                    best = min(best, d[i + w + 1] + 4)
                if x > 0:
                    best = min(best, d[i + w - 1] + 4)
            else:
                best = min(best, 3)
            d[i] = best
    return [v / 3.0 for v in d]


def watershed(mask, seeds):
    """Seeded watershed: flood the walkable cells from the seeds, deepest cells (farthest from a
    wall) first, so fronts meet at the narrowest part of the passages. seeds: [(label, x, y)].
    Returns a list of labels (0 = none) per cell."""
    w, h = mask.w, mask.h
    dist = distance_field(mask)
    lab = [0] * (w * h)
    heap = []
    order = 0
    for label, sx, sy in seeds:
        if not mask.inside(sx, sy) or mask.get(sx, sy) == 0:
            raise SystemExit("seed of label %d at cell (%d, %d) is not on walkable ground" % (label, sx, sy))
        i = sy * w + sx
        lab[i] = label
        for dx, dy in N4:
            nx, ny = sx + dx, sy + dy
            if mask.inside(nx, ny) and mask.get(nx, ny):
                order += 1
                heapq.heappush(heap, (-dist[ny * w + nx], order, nx, ny, label))
    while heap:
        _, _, x, y, label = heapq.heappop(heap)
        i = y * w + x
        if lab[i]:
            continue
        lab[i] = label
        for dx, dy in N4:
            nx, ny = x + dx, y + dy
            if mask.inside(nx, ny) and mask.get(nx, ny) and not lab[ny * w + nx]:
                order += 1
                heapq.heappush(heap, (-dist[ny * w + nx], order, nx, ny, label))
    return lab, dist


def components(img_mask, w, h, value):
    """4-connected components of the pixels equal to `value` in a flat bytearray. Returns
    (labels list, count). Labels start at 1."""
    lab = [0] * (w * h)
    n = 0
    for start in range(w * h):
        if img_mask[start] != value or lab[start]:
            continue
        n += 1
        lab[start] = n
        stack = [start]
        while stack:
            i = stack.pop()
            x, y = i % w, i // w
            if x > 0 and img_mask[i - 1] == value and not lab[i - 1]:
                lab[i - 1] = n
                stack.append(i - 1)
            if x < w - 1 and img_mask[i + 1] == value and not lab[i + 1]:
                lab[i + 1] = n
                stack.append(i + 1)
            if y > 0 and img_mask[i - w] == value and not lab[i - w]:
                lab[i - w] = n
                stack.append(i - w)
            if y < h - 1 and img_mask[i + w] == value and not lab[i + w]:
                lab[i + w] = n
                stack.append(i + w)
    return lab, n


# ----------------------------------------------------------------------------------- drawing specs

def walkable_from_drawing(spec):
    """The walkable mask (cells) of a hand drawing: closed outlines, holes by parity."""
    src = spec["source"]
    path = os.path.join(REPO, src["path"])
    im = Image.open(path).convert("RGBA")
    bg = Image.new("RGBA", im.size, (255, 255, 255, 255))
    bg.alpha_composite(im)
    gray = bg.convert("L")
    thr = int(src.get("line_threshold", 170))
    lines_full = gray.point(lambda v: 255 if v < thr else 0)
    red = int(src.get("reduce", 4))
    W0, H0 = lines_full.size
    lines = lines_full.reduce(red).point(lambda v: 255 if v > 6 else 0)
    draw = ImageDraw.Draw(lines)
    # Labels are text, not outlines: erase a box around every seed (the label positions).
    # Each entry may give its own "label_box" [half width, half height] (drawing pixels).
    default_box = src.get("label_box", [150, 40])
    labelled = list(spec["regions"])
    for extra in ("town", "dungeon"):
        if extra in spec and "seed" in spec[extra]:
            labelled.append(spec[extra])
    for entry in labelled:
        p = entry["seed"]
        ex, ey = entry.get("label_box", default_box)
        draw.rectangle(((p[0] - ex) / red, (p[1] - ey) / red, (p[0] + ex) / red, (p[1] + ey) / red), fill=0)
    # Extra separator lines ("cuts", in drawing pixels).
    for cut in src.get("cuts", []):
        pts = [(p[0] / red, p[1] / red) for p in cut]
        draw.line(pts, fill=255, width=2)
    close = int(src.get("close_px", 5))
    if close > 1:
        lines = lines.filter(ImageFilter.MaxFilter(close | 1))
    # Pad so the outside is one connected component.
    w, h = lines.size[0] + 4, lines.size[1] + 4
    padded = Image.new("L", (w, h), 0)
    padded.paste(lines, (2, 2))
    px = bytearray(padded.tobytes())
    lab, n = components(px, w, h, 0)
    exterior = lab[0]
    # Adjacency of the spaces across lines.
    reach = close // 2 + 2
    adj = [set() for _ in range(n + 1)]
    for i in range(w * h):
        if px[i] == 0:
            continue
        x, y = i % w, i // w
        found = set()
        for dx, dy in ((reach, 0), (-reach, 0), (0, reach), (0, -reach)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h:
                l2 = lab[ny * w + nx]
                if l2:
                    found.add(l2)
        if len(found) > 1:
            for a in found:
                adj[a] |= found
    depth = [-1] * (n + 1)
    depth[exterior] = 0
    queue = [exterior]
    while queue:
        nxt = []
        for c in queue:
            for o in adj[c]:
                if depth[o] < 0:
                    depth[o] = depth[c] + 1
                    nxt.append(o)
        queue = nxt
    # Walkable = inside an odd number of outlines; keep only the spaces holding a region or town
    # seed (drops the dungeon box and the stray bits between its door lines).
    keep = set()
    seed_pts = [r["seed"] for r in spec["regions"]]
    if "seed" in spec.get("town", {}):
        seed_pts.append(spec["town"]["seed"])
    for p in seed_pts:
        sx, sy = int(p[0] / red) + 2, int(p[1] / red) + 2
        l2 = lab[sy * w + sx]
        if l2 and depth[l2] % 2 == 1:
            keep.add(l2)
        else:
            raise SystemExit("seed %s lies on an outline or outside every blob (component %d, depth %d)" % (p, l2, depth[l2] if l2 else -1))
    walk = bytearray(w * h)
    for i in range(w * h):
        if lab[i] in keep:
            walk[i] = 255
    walk_img = Image.frombytes("L", (w, h), bytes(walk)).crop((2, 2, w - 2, h - 2))
    # Grow back into the (thickened) outlines, never into the outside.
    grow = close // 2 + 1
    if grow > 0:
        grown = walk_img.filter(ImageFilter.MaxFilter(2 * grow + 1))
        line_px = lines.tobytes()
        wb = bytearray(walk_img.tobytes())
        gb = grown.tobytes()
        for i in range(len(wb)):
            if gb[i] and line_px[i]:
                wb[i] = 255
        walk_img = Image.frombytes("L", walk_img.size, bytes(wb))
    # Resample to the cell grid.
    m_px = float(src["m_per_px"]) * red
    cell = float(spec.get("cell_m", 2.0))
    cw = max(1, round(walk_img.size[0] * m_px / cell))
    ch = max(1, round(walk_img.size[1] * m_px / cell))
    cells = walk_img.resize((cw, ch), Image.BOX).point(lambda v: 255 if v >= 128 else 0)
    mask = Grid(cw, ch)
    cb = cells.tobytes()
    for i in range(cw * ch):
        mask.a[i] = 1 if cb[i] else 0
    to_cell = lambda p: (int(p[0] * float(src["m_per_px"]) / cell), int(p[1] * float(src["m_per_px"]) / cell))
    return mask, to_cell


def nearest_walkable(mask, x, y, r=12):
    if mask.inside(x, y) and mask.get(x, y):
        return x, y
    best = None
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            nx, ny = x + dx, y + dy
            if mask.inside(nx, ny) and mask.get(nx, ny):
                d = dx * dx + dy * dy
                if best is None or d < best[0]:
                    best = (d, nx, ny)
    if best is None:
        raise SystemExit("no walkable cell near (%d, %d)" % (x, y))
    return best[1], best[2]


# ----------------------------------------------------------------------------------- blob specs

def walkable_from_blobs(spec):
    """Rounded, wobbly blobs (regions) joined by paths; all in metres."""
    cell = float(spec.get("cell_m", 2.0))
    rng = random.Random(int(spec["source"].get("seed", 1)))
    regions = spec["regions"]
    lo_x = min(r["center"][0] - r["size"][0] / 2 for r in regions) - 20
    lo_y = min(r["center"][1] - r["size"][1] / 2 for r in regions) - 20
    hi_x = max(r["center"][0] + r["size"][0] / 2 for r in regions) + 20
    hi_y = max(r["center"][1] + r["size"][1] / 2 for r in regions) + 60
    cw = int((hi_x - lo_x) / cell) + 1
    ch = int((hi_y - lo_y) / cell) + 1
    mask = Grid(cw, ch)
    tocell = lambda p: (int((p[0] - lo_x) / cell), int((p[1] - lo_y) / cell))
    for r in regions:
        cx, cy = r["center"]
        a, b = r["size"][0] / 2.0, r["size"][1] / 2.0
        n = float(r.get("roundness", 2.8))
        wob = float(r.get("wobble", 0.1))
        ph = [rng.uniform(0, math.tau) for _ in range(4)]
        amp = [wob, wob * 0.6, wob * 0.35, wob * 0.2]
        freq = [2, 3, 5, 7]
        x0, y0 = tocell((cx - a * 1.4, cy - b * 1.4))
        x1, y1 = tocell((cx + a * 1.4, cy + b * 1.4))
        for yy in range(max(0, y0), min(ch, y1 + 1)):
            for xx in range(max(0, x0), min(cw, x1 + 1)):
                px_ = lo_x + (xx + 0.5) * cell - cx
                py_ = lo_y + (yy + 0.5) * cell - cy
                ang = math.atan2(py_ / b, px_ / a)
                k = 1.0 + sum(amp[i] * math.sin(freq[i] * ang + ph[i]) for i in range(4))
                v = (abs(px_) / (a * k)) ** n + (abs(py_) / (b * k)) ** n
                if v <= 1.0:
                    mask.set(xx, yy, 1)
    centers = {r["id"]: r["center"] for r in regions}
    for p in spec.get("paths", []):
        pts = [centers[p["a"]]] + p.get("via", []) + [centers[p["b"]]]
        half = float(p.get("width", 16)) / 2.0 / cell
        for k in range(len(pts) - 1):
            ax, ay = tocell(pts[k])
            bx, by = tocell(pts[k + 1])
            steps = max(1, int(math.hypot(bx - ax, by - ay) * 2))
            for s in range(steps + 1):
                t = s / steps
                # a gentle meander
                off = math.sin(t * math.pi * 2 + k) * half * 0.35
                nxv, nyv = -(by - ay), (bx - ax)
                ln = math.hypot(nxv, nyv) or 1.0
                mx = ax + (bx - ax) * t + nxv / ln * off
                my = ay + (by - ay) * t + nyv / ln * off
                r_ = int(math.ceil(half))
                for dy in range(-r_, r_ + 1):
                    for dx in range(-r_, r_ + 1):
                        if dx * dx + dy * dy <= half * half:
                            xx, yy = int(mx) + dx, int(my) + dy
                            if mask.inside(xx, yy):
                                mask.set(xx, yy, 1)
    return mask, lambda p: tocell(p)


# ----------------------------------------------------------------------------------- build

def build(act, preview=False):
    spec_path = os.path.join(SPECS, act + ".json")
    with open(spec_path) as f:
        spec = json.load(f)
    kind = spec["source"]["kind"]
    if kind == "drawing":
        mask, to_cell = walkable_from_drawing(spec)
    else:
        mask, to_cell = walkable_from_blobs(spec)
    regions = spec["regions"]
    seeds = []
    labels = {}
    k = 0
    for r in regions:
        k += 1
        labels[r["id"]] = k
        sx, sy = to_cell(r["seed"] if "seed" in r else r["center"])
        sx, sy = nearest_walkable(mask, sx, sy)
        seeds.append((k, sx, sy))
    town = spec.get("town", {})
    town_label = 0
    if "seed" in town:
        k += 1
        town_label = k
        tx, ty = nearest_walkable(mask, *to_cell(town["seed"]))
        seeds.append((town_label, tx, ty))
    lab, dist = watershed(mask, seeds)
    w, h = mask.w, mask.h
    # The town exit: region cells next to the town's, or (blobs) the given point.
    exit_cells = []
    if town_label:
        for y in range(h):
            for x in range(w):
                i = y * w + x
                if lab[i] and lab[i] != town_label:
                    for dx, dy in N4:
                        nx, ny = x + dx, y + dy
                        if mask.inside(nx, ny) and lab[ny * w + nx] == town_label:
                            exit_cells.append((x, y))
                            break
        for i in range(w * h):
            if lab[i] == town_label:
                lab[i] = 0
    else:
        ex, ey = to_cell(town["at"])
        ex, ey = nearest_walkable(mask, ex, ey)
        exit_cells = [(ex, ey)]
    if not exit_cells:
        raise SystemExit("%s: no town exit found" % act)
    exit_x = sum(c[0] for c in exit_cells) / len(exit_cells)
    exit_y = sum(c[1] for c in exit_cells) / len(exit_cells)
    exit_dir = town.get("exit_dir", [0, 1])
    # Unreached walkable cells (separate components: the dungeon box...) are dropped.
    for i in range(w * h):
        if not lab[i]:
            mask.a[i] = 0
    # Crop to the walkable bounds (+ margin).
    xs = [i % w for i in range(w * h) if lab[i]]
    ys = [i // w for i in range(w * h) if lab[i]]
    margin = int(spec.get("margin_cells", 3))
    x0, x1 = max(0, min(xs) - margin), min(w - 1, max(xs) + margin)
    y0, y1 = max(0, min(ys) - margin), min(h - 1, max(ys) + margin)
    # The exit must reach the grid edge in its direction: extend the crop so the edge is close.
    cw, ch = x1 - x0 + 1, y1 - y0 + 1
    rows = []
    for y in range(y0, y1 + 1):
        row = []
        for x in range(x0, x1 + 1):
            l2 = lab[y * w + x]
            row.append(LETTERS[l2 - 1] if l2 else ".")
        rows.append("".join(row))
    # Region stats.
    out_regions = []
    for r in regions:
        l2 = labels[r["id"]]
        cells = [(i % w - x0, i // w - y0) for i in range(w * h) if lab[i] == l2]
        if not cells:
            raise SystemExit("%s: region %s has no cells" % (act, r["id"]))
        deep = max(cells, key=lambda c: dist[(c[1] + y0) * w + c[0] + x0])
        bx0 = min(c[0] for c in cells)
        by0 = min(c[1] for c in cells)
        bx1 = max(c[0] for c in cells)
        by1 = max(c[1] for c in cells)
        entry = {k2: v for k2, v in r.items() if k2 not in ("seed", "center", "size", "roundness", "wobble")}
        entry.update({
            "letter": LETTERS[l2 - 1],
            "cells": len(cells),
            "area_m2": len(cells) * spec.get("cell_m", 2.0) ** 2,
            "bbox": [bx0, by0, bx1, by1],
            "centroid": [round(sum(c[0] for c in cells) / len(cells), 1), round(sum(c[1] for c in cells) / len(cells), 1)],
            "deepest": [deep[0], deep[1]],
        })
        out_regions.append(entry)
    # Links: pairs of regions sharing a border, and where.
    pairs = {}
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            a = lab[y * w + x]
            if not a:
                continue
            for dx, dy in ((1, 0), (0, 1)):
                nx, ny = x + dx, y + dy
                if nx <= x1 and ny <= y1:
                    b = lab[ny * w + nx]
                    if b and b != a:
                        key = (min(a, b), max(a, b))
                        pairs.setdefault(key, []).append((x - x0 + dx * 0.5, y - y0 + dy * 0.5))
    ids = {labels[r["id"]]: r["id"] for r in regions}
    links = []
    for (a, b), pts in sorted(pairs.items()):
        mx = sum(p[0] for p in pts) / len(pts)
        my = sum(p[1] for p in pts) / len(pts)
        links.append({"a": ids[a], "b": ids[b], "at": [round(mx, 1), round(my, 1)], "width_cells": len(pts)})
    # The dungeon door: the named region's cell nearest the given point.
    dungeon = {}
    if "dungeon" in spec:
        d = spec["dungeon"]
        dl = labels[d["region"]]
        tx, ty = to_cell(d["door"])
        best = None
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if lab[y * w + x] == dl:
                    dd = (x - tx) ** 2 + (y - ty) ** 2
                    if best is None or dd < best[0]:
                        best = (dd, x, y)
        dungeon = {"region": d["region"], "cell": [best[1] - x0, best[2] - y0], "dir": d.get("dir", [0, 1])}
    out = {
        "act": act,
        "cell_m": spec.get("cell_m", 2.0),
        "size": [cw, ch],
        "source": spec["source"].get("path", "procedural"),
        "regions": out_regions,
        "links": links,
        "exit": {"to": "hub", "cell": [round(exit_x - x0, 1), round(exit_y - y0, 1)], "dir": exit_dir},
        "dungeon": dungeon,
        "rows": rows,
    }
    os.makedirs(OUT_DIR, exist_ok=True)
    tmp = os.path.join(OUT_DIR, "act_%s.json.tmp" % act)
    with open(tmp, "w") as f:
        json.dump(out, f, separators=(",", ":"))
    os.replace(tmp, os.path.join(OUT_DIR, "act_%s.json" % act))
    total = sum(r["cells"] for r in out_regions)
    print("[layouts] %s: %d x %d cells (%.0f x %.0f m), %d walkable cells (%.0f m2), %d regions, %d links" % (
        act, cw, ch, cw * out["cell_m"], ch * out["cell_m"], total, total * out["cell_m"] ** 2, len(out_regions), len(links)))
    for r in out_regions:
        bb = r["bbox"]
        print("           %-12s %-26s %6d cells  %4.0f x %4.0f m  level +%s" % (
            r["id"], r.get("name", ""), r["cells"], (bb[2] - bb[0] + 1) * out["cell_m"], (bb[3] - bb[1] + 1) * out["cell_m"], r.get("level", 0)))
    for l in links:
        print("           link %s <-> %s at %s (%d cells)" % (l["a"], l["b"], l["at"], l["width_cells"]))
    if preview:
        write_preview(out)
    return out


PALETTE = [(222, 190, 120), (120, 190, 110), (110, 160, 210), (200, 120, 110), (170, 130, 200),
           (220, 170, 90), (110, 200, 190), (190, 190, 120), (150, 150, 150)]


def write_preview(out):
    cw, ch = out["size"]
    s = 4
    img = Image.new("RGB", (cw * s, ch * s), (40, 36, 32))
    px = img.load()
    letter_col = {r["letter"]: PALETTE[i % len(PALETTE)] for i, r in enumerate(out["regions"])}
    for y, row in enumerate(out["rows"]):
        for x, c in enumerate(row):
            if c == ".":
                continue
            col = letter_col[c]
            for dy in range(s):
                for dx in range(s):
                    px[x * s + dx, y * s + dy] = col
    d = ImageDraw.Draw(img)
    try:
        font = ImageFont.truetype("DejaVuSans.ttf", 14)
    except OSError:
        font = ImageFont.load_default()
    for r in out["regions"]:
        cx, cy = r["centroid"]
        d.text((cx * s - 40, cy * s), "%s (+%s)" % (r.get("name", r["id"]), r.get("level", 0)), fill=(20, 20, 20), font=font)
    ex, ey = out["exit"]["cell"]
    d.ellipse((ex * s - 6, ey * s - 6, ex * s + 6, ey * s + 6), outline=(255, 255, 255), width=2)
    d.text((ex * s + 8, ey * s - 8), "town", fill=(255, 255, 255), font=font)
    if out["dungeon"]:
        dx, dy = out["dungeon"]["cell"]
        d.rectangle((dx * s - 6, dy * s - 6, dx * s + 6, dy * s + 6), outline=(0, 0, 0), width=3)
        d.text((dx * s + 8, dy * s), "dungeon", fill=(0, 0, 0), font=font)
    d.text((6, 6), "%s: %d x %d m (1 px = %.1f m)" % (out["act"], cw * out["cell_m"], ch * out["cell_m"], out["cell_m"] / s), fill=(255, 255, 255), font=font)
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    path = os.path.join(PREVIEW_DIR, "%s_layout.png" % out["act"])
    img.save(path)
    print("[layouts] preview -> %s" % os.path.relpath(path, REPO))


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    preview = "--preview" in sys.argv
    acts = args or sorted(f[:-5] for f in os.listdir(SPECS) if f.endswith(".json"))
    for act in acts:
        build(act, preview)


if __name__ == "__main__":
    main()
