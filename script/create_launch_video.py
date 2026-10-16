#!/usr/bin/env python3
"""Render the 19-second Glee launch clip from a production master.

Requires an isolated Python environment with numpy, opencv-python-headless,
Pillow, and an ffmpeg executable. The master and output must be different files.
"""
import argparse
import json
import math
from pathlib import Path
import subprocess

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
FPS = 60
WIDTH, HEIGHT = 1920, 1080
TITLE_ZONE = (400, 300, 1520, 640)
LINK_ZONE = (500, 640, 1420, 730)
ANCHORS = np.array([
    [307, 955, 400], [309, 954, 291], [312, 951, 234],
    [315, 950, 202], [318, 949, 173], [324, 949, 158],
    [330, 949, 147], [360, 949, 132], [390, 951, 130],
    [420, 955, 120], [450, 957, 111], [480, 959, 100],
    [510, 999, 86], [522, 1078, 74], [528, 1125, 67],
    [534, 1164, 67], [540, 1175, 84], [546, 1132, 137],
    [552, 1037, 274], [555, 980, 390], [558, 920, 515],
], dtype=np.float32)


def expected_center(frame):
    return np.array([np.interp(frame, ANCHORS[:, 0], ANCHORS[:, k])
                     for k in (1, 2)])


def color_marker(frame, number):
    roi = frame[:650, 700:1400]
    b, g, r = cv2.split(roi)
    mask = ((r > 145) & (g > 140) & (b < 170) &
            (r.astype(float) > g * .85)).astype(np.uint8)
    _, _, stats, centers = cv2.connectedComponentsWithStats(mask)
    expected = expected_center(number)
    candidates = []
    for stat, center in zip(stats[1:], centers[1:]):
        x, y, w, h, area = stat
        center = center + (700, 0)
        if 2 <= area < 1800 and 2 <= w < 80 and 2 <= h < 65:
            distance = np.linalg.norm(center - expected)
            if distance < 60:
                candidates.append((distance, stat, center))
    if not candidates:
        return None
    candidates.sort(key=lambda item: item[0])
    best = candidates[0]
    selected = [item for item in candidates
                if np.linalg.norm(item[2] - best[2]) < 27 and item[1][4] >= 5]
    if not selected:
        selected = [best]
    left = min(item[1][0] for item in selected) + 700
    top = min(item[1][1] for item in selected)
    right = max(item[1][0] + item[1][2] for item in selected) + 700
    bottom = max(item[1][1] + item[1][3] for item in selected)
    total = sum(item[1][4] for item in selected)
    center = sum(item[2] * item[1][4] for item in selected) / total
    return [float(center[0]), float(center[1]), right - left, bottom - top]


def tracking(master):
    capture = cv2.VideoCapture(str(master))
    gray, markers = {}, {}
    number = 0
    while True:
        ok, frame = capture.read()
        if not ok:
            break
        if 307 <= number <= 560:
            gray[number] = cv2.cvtColor(cv2.resize(frame, (960, 540)), cv2.COLOR_BGR2GRAY)
            marker = color_marker(frame, number)
            if marker is not None:
                markers[number] = marker
        number += 1
    capture.release()
    if number != 1140:
        raise ValueError("Expected a 19-second, 60 fps production master.")
    ref = gray[480]
    mask = np.zeros_like(ref)
    mask[27:70, 435:948] = 255
    mask[78:178, 830:940] = 255
    mask[8:55, 115:310] = 255
    seeds = cv2.goodFeaturesToTrack(ref, 180, .01, 3, mask=mask, blockSize=5)
    transforms = {480: np.eye(3)}
    scale, inverse = np.diag([2., 2., 1.]), np.diag([.5, .5, 1.])
    for numbers in (range(479, 306, -1), range(481, 523)):
        previous, last, original = ref, seeds.copy(), seeds.copy()
        for number in numbers:
            current = gray[number]
            next_points, status, error = cv2.calcOpticalFlowPyrLK(
                previous, current, last, None, winSize=(31, 31), maxLevel=4)
            back, back_status, _ = cv2.calcOpticalFlowPyrLK(
                current, previous, next_points, None, winSize=(31, 31), maxLevel=4)
            valid = ((status[:, 0] == 1) & (back_status[:, 0] == 1) &
                     (np.linalg.norm(back - last, axis=2)[:, 0] < 1.1) &
                     (error[:, 0] < 40))
            last, original = next_points[valid], original[valid]
            if len(last) < 8:
                break
            homography, _ = cv2.findHomography(original, last, cv2.RANSAC, 1.5)
            if homography is None:
                break
            transforms[number] = scale @ homography @ inverse
            previous = current
    if len(markers) < 235:
        raise ValueError("Too few reliable menu-icon observations.")
    return markers, transforms


