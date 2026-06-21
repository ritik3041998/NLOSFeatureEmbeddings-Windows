# NLOS Synthetic Data Generation — Windows 11 + VS Code Setup Guide

This guide covers **only** the `cuda-render/` part of NLOSFeatureEmbeddings: the
CUDA + OpenGL renderer that turns a 3D model into a **transient (time-resolved)
NLOS measurement**. The deep-learning / inference code is ignored here.

Target machine: **Windows 11, RTX 3050 6 GB** (Ampere, compute capability 8.6).

---

## 0. TL;DR — the execution flow

```
3D model (.obj + .mtl)
   │   loadobj()  → normalize to a ~1 m box, compute normals      (display_4_loaddata.cpp)
   ▼
OpenGL rasterizer (off-screen FBO, 256×256, ortho 2 m wall)       (display_2/3/5/6 + shaders)
   │   for 480×480 sampled directions over a cone, render the
   │   object as seen "through the wall"; each fragment carries
   │   RGB intensity + round-trip path length in alpha            (pointlight.vertex/fragmentshader)
   ▼
CUDA kernel cudaProcess2  → scatter every fragment into a
   600×256×256 time-of-flight histogram (1 cm bins)               (copydata.cu)
   ▼
OpenCV writes the histogram as one tall HDR image
   light-1-*.hdr   (= the transient measurement)                  (display_6_render.cpp)
   ▼
(optional) hdr2mat.py → measlr (H×W×T) .mat  /  preprocess_hdr2video.py → .mp4
```

One run of the program = one **sample**: a folder named
`shine_..-rot_..-shift_..` containing the transient HDR plus steady-state
images and depth maps.

---

## 1. Main entry points

| File | Role |
|---|---|
| **`render/src/main.cpp`** | **`int main()`** — the program entry point. Sets input/output folders, render resolution, sample count, then loops over models calling `render::display()`. |
| `render/src/renderclass.h` | The `render` class + `mesh`/`material`/`group` structs. |
| `render/src/display_0_initial.cpp` | GLFW window + GLEW + OpenGL state (requests **OpenGL 4.4 core**, hidden window). |
| `render/src/display_1_cam.cpp` | View/projection/model matrices. Wall = orthographic `[-1,1]²` plane. Scan directions sampled on a Fibonacci hemisphere. |
| `render/src/display_2_fbo.cpp` | Off-screen framebuffer + the large "tile" texture used to batch many renders. |
| `render/src/display_3_program.cpp` | Loads/compiles the GLSL shaders, gets uniform handles. |
| `render/src/display_4_loaddata.cpp` | **OBJ + MTL parser**, model normalization (scale/shift), normal computation. |
| `render/src/display_5_draw.cpp` | Uploads mesh to GPU (VAO/VBO). |
| `render/src/display_6_render.cpp` | **The render loop** — steady-state images, depth, and the transient histogram; calls the CUDA kernels and saves all outputs. |
| `render/src/copydata.cu` | **CUDA kernels** `cudaProcess2` (transient scatter) and `cudaProcess3` (confocal steady image). |
| `render/pointlight.vertexshader` / `.fragmentshader` | GLSL: confocal vs non-confocal geometry, path-length & intensity per fragment. |
| `conversion/preprocess_hdr2video.py` | Converts transient HDR → `.mp4` + sampled PNGs (used by the DL code). |
| `conversion/hdr2mat.py` | **(added by this guide)** transient HDR → `.mat` (`measlr`). |

You normally only ever **edit `main.cpp`** to control a run.

> **Windows portability note (already applied to this repo):** the original
> `main.cpp`/`display_6_render.cpp` used Linux `ls` and `mkdir` via `system()`,
> which fail in `cmd.exe`. They have been replaced with C++17
> `std::filesystem` (`directory_iterator` / `create_directories`). No behavior
> change on Linux; now also works on Windows.

---

## 2. Required versions

