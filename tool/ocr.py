"""Image jobs for the feed builder: OCR, page resizing and item crops.

Called by tool/update_feed.dart with the path of a JSON job file:

    [{"op": "ocr",    "src": "page.jpg", "out": "page.ocr.json"},
     {"op": "flashes", "src": "page.jpg", "out": "page.flashes.json"},
     {"op": "resize", "src": "page.jpg", "out": "view.jpg", "maxHeight": 1500},
     {"op": "crop",   "src": "page.jpg", "out": "item.jpg",
      "x": 10, "y": 20, "w": 300, "h": 300, "maxSide": 360}]

OCR uses RapidOCR (free, open source, runs offline on the CPU).
Set up once with:  pip install rapidocr onnxruntime
"""
import json
import math
import os
import sys

import cv2
import numpy as np


def read_image(path):
    data = np.fromfile(path, dtype=np.uint8)
    img = cv2.imdecode(data, cv2.IMREAD_COLOR)
    if img is None:
        raise ValueError(f"cannot decode {path}")
    return img


def write_jpeg(path, img, quality):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    ok, buf = cv2.imencode(".jpg", img, [cv2.IMWRITE_JPEG_QUALITY, quality])
    if not ok:
        raise ValueError(f"cannot encode {path}")
    buf.tofile(path)


_engine = None


def engine():
    global _engine
    if _engine is None:
        from rapidocr import RapidOCR

        _engine = RapidOCR()
    return _engine


def run_ocr(job):
    img = read_image(job["src"])
    height, width = img.shape[:2]
    # Said in full: reading a price flash (below) turns detection off for
    # its call, and the engine remembers the last settings it was given.
    result = engine()(img, use_det=True, use_cls=True, use_rec=True)
    lines = []
    if result is not None and result.boxes is not None:
        for box, text, score in zip(result.boxes, result.txts, result.scores):
            pts = [(float(p[0]), float(p[1])) for p in box]
            xs = [p[0] for p in pts]
            ys = [p[1] for p in pts]
            # The quad is top-left, top-right, bottom-right, bottom-left, so
            # its side edges give the real text height even when it is tilted.
            left = math.dist(pts[0], pts[3])
            right = math.dist(pts[1], pts[2])
            lines.append(
                {
                    "t": text,
                    "x": round(min(xs)),
                    "y": round(min(ys)),
                    "w": round(max(xs) - min(xs)),
                    "h": round(max(ys) - min(ys)),
                    "th": round((left + right) / 2),
                    "s": round(float(score), 3),
                }
            )
    with open(job["out"], "w", encoding="utf-8") as f:
        json.dump({"width": width, "height": height, "lines": lines}, f)
    return len(lines)


# ------------------------------------------------------------ price flashes
#
# General OCR reads small print well but stumbles on the big stylised digits
# of a price flash: on a page of toys a third of them came back wrong ("K299"
# as "229", "K149" with its raised "99" as "K1499"). Shoprite prints prices
# in red on a yellow flash, so they can be found by colour instead: a red
# blob of digit size whose surroundings are yellow is a digit of a price.
# Digits standing side by side form one price; the full-height ones are the
# kwacha, the small raised ones to their right the ngwee. Each part is cut
# out as clean black-on-white lettering and read on its own.


def _read_glyphs(mask, x0, y0, x1, y1, target=48):
    """Reads the glyphs in a region of a 0/255 mask. Returns (text, score)."""
    crop = mask[y0:y1, x0:x1]
    h, w = crop.shape[:2]
    if h < 3 or w < 3:
        return "", 0.0
    scale = target / h
    crop = cv2.resize(
        crop,
        (max(1, round(w * scale)), target),
        interpolation=cv2.INTER_AREA if scale < 1 else cv2.INTER_CUBIC,
    )
    pad = target // 2
    canvas = np.full((target + 2 * pad, crop.shape[1] + 2 * pad), 255, np.uint8)
    canvas[pad : pad + target, pad : pad + crop.shape[1]] = 255 - crop
    result = engine()(
        cv2.cvtColor(canvas, cv2.COLOR_GRAY2BGR),
        use_det=False,
        use_cls=False,
        use_rec=True,
    )
    if result is None or not result.txts:
        return "", 0.0
    return result.txts[0], float(result.scores[0])


def find_flashes(img):
    """Prices printed red on yellow, and yellow on red."""
    hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
    yellow = cv2.inRange(hsv, (18, 110, 170), (36, 255, 255))
    red = cv2.inRange(hsv, (0, 110, 90), (9, 255, 255)) | cv2.inRange(
        hsv, (170, 110, 90), (180, 255, 255)
    )
    return _find_flashes(img, red, yellow) + _find_flashes(img, yellow, red)


