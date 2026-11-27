"""Image jobs for the feed builder: OCR, page resizing and item crops.

Called by tool/update_feed.dart with the path of a JSON job file:

    [{"op": "ocr",    "src": "page.jpg", "out": "page.ocr.json"},
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
    result = engine()(img)
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