| Component | Version to install | Why this version |
|---|---|---|
| **GPU driver** | Any recent GeForce driver (≥ 520) | Provides OpenGL 4.6 + CUDA 11.8 runtime for the RTX 3050. |
| **CUDA Toolkit** | **11.8** (do **not** use 12.x) | The code uses **texture references** (`texture<float4,2>`, `tex2D`, `cudaBindTextureToArray`). These were **removed in CUDA 12.0**. 11.8 still supports them *and* supports the RTX 3050 (sm_86). |
| **Visual Studio** | **2022 Community** + **"MSVC v142 (VS2019) build tools"** component | CUDA 11.8's `nvcc` officially supports the v142 toolset. Using the default v143 may give *"unsupported Microsoft Visual Studio version"*. We pin `-T v142`. |
| **CMake** | **3.20+** (bundled with VS, or standalone) | First-class CUDA language + `CMAKE_CUDA_ARCHITECTURES`. |
| **OpenGL** | 4.4 core (from the driver) | `display_0_initial.cpp` requests 4.4; RTX 3050 supports 4.6. Nothing to install. |
| **GLFW** | 3.3+ (vcpkg `glfw3`) | Window/context creation. |
| **GLEW** | 2.x (vcpkg `glew`) | OpenGL extension loading. |
| **GLM** | 0.9.9+ / 1.x (vcpkg `glm`) | Math (vectors/matrices). |
| **OpenCV** | 4.x (vcpkg `opencv4`) | Image/HDR I/O + `cv::Rodrigues`. (README tested 3.4; 4.x works.) |
| **VS Code** | latest + **C/C++** and **CMake Tools** extensions | IDE / build driver. |
| **Python** (optional) | 3.9–3.11 + `numpy scipy opencv-python` | Only for `hdr2mat.py` / `preprocess_hdr2video.py`. |

---

## 3. Installation commands

### 3.1 Visual Studio 2022
Install **Visual Studio 2022 Community** with workloads:
- *Desktop development with C++*

and individual components:
- *MSVC v142 - VS 2019 C++ x64/x86 build tools*
- *C++ CMake tools for Windows*
- *Windows 11 SDK*

### 3.2 CUDA Toolkit 11.8
Download **CUDA Toolkit 11.8** from the NVIDIA archive and install (it auto-adds
the Visual Studio integration). Verify in a new terminal:

```powershell
nvcc --version          # should print "release 11.8"
nvidia-smi              # confirms the RTX 3050 + driver
```

### 3.3 vcpkg + C/C++ libraries
`vcpkg` is the simplest way to get GLFW/GLEW/GLM/OpenCV on Windows:

```powershell
git clone https://github.com/microsoft/vcpkg C:\dev\vcpkg
C:\dev\vcpkg\bootstrap-vcpkg.bat

C:\dev\vcpkg\vcpkg install glfw3:x64-windows glew:x64-windows glm:x64-windows opencv4:x64-windows
```

> The OpenCV build takes a while. After this, the DLLs live in
> `C:\dev\vcpkg\installed\x64-windows\bin` — make sure that folder is on your
> `PATH`, or use vcpkg "applocal" deployment (the CMake toolchain copies the
> DLLs next to the .exe automatically when you build through it).

### 3.4 Python helpers (optional)
```powershell
pip install numpy scipy opencv-python
```

---

## 4. Build steps

### 4.1 One-time edit — set absolute data paths
Open `render/src/main.cpp` and set the input/output folders to **absolute
Windows paths** (forward slashes are fine):

```cpp
// main.cpp, near the top of main()
string parentFlder    = "D:/NLOSFeatureEmbeddings-main/data/bunny-model";
string parentSvFolder = "D:/NLOSFeatureEmbeddings-main/data/bunny-renders";
```

`parentFlder` must contain one **sub-folder per model**, each holding
`model/model_normalized.obj` (this is exactly how `data/bunny-model/bunny/...`
is laid out).

