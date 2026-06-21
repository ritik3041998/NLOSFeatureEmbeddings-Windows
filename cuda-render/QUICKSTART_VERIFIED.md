# NLOS Renderer — Verified From-Scratch Setup (Windows 11 + VS Code)

This is the **exact, tested** procedure to build and run the `cuda-render` NLOS
data generator on a fresh Windows 11 machine with an NVIDIA GPU (tested on an
**RTX 3050 6 GB**, driver 591.80). Every command here was actually executed and
produced output.

The whole thing: **install 4 prerequisites → get 4 C++ libraries → apply 6 code
changes → configure → build → run.**

---

## A. Prerequisites to install (one-time)

| # | Component | Version | Notes |
|---|---|---|---|
| 1 | NVIDIA GPU driver | ≥ 520 (591.80 used) | OpenGL 4.6 + CUDA 11.8 runtime |
| 2 | **CUDA Toolkit** | **11.8** — *not* 12.x | The CUDA kernel uses **texture references** (`tex2D`, `cudaBindTextureToArray`), removed in CUDA 12. 11.8 still supports them *and* the RTX 3050 (sm_86). |
| 3 | **Visual Studio 2022** Community | 17.x, **"Desktop development with C++"** workload | Provides MSVC, the bundled CMake + Ninja, and CUDA's MSBuild integration. The CUDA-compatible MSVC toolset **14.37** is selected automatically. |
| 4 | Python | 3.10 (optional) | Only for `hdr2mat.py` / `preprocess_hdr2video.py` |

Install commands (run PowerShell as admin):
```powershell
winget install Microsoft.VisualStudio.2022.Community --override "--add Microsoft.VisualStudio.Workload.NativeDesktop --includeRecommended"
# CUDA 11.8 — download the local installer from the NVIDIA CUDA 11.8 archive and run it
#   https://developer.nvidia.com/cuda-11-8-0-download-archive  (Windows x86_64, exe local)
winget install Python.Python.3.10        # optional
```
Verify:
```powershell
nvidia-smi
& "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v11.8\bin\nvcc.exe" --version   # release 11.8
```
> You do **not** need to install CMake separately — VS bundles it at
> `…\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe`.

---

## B. Get the 4 C++ libraries

**GLEW + GLFW + GLM via vcpkg** (builds in minutes; auto-deploys DLLs next to the exe):
```powershell
git clone https://github.com/microsoft/vcpkg C:\dev\vcpkg
C:\dev\vcpkg\bootstrap-vcpkg.bat -disableMetrics
C:\dev\vcpkg\vcpkg.exe install glew:x64-windows glfw3:x64-windows glm:x64-windows
```

**OpenCV — use the prebuilt release** (much faster than building from source):
```powershell
$ProgressPreference='SilentlyContinue'
Invoke-WebRequest "https://github.com/opencv/opencv/releases/download/4.10.0/opencv-4.10.0-windows.exe" -OutFile C:\dev\opencv-4.10.0-windows.exe
Start-Process C:\dev\opencv-4.10.0-windows.exe -ArgumentList '-o"C:\dev" -y' -Wait
# result: C:\dev\opencv\build\OpenCVConfig.cmake  +  C:\dev\opencv\build\x64\vc16\bin\opencv_world4100.dll
```

---

## C. Get the code + apply the 6 changes

Clone the repo:
```powershell
git clone https://github.com/princeton-computational-imaging/NLOSFeatureEmbeddings D:\NLOS
```

The upstream repo ships **only source files** — no build file, and a few
Linux-only / MSVC-incompatible bits. Apply these (this working copy already has
them, so you can also just copy the files over):

