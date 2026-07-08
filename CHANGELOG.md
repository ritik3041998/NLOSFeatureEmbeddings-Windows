# Changelog — Windows port & data-generation work

All work below adapts the Princeton **NLOSFeatureEmbeddings** `cuda-render`
synthetic-data generator to build and run on **Windows 11 + Visual Studio + an
NVIDIA RTX 3050 (CUDA 11.8)**, and adds tooling to produce datasets in the
`bike` layout. Verified end-to-end (built and rendered) on the target machine.

---

## 1. Windows build system (new files)

| File | Purpose |
|---|---|
| `cuda-render/CMakeLists.txt` | CMake build (none shipped upstream). CUDA+C++, links OpenGL/GLEW/GLFW/GLM/OpenCV, copies shaders next to the exe. |
| `cuda-render/setup.ps1` | **One-command** install→build→run. Auto-detects repo location + GPU arch, installs vcpkg libs + OpenCV, patches paths, builds Release, runs. Flags: `-NoRun`, `-Clean`. |
| `cuda-render/.vscode/settings.json`, `launch.json` | VS Code CMake Tools + run configuration. |

## 2. Source-code changes (Windows / MSVC portability)

| File | Change |
|---|---|
| `cuda-render/render/src/main.cpp` | `getFiles()` rewritten from Linux `ls`+`temp.log` to `std::filesystem::directory_iterator`; 3× `system("mkdir")` → `fs::create_directories`; absolute data paths. |
| `cuda-render/render/src/display_6_render.cpp` | `#include <filesystem>`; `system("mkdir")` → `std::filesystem::create_directories`; added `#define NTBIN` to parameterize the number of time bins. |
| `cuda-render/render/src/copydata.cu` | `#if __CUDA_ARCH__ < 600 and defined(...)` → `#if defined(...) && __CUDA_ARCH__ < 600` (MSVC preprocessor rejects `and`). |

## 3. Converters (new files)

| File | Purpose |
|---|---|
| `cuda-render/conversion/hdr2mat.py` | Transient `light-*.hdr` → `.mat` (`measlr`, H×W×T). |
| `cuda-render/conversion/to_bike_format.py` | Raw render output → **`bike` dataset layout**: keeps frontal `confocal-0`/`depth-0` (hdr+png) and turns the transient into `video-confocal-gray-full.mp4` + `video-confocalspad-gray-full.mp4` (SPAD noise approximated with Poisson+Gaussian). |

## 4. Documentation (new files)

| File | Purpose |
|---|---|
| `RUN_ME_FIRST.txt` | 3 prerequisites + the one command, for a new machine. |
| `DEPENDENCIES.txt` | Full manual vs auto-installed dependency list with versions. |
| `cuda-render/QUICKSTART_VERIFIED.md` | Tested step-by-step setup + troubleshooting (the exact commands that worked). |
| `cuda-render/SETUP_WINDOWS_RENDER.md` | Full reference: files, models, confocal vs non-confocal, pose/scale/material/wall, output format, dataset generation. |
| `CHANGELOG.md` | This file. |

## 5. Verified runs (resolution / temporal parameterization)

Rendered the bundled bunny at several settings by editing `height`/`width`
(`main.cpp`) and `NTBIN` (`display_6_render.cpp`):

| Config (spatial × time) | Transient `light-1-*.hdr` | Notes |
|---|---|---|
| 256 × 256 × 600 (default) | ~25.5 MB | baseline |
| 128 × 128 × 1024 | ~8.2 MB | verified `(131072,128,3)` = 1024×128×128 |
| **64 × 64 × 2048** | ~3.2 MB raw | used for the bike-style dataset |

## 6. Example dataset (tracked: `output/`)

Generated a mini **bike-style** dataset from the bunny at 64×64×2048:
- 10 model folders (`bunny00`–`bunny09`, copies of the bundled bunny)
- 5 random bike-like poses each → **50 samples**
- Each sample = the exact **6 bike files**: `confocal-0-*.{hdr,png}`,
  `depth-0-*.{hdr,png}`, `video-confocal-gray-full.mp4`,
  `video-confocalspad-gray-full.mp4`
- 300 files, ~12 MB, committed under `output/`.

## 7. Not committed (see `.gitignore`)

Excluded to keep the repo sane (regenerable / large / reference-only):
`cuda-render/build/`, `data/bunny-renders*`, `data/bunny-raw-*`,
`data/bunny-model-10/`, and the **`bike/`** reference dataset (~954 MB).

---

### Toolchain used (target machine)
CUDA **11.8** (texture references require ≤ 11.x), Visual Studio 2022
(MSVC 14.37), CMake (bundled), vcpkg (GLEW 2.x / GLFW 3.4 / GLM 1.x), prebuilt
OpenCV 4.10.0, RTX 3050 (sm_86), Python 3.10.