def font(size, weight):
    result = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", size)
    result.set_variation_by_axes([100, 96, 400, weight])
    return result


def text_alpha(text, typeface, zone, top):
    x1, y1, x2, y2 = zone
    image = Image.new("L", (x2 - x1, y2 - y1))
    draw = ImageDraw.Draw(image)
    bounds = typeface.getbbox(text)
    width = draw.textlength(text, font=typeface)
    draw.text(((image.width - width) / 2, top - y1 - bounds[1]), text,
              font=typeface, fill=255)
    return np.asarray(image, dtype=np.float32) / 255


def moments(frame, zone):
    x1, y1, x2, y2 = zone
    gray = cv2.cvtColor(frame[y1:y2, x1:x2], cv2.COLOR_BGR2GRAY).astype(float)
    background = float(np.median(gray[:8]))
    darkness = np.maximum(background - gray, 0)
    mass = darkness.sum()
    rows = darkness.sum(axis=1)
    y = np.arange(len(rows))
    center = float((rows * y).sum() / max(mass, 1))
    variance = float((rows * (y - center) ** 2).sum() / max(mass, 1))
    return mass, center, variance


def animated_text(frame, sharp, zone, reference, color):
    mass, center, variance = moments(frame, zone)
    ref_mass, ref_center, ref_variance = reference
    opacity = float(np.clip(mass / ref_mass, 0, 1))
    sigma = min(45, math.sqrt(max(variance - ref_variance, 0)))
    # Preserve the title's small spring overshoot as well as its opacity/blur.
    scale = math.sqrt(max(mass / ref_mass, 1))
    matrix = np.float32([[scale, 0, (1 - scale) * sharp.shape[1] / 2],
                         [0, scale, center - scale * ref_center]])
    alpha = cv2.warpAffine(sharp, matrix, (sharp.shape[1], sharp.shape[0]))
    if sigma > .15:
        alpha = cv2.GaussianBlur(alpha, (0, 0), sigma)
    x1, y1, x2, y2 = zone
    background = frame[y1:y1 + 8, x1:x2].reshape(-1, 3).mean(axis=0)
    base = np.broadcast_to(background, (y2 - y1, x2 - x1, 3)).astype(np.float32)
    a = alpha[..., None] * opacity
    frame[y1:y2, x1:x2] = np.clip(base * (1 - a) + color * a, 0, 255).astype(np.uint8)


def projection(number, marker, transforms):
    cx, cy, w, h = marker
    if number in transforms:
        result = transforms[number].copy()
        original_center = np.float32([[[959.09, 100.31]]])
        predicted = cv2.perspectiveTransform(original_center, result)[0, 0]
        result[0] += (cx - predicted[0]) * result[2]
        result[1] += (cy - predicted[1]) * result[2]
        return result
    sx, sy = max(w / 27, .075), max(h / 19, .075)
    angle = math.radians(float(np.interp(number, [307, 480, 522, 552, 560],
                                        [0, 1, 2, 6.5, 11])))
    shear = float(np.interp(number, [307, 522, 552, 560], [0, 0, .55, 1.0]))
    rotate = np.array([[math.cos(angle), -math.sin(angle)],
                       [math.sin(angle), math.cos(angle)]])
    linear = rotate @ np.array([[sx, sy * shear], [0, sy]])
    result = np.eye(3)
    result[:2, :2] = linear
    result[:2, 2] = np.array([cx, cy]) - linear @ np.array([959.09, 100.31])
    return result


