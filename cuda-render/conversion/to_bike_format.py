"""
to_bike_format.py  -  turn raw renderer output into the `bike` dataset layout.

The bike dataset stores, per sample folder
    <root>/<shininess>/<model>/shine_..-rot_..-shift_../
exactly 6 files:
    confocal-0-*.hdr / .png          (frontal confocal image)
    depth-0-*.hdr    / .png          (frontal depth map)
    video-confocal-gray-full.mp4     (clean transient video)
    video-confocalspad-gray-full.mp4 (SPAD-noise transient video)

The raw renderer instead produces many confocal-*/depth-*/original-* views plus
the transient `light-1-*.hdr`. This script keeps the frontal (id 0) confocal +
depth and converts the transient into the two videos, mirroring the bike layout.

Usage:
    python to_bike_format.py <raw_root> <out_root> --timebin 2048 --hw 64

Note: the true `confocalspad` in the published bike set comes from a dedicated
SPAD simulator (graphics.unizar.es/data/spad). Here we approximate it with
Poisson shot noise + Gaussian read noise so the file/structure matches.
"""
import argparse
import glob
import os
import shutil

import numpy as np
import cv2

np.random.seed(123456)   # reproducible SPAD noise


def _one(folder, pattern):
    hits = sorted(glob.glob(os.path.join(folder, pattern)))
    return hits[0] if hits else None


def _load_transient_gray(light_hdr, T, H, W):
    """light-1-*.hdr  ->  (T,H,W) grayscale float in [0,1]."""
    im = cv2.imread(light_hdr, cv2.IMREAD_UNCHANGED)          # (T*H, W, 3) BGR
    if im is None or im.shape != (T * H, W, 3):
        raise SystemExit("bad transient %s shape=%s expected %s" %
                         (light_hdr, None if im is None else im.shape, (T * H, W, 3)))
    im = im.astype(np.float32)
    m = im.max()
    if m > 0:
        im = im / m
    gray = cv2.cvtColor(im, cv2.COLOR_BGR2GRAY)              # (T*H, W)
    gm = gray.max()
    if gm > 0:
        gray = gray / gm
    return gray.reshape(T, H, W)


def _spad_noise(vol, photons=200.0, read=0.02):
    """Approximate SPAD acquisition: Poisson shot noise + Gaussian read noise."""
    lam = np.clip(vol, 0, None) * photons
    noisy = np.random.poisson(lam).astype(np.float32) / photons
    noisy = noisy + read * np.random.randn(*noisy.shape).astype(np.float32)
    noisy = np.clip(noisy, 0, None)
    m = noisy.max()
    return noisy / m if m > 0 else noisy


def _write_video(vol_thw, path, fps=20):
    """(T,H,W) in [0,1] grayscale -> mp4 (gray tiled to 3 channels)."""
    T, H, W = vol_thw.shape
    fourcc = cv2.VideoWriter_fourcc(*'mp4v')
    out = cv2.VideoWriter(path, fourcc, fps, (W, H))
    for t in range(T):
        frame = np.clip(vol_thw[t] * 255.0, 0, 255).astype(np.uint8)
        out.write(cv2.cvtColor(frame, cv2.COLOR_GRAY2BGR))
    out.release()


def process_sample(raw_dir, out_dir, T, H, W):
    os.makedirs(out_dir, exist_ok=True)

    # 1) frontal confocal + depth (id 0), both hdr and png
    copied = 0
    for name in ("confocal-0-*", "depth-0-*"):
        for ext in ("hdr", "png"):
            f = _one(raw_dir, name + "." + ext)
            if f:
                shutil.copy(f, out_dir)
                copied += 1

    # 2) transient -> clean + spad videos
    light = _one(raw_dir, "light-1-*.hdr")
    if light is None:
        print("  [skip] no light-1-*.hdr in", raw_dir)
        return
    gray = _load_transient_gray(light, T, H, W)
    _write_video(gray, os.path.join(out_dir, "video-confocal-gray-full.mp4"))
    _write_video(_spad_noise(gray),
                 os.path.join(out_dir, "video-confocalspad-gray-full.mp4"))
    print("  [ok] %s  (%d imgs + 2 videos)" % (os.path.relpath(out_dir), copied))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("raw_root", help="raw renderer output root")
    ap.add_argument("out_root", help="destination root (bike-style)")
    ap.add_argument("--timebin", type=int, default=2048)
    ap.add_argument("--hw", type=int, default=64)
    args = ap.parse_args()

    n = 0
    for dirpath, _dirs, _files in os.walk(args.raw_root):
        if os.path.basename(dirpath).startswith("shine_"):
            rel = os.path.relpath(dirpath, args.raw_root)
            process_sample(dirpath, os.path.join(args.out_root, rel),
                           args.timebin, args.hw, args.hw)
            n += 1
    print("done: %d sample(s) -> %s" % (n, args.out_root))


if __name__ == "__main__":
    main()