1. **Add `cuda-render/CMakeLists.txt`** — the build file (see this repo's copy).
2. **`render/src/copydata.cu` line 5** — MSVC can't use `and` in `#if`:
   ```cpp
   #if  __CUDA_ARCH__ < 600 and defined(__CUDA_ARCH__)      // before
   #if defined(__CUDA_ARCH__) && __CUDA_ARCH__ < 600        // after
   ```
3. **`render/src/main.cpp` — `getFiles()`** — replace the Linux `ls`/`temp.log`
   listing with `std::filesystem::directory_iterator` (and `#include <filesystem>`).
4. **`render/src/main.cpp` — the 3 `system("mkdir …")` calls** → `fs::create_directories(...)`
   (forward-slash paths fail in `cmd.exe`).
5. **`render/src/display_6_render.cpp`** — `#include <filesystem>` and the one
   `system("mkdir …")` → `std::filesystem::create_directories(folder)`.
6. **`render/src/main.cpp` — set absolute input/output paths** (forward slashes ok):
   ```cpp
   string parentFlder    = "D:/NLOS/data/bunny-model";
   string parentSvFolder = "D:/NLOS/data/bunny-renders";
   ```

> Input models must sit at `<parentFlder>/<name>/model/model_normalized.obj`
> (+ `.mtl`), triangulated, with coordinates inside `[-0.5, 0.5]`. The bundled
> bunny already matches.

---

## D. Configure + build (the commands that worked)

```powershell
$cmake = "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
cd D:\NLOS\cuda-render

& $cmake -B build -S . -G "Visual Studio 17 2022" -A x64 -T "cuda=11.8" `
    -DCMAKE_TOOLCHAIN_FILE=C:/dev/vcpkg/scripts/buildsystems/vcpkg.cmake `
    -DOpenCV_DIR=C:/dev/opencv/build `
    -DCMAKE_CUDA_ARCHITECTURES=86 `
    -DCMAKE_CUDA_FLAGS="-allow-unsupported-compiler"

& $cmake --build build --config Release
```

Key flags explained:
- `-T "cuda=11.8"` — use the CUDA 11.8 MSBuild integration. **Do not** pin a
  specific MSVC version (e.g. `version=14.37.32822`) — that triggered a missing
  `VCRedistVersion.default.props` error here. CMake picks the compatible 14.37
  cl.exe on its own.
- `-DCMAKE_CUDA_FLAGS="-allow-unsupported-compiler"` — safety net so nvcc 11.8
  accepts the installed MSVC even if a newer toolset is the default.
- `-DCMAKE_CUDA_ARCHITECTURES=86` — RTX 3050 = sm_86.

Output: `D:\NLOS\cuda-render\build\Release\nlos_render.exe`, with
`glew32.dll`, `glfw3.dll`, and the shaders auto-copied next to it.

**One manual copy** — the prebuilt OpenCV DLL (vcpkg doesn't deploy it because
OpenCV isn't a vcpkg package):
```powershell
Copy-Item C:\dev\opencv\build\x64\vc16\bin\opencv_world4100.dll D:\NLOS\cuda-render\build\Release\ -Force
```

---

## E. Run

```powershell
cd D:\NLOS\cuda-render\build\Release
.\nlos_render.exe
```
(Run from this folder — the renderer loads the shaders by relative path.)

Healthy output ends with:
```
rendering time (ms) ~940
done!
```
Results land in `D:\NLOS\data\bunny-renders\0\bunny\shine_0.0000-…\`:
- **`light-1-*.hdr`** — the transient NLOS measurement (the data)
- `confocal-*`, `original-*`, `depth-*` — steady images + depth (ground truth)

At default 256×256×600 → ~27 MB/sample (transient ≈ 25.5 MB).

---

## F. Convert for the DL pipeline (optional)
```powershell
pip install numpy scipy opencv-python
cd D:\NLOS\cuda-render\conversion
# .mat (real-data eval path):
python hdr2mat.py "…\light-1-….hdr" bunny0.mat
# .mp4 (synthetic training path): edit the `folders` list at the bottom, then:
python preprocess_hdr2video.py
```

---

## G. Changing resolution / temporal bins
- **Spatial** (e.g. 128×128): `main.cpp` → `int height = 128; int width = 128;`
- **Time bins** (e.g. 1024): `display_6_render.cpp` → add `#define NTBIN 1024`,
  set both `int timebin = NTBIN;`, and in the `launch_cudaProcess2(...)` call use
  `…, maxsz, NTBIN, 0);`. (Default 1 cm bins; 1024 bins → 0–10.24 m window.)

Then rebuild (`cmake --build build --config Release`) and run. Tested: 128×128×1024
produces a `(131072,128,3)` HDR = 1024×128×128, ~8.2 MB.

---

## H. Troubleshooting (issues actually hit)

| Symptom | Cause / Fix |
|---|---|
| `VCRedistVersion.default.props was not found` during configure | You pinned `-T version=14.37.…`. Use `-T "cuda=11.8"` instead (let CMake pick the toolset). |
| `unsupported Microsoft Visual Studio version` | Add `-DCMAKE_CUDA_FLAGS="-allow-unsupported-compiler"`, or ensure CUDA 11.8 (not 12.x). |
| `tex2D` / `cudaBindTextureToArray` undefined | You're on CUDA 12.x — install CUDA 11.8. |
| `error: 'and' …` in copydata.cu | Apply change #2 (`and` → `&&`). |
| App runs but `0xc000007b` / missing `opencv_world4100.dll` | Copy the OpenCV DLL next to the exe (step D). |
| `Impossible to open pointlight.vertexshader` | Run from `build\Release` (shaders are copied there). |
| IntelliSense red squiggles on `GL/glew.h`, `cuda_runtime.h` | Cosmetic; resolves after CMake configure populates include paths. |