def replace_menu_icon(frame, number, marker, transforms, glyph):
    homography = projection(number, marker, transforms)
    corners = cv2.perspectiveTransform(
        np.float32([[[925, 62], [1022, 62], [1022, 155], [925, 155]]]),
        homography)[0]
    left = max(0, int(np.floor(corners[:, 0].min())) - 5)
    top = max(0, int(np.floor(corners[:, 1].min())) - 5)
    right = min(WIDTH, int(np.ceil(corners[:, 0].max())) + 5)
    bottom = min(HEIGHT, int(np.ceil(corners[:, 1].max())) + 5)
    if right <= left or bottom <= top:
        return
    original = frame[top:bottom, left:right].copy()
    local = np.array([[1, 0, -left], [0, 1, -top], [0, 0, 1.]]) @ homography
    mask_canvas = np.zeros((HEIGHT, WIDTH), dtype=np.uint8)
    cv2.rectangle(mask_canvas, (940, 76), (980, 116), 255, -1)
    old_mask = cv2.warpPerspective(mask_canvas, local, (right - left, bottom - top))
    # Preserve the recorded pointer in front of the replacement.
    pointer = np.zeros(original.shape[:2], dtype=np.uint8)
    dark = (cv2.cvtColor(original, cv2.COLOR_BGR2GRAY) < 65).astype(np.uint8)
    count, labels, stats, _ = cv2.connectedComponentsWithStats(dark)
    scale = max(marker[2] / 27, .1)
    for index in range(1, count):
        x, y, w, h, area = stats[index]
        if 35 * scale * scale < area < 900 * scale * scale and h > 16 * scale and h > w * 1.1:
            pointer[labels == index] = 255
    if pointer.any():
        radius = max(1, int(round(2 * scale)))
        pointer = cv2.dilate(pointer, np.ones((radius * 2 + 1,) * 2, np.uint8))
    # The small dot follows the recorded session state, with monochrome rendering.
    dot_canvas = np.zeros((HEIGHT, WIDTH), dtype=np.uint8)
    cv2.circle(dot_canvas, (993, 95), 9, 255, -1)
    dot_area = cv2.warpPerspective(dot_canvas, local, (right - left, bottom - top))
    b, g, r = cv2.split(original)
    active = (((g.astype(float) - r > 85) & (g.astype(float) - b > 85) &
               (g > 195) & (dot_area > 0)).sum() > max(1, 2 * scale * scale))
    if active:
        old_mask = np.maximum(old_mask, dot_area)
    cleaned = cv2.inpaint(original, (old_mask > 30).astype(np.uint8) * 255,
                         max(2, round(scale * 5)), cv2.INPAINT_TELEA)
    overlay = np.zeros((HEIGHT, WIDTH), dtype=np.float32)
    overlay[79:112, 939:979] = cv2.resize(glyph, (40, 33), interpolation=cv2.INTER_AREA)
    if active:
        cv2.circle(overlay, (993, 95), 4, 1., -1, cv2.LINE_AA)
    alpha = cv2.warpPerspective(overlay, local, (right - left, bottom - top))
    sigma = 12 * math.exp(-max(number / FPS - 5.1167, 0) / .1) + .15
    if sigma > .3:
        alpha = cv2.GaussianBlur(alpha, (0, 0), sigma)
    a = np.clip(alpha[..., None] * .96, 0, 1)
    rendered = (cleaned.astype(float) * (1 - a) + 246 * a).astype(np.uint8)
    if pointer.any():
        colored_marker = ((r > 145) & (g > 140) & (b < 170) &
                          (r.astype(float) > g * .85))
        pointer[colored_marker] = 0
        rendered[pointer > 0] = original[pointer > 0]
    frame[top:bottom, left:right] = rendered


