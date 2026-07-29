# How to Run This Repo & Simulate OBJs on a New System

End-to-end pipeline: from a bare Windows machine to generated NLOS data.
Everything is automated by the scripts — you only install a few prerequisites
once, then run one command per model (or per folder of models).

---

## Phase 1 — Install prerequisites (one-time, manual)

The scripts can't auto-install these:

| # | Install | Version | Where |
|---|---|---|---|
| 1 | NVIDIA GPU driver | recent (≥520) | nvidia.com / GeForce Experience |
| 2 | **CUDA Toolkit 11.8**  ⚠️ NOT 12.x | 11.8 | https://developer.nvidia.com/cuda-11-8-0-download-archive |
| 3 | Visual Studio 2022 + **"Desktop development with C++"** | 2022 | https://visualstudio.microsoft.com |
| 4 | Git | any | https://git-scm.com |
| 5 | Python + libs (for prepare/convert scripts) | 3.10 | `pip install numpy scipy opencv-python` |

Why CUDA 11.8: the renderer uses CUDA texture references, removed in CUDA 12.

## Phase 2 — Get the repo

```powershell
git clone https://github.com/ritik3041998/NLOSFeatureEmbeddings-Windows D:\NLOS
cd D:\NLOS
```

## Phase 3 — First-time build (auto-installs the C++ libraries)

```powershell
powershell -ExecutionPolicy Bypass -File cuda-render\setup.ps1
```

Clones vcpkg, installs GLEW/GLFW/GLM, downloads prebuilt OpenCV, configures,
builds Release, and does a test render. **Run once per machine** (~10–15 min the
first time; seconds afterwards).

## Phase 4 — Simulate your OBJ(s)

**A) One model → one command**
```powershell
powershell -ExecutionPolicy Bypass -File cuda-render\simulate_obj.ps1  "C:\path\your.obj"  car
```

**B) A whole folder of models (batch)** — layout must be `<name>/models/model_normalized.obj`
```powershell
powershell -ExecutionPolicy Bypass -File cuda-render\simulate_folder.ps1  "C:\path\my-dataset"  -Poses 5
```

Options (both scripts):

| Flag | Meaning | Default |
|---|---|---|
| `-HW n` | spatial resolution (n×n) | 64 |
| `-TimeBin n` | number of time bins | 2048 |
| `-Poses N` | random poses per model | 5 |
| `-Single` | one fixed pose instead of random | — |
| `-Extent x` | object size in the scene (must be < 1.0) | 0.9 |
| `-OutName name` | output folder (folder script only) | output-nlos |

## Phase 5 — Get the output

Bike-structured dataset:
```
output\0\<name>\shine_..-rot_..-shift_..\
    confocal-0-*.hdr / .png          (frontal confocal image)
    depth-0-*.hdr    / .png          (frontal depth map)
    video-confocal-gray-full.mp4     (transient video)
    video-confocalspad-gray-full.mp4 (SPAD-noise transient video)
```

Need lossless numeric transient instead of the mp4? The raw float HDR is in
`data\batch-raw\...\light-1-*.hdr`; convert with
`python cuda-render\conversion\hdr2mat.py <light.hdr> out.mat --timebin <T> --hw <n>`.

---

## Condensed (new PC, after Phase-1 installs)

```powershell
git clone https://github.com/ritik3041998/NLOSFeatureEmbeddings-Windows D:\NLOS
cd D:\NLOS
powershell -ExecutionPolicy Bypass -File cuda-render\setup.ps1                          # build (once)
powershell -ExecutionPolicy Bypass -File cuda-render\simulate_obj.ps1 "C:\my.obj" car    # simulate
```

---

## Two things to remember

### 1. Resolution vs GPU memory
The renderer allocates a GPU transient buffer of `4 × T × H × W × 3` bytes:

| Config | GPU buffer | Fits 6 GB (RTX 3050)? |
|---|---|---|
| 64×64×2048 | 0.09 GB | ✅ |
| 128×128×2048 | 0.38 GB | ✅ |
| 256×256×2048 | 1.50 GB | ✅ (~3.5 GB total w/ tile texture) |
| **512×512×2048** | **6.00 GB** | ❌ won't fit on 6 GB |

For 512+ on a 6 GB card you'd need a 1-channel renderer change; on an ≥8–12 GB
GPU it runs as-is (lower `blocksz` in `main.cpp` if the tile texture is too big).

Approx timing at 64×64×2048 (measured): ~4–5 s/sample → 337 models × 5 poses
≈ 2.5–3.5 h. At 256×256 it is ~6–8× slower.

### 2. Bin resolution
Time-bin width is fixed at **0.01 m ≈ 33 ps** (set by `depth * 100` in
`copydata.cu`). `-TimeBin` changes the number of bins, not the width. This
matches the reconstruction pipeline's `bin_len = 0.01`.

### 3. Input data is not in the repo
`dataset/`, `NLOS-DATA/`, and all generated outputs are gitignored (too large).
Bring your own OBJs / dataset folder on the new machine — the scripts auto-patch
paths, so you never edit the source.

---

## The scripts & converters (all in `cuda-render/`)

| File | Purpose |
|---|---|
| `setup.ps1` | one-time install + build |
| `simulate_obj.ps1` | simulate a single .obj |
| `simulate_folder.ps1` | batch-simulate every model in a folder |
| `conversion/prepare_obj.py` | triangulate + normalize any .obj into the required layout |
| `conversion/to_bike_format.py` | raw render output → bike 6-file structure |
| `conversion/hdr2mat.py` | transient HDR → .mat (`measlr`) |

See also `QUICKSTART_VERIFIED.md`, `SETUP_WINDOWS_RENDER.md`, `DEPENDENCIES.txt`,
`MIGRATION_GUIDE.md`, and `CHANGELOG.md`.
