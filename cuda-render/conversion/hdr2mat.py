"""
hdr2mat.py  -  convert a rendered transient HDR into a .mat measurement.

The CUDA renderer writes the transient histogram as a single tall HDR image:

    light-1-<maxval>-<maxdist>-<mindist>.hdr   (confocal,   conf=1)
    light-0-<maxval>-<maxdist>-<mindist>.hdr   (non-confocal, conf=0)

Its pixel layout is  (TIMEBIN * H) x W x 3 , i.e. TIMEBIN frames of H x W
stacked vertically.  TIMEBIN = (TEN - TBE) * 100 = 600 by default
(time bin = 1 cm of round-trip path length, covering 0..6 m).

This script reshapes it back to a (T, H, W) volume and saves it as a MATLAB
file with the key 'measlr' (transposed to H x W x T), which is the same key
the deep-learning code expects for real captures.

Usage:
    python hdr2mat.py  path/to/light-1-....hdr  out.mat
    python hdr2mat.py  path/to/light-1-....hdr  out.mat --timebin 600 --hw 256
"""
import argparse
import numpy as np
import cv2
import scipy.io as sio


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("hdr", help="input transient .hdr file (light-*.hdr)")
    ap.add_argument("out", help="output .mat file")
    ap.add_argument("--timebin", type=int, default=600,
                    help="number of time bins = (TEN-TBE)*100, default 600")
    ap.add_argument("--hw", type=int, default=256,
                    help="spatial resolution (H == W), default 256")
    ap.add_argument("--gray", action="store_true", default=True,
                    help="collapse RGB to a single channel (default on)")
    ap.add_argument("--color", dest="gray", action="store_false",
                    help="keep the 3 colour channels (saves T x H x W x 3)")
    args = ap.parse_args()

    T, H, W = args.timebin, args.hw, args.hw

    # cv2.imread(-1) keeps the full 32-bit float HDR data, BGR order
    im = cv2.imread(args.hdr, cv2.IMREAD_UNCHANGED)
    if im is None:
        raise SystemExit("could not read %s" % args.hdr)

    expected = (T * H, W, 3)
    if im.shape != expected:
        raise SystemExit("unexpected HDR shape %s, expected %s "
                         "(check --timebin / --hw)" % (im.shape, expected))

    vol = im.reshape(T, H, W, 3).astype(np.float32)   # T x H x W x 3 (BGR)

    if args.gray:
        # luminance-style average over colour channels -> T x H x W
        vol = vol.mean(axis=3)
        measlr = np.transpose(vol, (1, 2, 0))          # H x W x T
    else:
        measlr = np.transpose(vol, (1, 2, 0, 3))       # H x W x T x 3

    sio.savemat(args.out, {"measlr": measlr})
    print("saved %s  shape=%s  max=%.4f" %
          (args.out, measlr.shape, float(measlr.max())))


if __name__ == "__main__":
    main()