def render(master, output):
    if output.exists() or master.resolve() == output.resolve():
        raise ValueError("Use a new output path outside the master.")
    output.parent.mkdir(parents=True, exist_ok=True)
    markers, transforms = tracking(master)
    numbers = sorted(markers)
    # Interpolate brief tracking gaps without changing the footage's timing.
    stable = {}
    for n in range(min(numbers), max(numbers) + 1):
        stable[n] = [float(np.interp(n, numbers, [markers[k][j] for k in numbers]))
                     for j in range(4)]
    for n in stable:
        nearby = [markers[k] for k in numbers if abs(k - n) <= 2]
        if nearby:
            stable[n][2:] = np.median(np.array(nearby)[:, 2:], axis=0).tolist()
    glyph = np.asarray(Image.open(ROOT / "docs/branding/menu-white-96.png")
                       .convert("RGBA"), dtype=np.float32)[..., 3] / 255
    final_bytes = subprocess.check_output([
        "ffmpeg", "-v", "error", "-ss", "18.5", "-i", str(master),
        "-frames:v", "1", "-f", "rawvideo", "-pix_fmt", "bgr24", "pipe:1"])
    final = np.frombuffer(final_bytes, dtype=np.uint8).reshape(HEIGHT, WIDTH, 3)
    title_ref, link_ref = moments(final, TITLE_ZONE), moments(final, LINK_ZONE)
    title = text_alpha("Glee", font(170, 700), TITLE_ZONE, 468)
    link = text_alpha("github.com/dumpydon/glee", font(36, 550), LINK_ZONE, 656)
    decoder = subprocess.Popen([
        "ffmpeg", "-v", "error", "-i", str(master), "-f", "rawvideo",
        "-pix_fmt", "bgr24", "pipe:1"], stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL)
    log_path = output.with_suffix(".render.log")
    with log_path.open("w") as log:
        process = subprocess.Popen([
            "ffmpeg", "-hide_banner", "-y", "-f", "rawvideo", "-pixel_format", "bgr24",
            "-video_size", "1920x1080", "-framerate", "60", "-i", "pipe:0",
            "-i", str(master), "-map", "0:v:0", "-map", "1:a:0?",
            "-map_metadata", "-1", "-c:v", "libx264", "-crf", "18", "-preset", "medium",
            "-vf", "scale=in_range=pc:out_range=tv:out_color_matrix=bt709",
            "-pix_fmt", "yuv420p", "-color_range", "tv", "-colorspace", "bt709",
            "-color_primaries", "bt709", "-color_trc", "iec61966-2-1",
            "-c:a", "copy", "-movflags", "+faststart",
            "-metadata", "title=Glee launch", "-metadata", "artist=dumpydon",
            "-metadata", "copyright=Copyright 2026 dumpydon", str(output)
        ], stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=log)
        number = 0
        try:
            while True:
                data = decoder.stdout.read(WIDTH * HEIGHT * 3)
                if not data:
                    break
                if len(data) != WIDTH * HEIGHT * 3:
                    raise ValueError("Incomplete decoded frame.")
                frame = np.frombuffer(data, dtype=np.uint8).reshape(HEIGHT, WIDTH, 3).copy()
                if number in stable:
                    replace_menu_icon(frame, number, stable[number], transforms, glyph)
                if number >= 973:
                    animated_text(frame, title, TITLE_ZONE, title_ref, 31)
                    animated_text(frame, link, LINK_ZONE, link_ref, 135)
                process.stdin.write(frame.tobytes())
                number += 1
                if number % 240 == 0:
                    print(f"Rendered {number}/1140 frames", flush=True)
        finally:
            decoder.stdout.close()
            process.stdin.close()
        if decoder.wait() != 0:
            raise ValueError("Production master decode failed.")
        if process.wait() != 0:
            raise ValueError("ffmpeg failed; inspect " + str(log_path))
    if number != 1140:
        raise ValueError("Unexpected output frame count.")
    report = {"frames": number, "fps": FPS, "duration_seconds": 19,
              "resolution": [WIDTH, HEIGHT],
              "icon_tracking_coverage": [min(stable), max(stable)],
              "native_glyph": "docs/branding/menu-white-96.png",
              "audio": "original AAC stream copied",
              "title": "Glee", "link": "github.com/dumpydon/glee"}
    output.with_suffix(".render.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--master", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    render(args.master, args.output)


if __name__ == "__main__":
    main()