### 4.2 Configure + build (command line)
```powershell
cd D:\NLOSFeatureEmbeddings-main\cuda-render

cmake -B build -S . -G "Visual Studio 17 2022" -A x64 -T v142 `
      -DCMAKE_TOOLCHAIN_FILE=C:/dev/vcpkg/scripts/buildsystems/vcpkg.cmake

cmake --build build --config Release
```

Output: `D:\NLOSFeatureEmbeddings-main\cuda-render\build\Release\nlos_render.exe`
(the two shader files are auto-copied next to it).

### 4.3 Build inside VS Code (alternative)
1. `File ▸ Open Folder…` → open `D:\NLOSFeatureEmbeddings-main`.
2. The provided `cuda-render/.vscode/settings.json` points CMake Tools at the
   renderer and the vcpkg toolchain.
3. Command palette → **CMake: Configure**, pick *Visual Studio Community 2022 –
   amd64*.
4. **CMake: Build** (or `F7`).
5. Press **F5** to run (`launch.json` sets the working directory to the .exe
   folder so the shaders resolve).

---

## 5. Generate your first sample — exact commands

The repo already ships the bunny model, so after building:

```powershell
cd D:\NLOSFeatureEmbeddings-main\cuda-render\build\Release
.\nlos_render.exe
```

What happens: it loads `bunny/model/model_normalized.obj`, renders one confocal
transient, and writes results to
`D:\NLOSFeatureEmbeddings-main\data\bunny-renders\0\bunny\shine_0.0000-rot_0.0000_0.0000_0.0000-shift_0.0000_0.0000_0.0000\`.

Convert the transient to a `.mat` (and/or a video):
```powershell
cd D:\NLOSFeatureEmbeddings-main\cuda-render\conversion
python hdr2mat.py "D:\NLOSFeatureEmbeddings-main\data\bunny-renders\0\bunny\shine_0.0000-rot_0.0000_0.0000_0.0000-shift_0.0000_0.0000_0.0000\light-1-...hdr" bunny0.mat
```

> The default `main.cpp` uses `definerot = true` with all rotations/shifts = 0,
> so you get a single, deterministic, front-facing confocal sample — ideal for a
> first test.

---

## 6. Confocal vs non-confocal

Two layers control this:

1. **Shader geometry** (`pointlight.vertexshader`): the `isconfocal` uniform.
   When `> 0`, illumination and detection are co-located at the projected wall
   point (confocal); otherwise the light comes from `lightPosition_modelspace`
   (non-confocal). You don't edit this — it's driven by the loop below.

2. **Render loop** (`display_6_render.cpp`, the transient section):
   ```cpp
   for (int conf = 1; conf < 2; conf++) {       // <-- change here
       float confocal = conf * 2.0 - 1.0;       // conf=0 → -1 (non-confocal)
       glUniform1f(isconfocal, confocal);       // conf=1 → +1 (confocal)
   ```
   - **Confocal only (default):** `for (int conf = 1; conf < 2; conf++)` → writes `light-1-*.hdr`.
   - **Non-confocal only:** `for (int conf = 0; conf < 1; conf++)` → writes `light-0-*.hdr`.
   - **Both:** `for (int conf = 0; conf < 2; conf++)`.

For non-confocal the light position is the single source set just above the
loop; the number of light positions is `lhnum`/`lvnum` (kept at 1 — note the
`if (lh*lightvnum+lv > 0) exit(0);` guard, so do **not** raise these without
also removing that guard).

---

## 7. Object position, rotation, scale, material, wall

### Position & rotation (per sample)
`render::display()` in `display_6_render.cpp` (~lines 360–395):
```cpp
float xrot = 15 * (2*randomnum()-1);     // ±15°
float yrot = ... ;                       // ~[45,135] or [-45,-135]
float zrot = 15 * (2*randomnum()-1);     // ±15°
float xshift = 0.4f*(2*randomnum()-1);   // ±0.4 m
float yshift = 0.4f*(2*randomnum()-1);
float zshift = 0.4f*(2*randomnum()-1);
if (inirotshift) { xrot=rotx; ... zshift=shiftz; }   // override from main.cpp
```
- For **fixed** pose: in `main.cpp` keep `definerot = true` and set
  `rotx/roty/rotz/shiftx/shifty/shiftz`.
- For **random** poses (dataset generation): set `definerot = false`, and use
  `rnum > 1` to draw several random poses per model.

### Scale (model normalization)
`readobj()` in `display_4_loaddata.cpp` (~lines 339–356): the model is centered
and rescaled so its largest dimension becomes
```cpp
float scale2 = 0.6 + rand()/RAND_MAX * 0.6;   // random size in [0.6, 1.2] m
glm::vec3 tmp = (v_list[i] - shift) * scale2 / scale;
```
For a **fixed size**, replace `scale2` with a constant, e.g. `float scale2 = 1.0f;`.
Note `readobj` rejects models whose raw coordinates fall outside `[-0.5, 0.5]`
(returns false) — pre-normalized OBJs like the bunny pass; arbitrary OBJs may
need pre-scaling (see §10).

### Normals (smooth vs flat)
`display_4_loaddata.cpp` (~lines 464–473): point (smooth) normals are active;
face (flat) normals are the commented block just above. The paper notes face
normals work better for ShapeNet — swap the comment if needed.

### Material (diffuse / specular / color)
- Per-object material comes from the **`.mtl`** file: `Kd` (diffuse RGB),
  `Ks` (specular RGB), `Ns` (shininess), `Ka` (ambient). Edit the `.mtl` to
  recolor or change glossiness.
- A hard **specular override** exists in `display_6_render.cpp` (~line 693):
  ```cpp
  bool specular = false;   // set true → forces Ns=64, Kd=0 (metallic look)
  ```

### Wall geometry
The wall is the orthographic plane `z = 1`, size **2 m × 2 m**, defined by
`getProjectionMatrix()` in `display_1_cam.cpp`:
```cpp
glm::ortho(-1.0, 1.0, -1.0, 1.0, -100.0, 100.0);   // 2×2 wall
```
The scan/light grid samples `light_x, light_y ∈ (-1,1)` to match. Changing the
wall size means editing the ortho bounds **and** the light sampling range; it is
otherwise hard-coded to 2 m (the value the DL code assumes via `wall_size=2.0`).

### Spatial / temporal resolution
- Spatial: `height = width = 256` in `main.cpp`.
- Temporal: macros at the top of `display_6_render.cpp`:
  ```cpp
  #define TBE 0     // start path length (×100 = bins)
  #define TEN 6     // end path length  → TIMEBIN = (TEN-TBE)*100 = 600 bins, 0..6 m
  ```
  Each bin = 1 cm of total (light→point→wall) round-trip path length.

---

## 8. Output files

For every sample folder `shine_..-rot_..-shift_..`:

| File pattern | Meaning |
|---|---|
| **`light-1-<maxval>-<maxdist>-<mindist>.hdr`** | **The confocal transient measurement.** A tall `600·256 × 256 × 3` float HDR — 600 time frames of 256×256 stacked vertically. *(non-confocal → `light-0-*.hdr`)* |
| `confocal-<id>-<max>-<min>.png` / `.hdr` | Confocal **steady-state** 2-D images from sampled viewpoints (`id 0` = frontal). |
| `original-<id>-<max>-<min>.png` / `.hdr` | Ordinary (line-of-sight) shaded renders from those viewpoints — the "ground-truth" appearance. |
| `depth-<id>-<max>-<min>.png` / `.hdr` | Depth maps for those viewpoints. |

Filename numbers encode statistics: `maxval` = peak intensity, `maxdist`/`mindist`
= furthest/nearest path length (m) with signal.

After `hdr2mat.py`: `*.mat` with key `measlr`.
After `preprocess_hdr2video.py`: `video-confocal-gray-full.mp4` + sampled PNGs.

---

## 9. Shape, format, and meaning of the transient data

- **On disk** (`light-1-*.hdr`): `float32`, shape `(600·256, 256, 3)`, BGR (OpenCV).
- **Logical volume:** `T × H × W = 600 × 256 × 256` (drop color → grayscale, or
  keep 3 channels).
- **Axes:**
  - `T` (time / depth): bin `t` = round-trip path length `lp + pv` in the
    interval `[t/100, (t+1)/100]` meters (`lp` = light→surface, `pv` =
    surface→wall-point). So `t = 0..599` spans 0–6 m.
  - `H, W`: position on the 2 m × 2 m wall (256×256 scan grid).
- **Values:** accumulated radiance reaching each wall point at each time of
  flight, with the shader's inverse-square falloff and Lambertian/specular
  shading, linearly splatted between adjacent time bins (`cudaProcess2`). No
  sensor noise is added — for realistic SPAD noise, add it in a post-process
  (the paper uses the model at <https://graphics.unizar.es/data/spad/>).
- **`measlr` convention** (what `hdr2mat.py` writes, matching the DL real-data
  loader): `H × W × T` (grayscale) — the deep-learning code transposes it back
  to `T × H × W` on load.

---

## 9b. Feeding the data into the deep-learning code (IMPORTANT)

The DL repo has **two distinct input paths** — pick the right one:

| Path | Format | Used by | Converter |
|---|---|---|---|
| **Synthetic / training** | **`.mp4`** (`video-confocal-gray-full.mp4`) + sampled PNGs | the training data loader | **`conversion/preprocess_hdr2video.py`** |
| Real captures / eval | `.mat` with key `measlr` (`H×W×T`) | `DL_inference/inference/eval2.py` → `testrealcall.py` | `conversion/hdr2mat.py` |

**Your rendered data is synthetic, so use the `.mp4` path.** Two things make
this line up automatically:
- The renderer's default `TEN=6` → **600 time bins**, which is exactly the
  `imszs = [600, 256, 256, 3]` that `preprocess_hdr2video.py` expects.
- It reads `light-1-*.hdr` (confocal) and writes `video-confocal-gray-full.mp4`.

Steps:
1. Render your samples (§5/§10).
2. Edit the `folders` list at the bottom of
   [`conversion/preprocess_hdr2video.py`](conversion/preprocess_hdr2video.py)
   (~line 284) to point at your output root, e.g.
   ```python
   folders = ['D:/NLOSFeatureEmbeddings-main/data/bunny-renders']
   ```
   It already uses `numworkers=0` in `__main__` (required on Windows) and
   `conf=[1]` (confocal). It imports `torch`, so install PyTorch in this env.
3. Run it:
   ```powershell
   cd D:\NLOSFeatureEmbeddings-main\cuda-render\conversion
   python preprocess_hdr2video.py
   ```
   This walks every `shine_..` folder and writes the `.mp4` (+ `_all.png` and
   the sampled-frame PNGs) next to each transient.

> Use `hdr2mat.py` **only** if you deliberately want to push a synthetic scene
> through the *real-data* eval path — note `testrealcall.py` hardcodes per-scene
> time offsets (`bike`, `dragon`, …) and a fixed `matmaxref` normalization, so
> synthetic `.mat` files won't drop in without editing that loader.

---

## 10. Generating thousands of samples automatically

The renderer is built for batch generation; the bunny demo just caps it at 1.

1. **Populate the model pool.** Put many models under `parentFlder`, each as
   `<modelname>/model/model_normalized.obj` (+ its `.mtl`). The motorbike
   dataset in the paper used ShapeNet class `03790512`; a pre-rendered 3000-bike
   set is linked from the repo README.
   - OBJs must be pre-normalized into `[-0.5, 0.5]` or `readobj()` skips them.

2. **Set the counts in `main.cpp`:**
   ```cpp
   bool definerot = false;   // use RANDOM rotations/shifts per sample
   int  rendernum = 3000;    // total models to process (the while-loop cap)
   ...
   int rnum = 10;            // random poses PER model  (in display(...) call)
   ```
   The main loop walks `folders` round-robin (`i = (i+1) % folders.size()`), so
   `rendernum` samples are produced across your model pool, each in its own
   `shine_..-rot_..-shift_..` folder. Total samples = `rendernum × rnum`.

3. **(Optional) keep it confocal-only and grayscale** for the smallest output;
   raise `samplenum`/lower `blocksz` only if you understand the texture-size
   trade-off (see §11 memory note).

4. **Batch-convert** all transients to `.mat`:
   ```powershell
   Get-ChildItem -Recurse -Filter "light-1-*.hdr" D:\NLOSFeatureEmbeddings-main\data\bunny-renders |
     ForEach-Object { python hdr2mat.py $_.FullName ($_.DirectoryName + "\meas.mat") }
   ```
   (or run `preprocess_hdr2video.py` after pointing its `folders` list at your
   output root, to produce the `.mp4`s the DL pipeline consumes).

Throughput: each sample renders 480×480 directions; on an RTX 3050 expect
roughly seconds-to-minutes per sample depending on mesh size. Generating
thousands is an overnight job — run it as a background process.

---

## 11. Code changes needed (summary)

| Change | File | Status |
|---|---|---|
| Replace Linux `ls` directory listing with `std::filesystem` | `main.cpp` | ✅ **applied** |
| Replace `system("mkdir …")` with `create_directories` (forward-slash paths fail in cmd) | `main.cpp`, `display_6_render.cpp` | ✅ **applied** |
| Absolute Windows data paths | `main.cpp` (§4.1) | ⬜ you set these |
| Save transient as `.mat` | `conversion/hdr2mat.py` | ✅ **added** |
| CMake build (no `.sln`/`CMakeLists` shipped originally) | `cuda-render/CMakeLists.txt` | ✅ **added** |
| `-D_CRT_SECURE_NO_WARNINGS` for MSVC (legacy `sprintf`) | `CMakeLists.txt` | ✅ **applied** |
| Confocal/non-confocal, scale, pose, material, counts | various (§6, §7, §10) | ⬜ optional, your choice |

> **Memory note (RTX 3050 6 GB):** the default config fits comfortably. The
> "tile" texture is `blocksz·256 = 40·256 = 10240²` RGBA32F ≈ **1.7 GB**, plus
> the `600×256×256×3` transient buffer ≈ **0.47 GB**, ≈ **2.2 GB** total. Do not
> raise `blocksz` past ~48 on a 6 GB card. If you ever hit an out-of-memory or
> `GL_MAX_TEXTURE_SIZE` error, lower `blocksz` in `main.cpp` (keep
> `actualsample % blocksz == 0`).

---

## 12. Troubleshooting

| Symptom | Fix |
|---|---|
| `nvcc fatal: unsupported Microsoft Visual Studio version` | You're on the v143 toolset. Re-configure with `-T v142` (already in the commands/settings). |
| `tex2D` / `cudaBindTextureToArray` undeclared, or texture errors | You're on **CUDA 12.x**. Texture references were removed; install **CUDA 11.8**. |
| `Failed to open GLFW window` | Run on the **NVIDIA GPU** (not an integrated Intel GPU); update the driver. OpenGL 4.4 core is required. |
| `Impossible to open pointlight.vertexshader` | Working directory doesn't contain the shaders. Run from the `.exe` folder (CMake copies them there) or use the provided `launch.json`. |
| `cannot load obj/mtl file` or model skipped | Check the `<model>/model/model_normalized.obj` layout and that coordinates are within `[-0.5, 0.5]`. |
| OpenCV DLL not found at runtime | Add `C:\dev\vcpkg\installed\x64-windows\bin` to `PATH` (the vcpkg toolchain normally copies DLLs next to the exe). |
| IntelliSense red squiggles on `GL/glew.h` etc. before building | Cosmetic — they resolve after the first successful CMake **Configure** populates the include paths. |