def _find_flashes(img, ink, ground):
    """ink: mask of the lettering's colour; ground: of the colour around it."""
    height, width = img.shape[:2]
    n, _, stats, _ = cv2.connectedComponentsWithStats(ink, 8)
    ground_sum = cv2.integral(ground // 255)
    ink_sum = cv2.integral(ink // 255)
    # Starburst prices have a black outline round each digit. It is neither
    # lettering nor background, so it is left out of the count.
    dark = cv2.inRange(cv2.cvtColor(img, cv2.COLOR_BGR2HSV), (0, 0, 0), (180, 255, 80))
    dark_sum = cv2.integral(dark // 255)

    def count(integral, x0, y0, x1, y1):
        return int(
            integral[y1, x1] - integral[y0, x1] - integral[y1, x0] + integral[y0, x0]
        )

    glyphs = []
    for i in range(1, n):
        x, y, w, h, area = (int(v) for v in stats[i])
        if h < 0.005 * height or h > 0.13 * height or w > 0.12 * width:
            continue
        if area < 0.18 * w * h:
            continue
        m = max(3, round(0.3 * h))
        x0, y0 = max(0, x - m), max(0, y - m)
        x1, y1 = min(width, x + w + m), min(height, y + h + m)
        box = (x1 - x0) * (y1 - y0)
        around = box - count(ink_sum, x0, y0, x1, y1) - count(dark_sum, x0, y0, x1, y1)
        if around < 0.15 * box:
            continue
        if count(ground_sum, x0, y0, x1, y1) / around < 0.6:
            continue
        glyphs.append((x, y, w, h))

    # Glyphs standing side by side belong to one price.
    parent = list(range(len(glyphs)))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    for a in range(len(glyphs)):
        ax, ay, aw, ah = glyphs[a]
        for b in range(a + 1, len(glyphs)):
            bx, by, bw, bh = glyphs[b]
            tall = max(ah, bh)
            if min(ah, bh) < 0.25 * tall:
                continue
            if max(bx - (ax + aw), ax - (bx + bw)) > 0.5 * tall:
                continue
            if ay < by + bh and by < ay + ah:
                parent[find(a)] = find(b)
    groups = {}
    for i, g in enumerate(glyphs):
        groups.setdefault(find(i), []).append(g)

    flashes = []
    for group in groups.values():
        tall = max(g[3] for g in group)
        if tall < 0.014 * height:
            continue
        big = [g for g in group if g[3] >= 0.7 * tall]
        bx0 = min(g[0] for g in big)
        bx1 = max(g[0] + g[2] for g in big)
        by0 = min(g[1] for g in big)
        by1 = max(g[1] + g[3] for g in big)
        kwacha, ks = _read_glyphs(ink, bx0, by0, bx1, by1)
        if not kwacha.isdigit() or len(kwacha) > 5:
            continue  # a red word on a yellow banner, not a price
        raised = [
            g
            for g in group
            if g[3] < 0.7 * tall
            and g[0] >= bx1 - 0.15 * tall
            and g[1] < by0 + 0.4 * tall
        ]
        ngwee, ns = "", 0.0
        if raised:
            ngwee, ns = _read_glyphs(
                ink,
                min(g[0] for g in raised),
                min(g[1] for g in raised),
                max(g[0] + g[2] for g in raised),
                max(g[1] + g[3] for g in raised),
            )
        x0 = min(g[0] for g in group)
        y0 = min(g[1] for g in group)
        flashes.append(
            {
                "x": x0,
                "y": y0,
                "w": max(g[0] + g[2] for g in group) - x0,
                "h": max(g[1] + g[3] for g in group) - y0,
                # Height of the full-size digits.
                "th": by1 - by0,
                "kwacha": kwacha,
                "ks": round(ks, 3),
                # Empty when the price is in whole kwacha; anything other
                # than two digits means the raised part was not read.
                "ngwee": ngwee,
                "ns": round(ns, 3),
                "raised": len(raised),
            }
        )
    return flashes


def run_flashes(job):
    img = read_image(job["src"])
    height, width = img.shape[:2]
    flashes = find_flashes(img)
    with open(job["out"], "w", encoding="utf-8") as f:
        json.dump({"width": width, "height": height, "flashes": flashes}, f)
    return len(flashes)


def run_resize(job):
    img = read_image(job["src"])
    height, width = img.shape[:2]
    max_h = job.get("maxHeight", 1500)
    if height > max_h:
        scale = max_h / height
        img = cv2.resize(
            img, (round(width * scale), max_h), interpolation=cv2.INTER_AREA
        )
    write_jpeg(job["out"], img, job.get("quality", 76))
    return img.shape[1], img.shape[0]


_cache = {}


def run_crop(job):
    src = job["src"]
    if src not in _cache:
        _cache.clear()
        _cache[src] = read_image(src)
    img = _cache[src]
    height, width = img.shape[:2]
    x = max(0, min(width - 1, int(job["x"])))
    y = max(0, min(height - 1, int(job["y"])))
    w = max(1, min(width - x, int(job["w"])))
    h = max(1, min(height - y, int(job["h"])))
    crop = img[y : y + h, x : x + w]
    max_side = job.get("maxSide", 360)
    longest = max(w, h)
    if longest > max_side:
        scale = max_side / longest
        crop = cv2.resize(
            crop,
            (max(1, round(w * scale)), max(1, round(h * scale))),
            interpolation=cv2.INTER_AREA,
        )
    write_jpeg(job["out"], crop, job.get("quality", 80))


def main():
    with open(sys.argv[1], encoding="utf-8") as f:
        jobs = json.load(f)
    failures = 0
    for i, job in enumerate(jobs, 1):
        try:
            if job["op"] == "ocr":
                n = run_ocr(job)
                print(f"[{i}/{len(jobs)}] ocr {n} lines  {os.path.basename(job['src'])}", flush=True)
            elif job["op"] == "flashes":
                n = run_flashes(job)
                print(f"[{i}/{len(jobs)}] prices {n} flashes  {os.path.basename(job['src'])}", flush=True)
            elif job["op"] == "resize":
                w, h = run_resize(job)
                print(f"[{i}/{len(jobs)}] page {w}x{h}  {os.path.basename(job['out'])}", flush=True)
            elif job["op"] == "crop":
                run_crop(job)
        except Exception as e:  # keep going: one bad page must not stop the run
            failures += 1
            print(f"[{i}/{len(jobs)}] FAILED {job.get('op')} {job.get('src')}: {e}", flush=True)
    print(f"done, {failures} failed", flush=True)


if __name__ == "__main__":
    main()
