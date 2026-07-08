# Migration Guide — apply today's changes to another copy of the repo

You have another machine with the **original/older** code and want it to match
this one. There are two ways.

---

## Option 1 — SYNC FROM GIT (easiest, recommended)

Everything is already on your GitHub repo
`https://github.com/ritik3041998/NLOSFeatureEmbeddings-Windows`.

**If the other copy is a clone of the SAME repo:**
```bash
git pull origin main
```

**If the other copy is the original upstream repo (different remote):**
```bash
# add this repo as a second remote and pull its main
git remote add winport https://github.com/ritik3041998/NLOSFeatureEmbeddings-Windows.git
git fetch winport
git checkout winport/main -- .        # overlay all files from the Windows port
# or, to fully switch:  git merge winport/main --allow-unrelated-histories
```

**If it's not a git repo / you just want the files:** download the repo as a
ZIP from GitHub and copy these over (see file lists in Option 2).

That's it — no hand-editing needed. Use Option 2 only if you must patch by hand.

---

## Option 2 — APPLY THE CHANGES BY HAND

Two kinds of change: **(A) new files to add** and **(B) edits to 3 existing
source files.**

### A) New files to ADD (copy them in as-is)

```
RUN_ME_FIRST.txt
DEPENDENCIES.txt
CHANGELOG.md
MIGRATION_GUIDE.md                        (this file)
.gitignore
cuda-render/CMakeLists.txt
cuda-render/setup.ps1
cuda-render/QUICKSTART_VERIFIED.md
cuda-render/SETUP_WINDOWS_RENDER.md
cuda-render/.vscode/settings.json
cuda-render/.vscode/launch.json
cuda-render/conversion/hdr2mat.py
cuda-render/conversion/to_bike_format.py
```
None of these exist upstream, so just copy them in — nothing to merge.

### B) Edits to EXISTING source files (3 files)

These are the **required Windows/MSVC portability fixes**. Apply each exactly.

---

#### B1. `cuda-render/render/src/copydata.cu`  (1 edit)

MSVC's preprocessor rejects the word `and`. Near the top:

**BEFORE**
```cpp
#if  __CUDA_ARCH__ < 600 and defined(__CUDA_ARCH__)
```
**AFTER**
```cpp
#if defined(__CUDA_ARCH__) && __CUDA_ARCH__ < 600
```

---

#### B2. `cuda-render/render/src/main.cpp`  (4 edits)

**Edit 1 — includes + rewrite `getFiles()`** (Linux `ls` → `std::filesystem`)

BEFORE
```cpp
#include <vector>
#include <string>
#include <fstream>

#include "renderclass.h"

void getFiles(string parentFolder, vector<string> &vecFileNames) {

	string cmd = "ls " + parentFolder + " > temp.log";
	system(cmd.c_str());

	ifstream ifs("temp.log");
	if (ifs.fail()) {
		return;
	}

	string fileName;
	while (getline(ifs, fileName)) {
		vecFileNames.push_back(parentFolder + "/" + fileName);
	}

	ifs.close();
	return;
}
```
AFTER
```cpp
#include <vector>
#include <string>
#include <fstream>
#include <filesystem>   // C++17, Windows-portable directory listing / mkdir

namespace fs = std::filesystem;

#include "renderclass.h"

void getFiles(string parentFolder, vector<string> &vecFileNames) {

	if (!fs::exists(parentFolder)) {
		cout << "parent folder does not exist: " << parentFolder << endl;
		return;
	}

	for (const auto &entry : fs::directory_iterator(parentFolder)) {
		if (entry.is_directory())
			vecFileNames.push_back(entry.path().generic_string());
	}
	return;
}
```

**Edit 2 — first `mkdir` block** (in `main()`, right after the rot/shift vars)

BEFORE
```cpp
	char cmd[256];
	sprintf(cmd, "mkdir %s", parentSvFolder.c_str());
	system(cmd);

	for (int i = 0; i < 1; i++) {
		string svfolder = parentSvFolder + "/" + to_string(i);

		char cmd[256];
		sprintf(cmd, "mkdir %s", svfolder.c_str());
		system(cmd);
	}
```
AFTER
```cpp
	fs::create_directories(parentSvFolder);

	for (int i = 0; i < 1; i++) {
		string svfolder = parentSvFolder + "/" + to_string(i);
		fs::create_directories(svfolder);
	}
```

**Edit 3 — second `mkdir` block** (inside the model loop, after the two `cout`s)

BEFORE
```cpp
				char cmd[256];
				sprintf(cmd, "mkdir %s", svfolder.c_str());
				system(cmd);
```
AFTER
```cpp
				fs::create_directories(svfolder);
```

**Edit 4 — data paths** (set to absolute paths on the other machine; forward
slashes are fine). Upstream uses `../../data/...`; make them absolute so the
exe works from any working directory:
```cpp
	string parentFlder    = "D:/YOUR/PATH/data/bunny-model";
	string parentSvFolder = "D:/YOUR/PATH/data/bunny-renders";
```

---

#### B3. `cuda-render/render/src/display_6_render.cpp`  (4 edits)

**Edit 1 — add the filesystem include** (top of file)

BEFORE
```cpp
#include "renderclass.h"
#include <chrono>
```
AFTER
```cpp
#include "renderclass.h"
#include <chrono>
#include <filesystem>   // C++17, Windows-portable mkdir
```

**Edit 2 — add the time-bin macro** (next to `TBE`/`TEN`)

BEFORE
```cpp
#define TBE 0
#define TEN 6
```
AFTER
```cpp
#define TBE 0
#define TEN 6
#define NTBIN 2048   // number of time bins (was (TEN-TBE)*100 = 600)
```

**Edit 3 — the two `timebin` computations** (there are exactly TWO identical
lines; change both)

BEFORE (x2)
```cpp
	int timebin = (TEN - TBE) * 100;
```
AFTER (x2)
```cpp
	int timebin = NTBIN;
```

**Edit 4a — the `launch_cudaProcess2` depth args**

BEFORE
```cpp
					launch_cudaProcess2(in_array,
									cuda_dest_saver_resource, timebin, height,
									width, maxsz, 100 * TEN, 100 * TBE);
```
AFTER
```cpp
					launch_cudaProcess2(in_array,
									cuda_dest_saver_resource, timebin, height,
									width, maxsz, NTBIN, 0);
```

**Edit 4b — the `mkdir` block**

BEFORE
```cpp
		char cmd[256];
		sprintf(cmd, "mkdir %s", folder);
		system(cmd);
```
AFTER
```cpp
		std::filesystem::create_directories(folder);
```

---

### C) Config values you tune per run (in `main.cpp`)

These are **not** fixes — they select resolution / dataset size. Current values:

| Variable | Location | Meaning | Values I used |
|---|---|---|---|
| `int height`, `int width` | `main()` | spatial resolution | 256 → 128 → **64** |
| `#define NTBIN` | `display_6_render.cpp` | time bins | 600 → 1024 → **2048** |
| `bool definerot` | `main()` | `true`=fixed pose, `false`=random | **false** for a dataset |
| `int rnum` | model loop | poses per model | **5** |
| `int rendernum` | `main()` | number of models to process | **10** |

For a single fixed sample: `definerot=true`, `rnum=1`, `rendernum=1`.
For a bike-style dataset: `definerot=false`, `rnum=5`, `rendernum=10`, and put
N model folders under `parentFlder` as `<name>/model/model_normalized.obj`.

---

## After applying the changes — build & run

Install once: **CUDA 11.8** (not 12.x), **Visual Studio 2022 + C++ workload**,
**Git**. Then from `cuda-render/`:

```powershell
powershell -ExecutionPolicy Bypass -File .\setup.ps1
```
`setup.ps1` installs vcpkg (GLEW/GLFW/GLM) + OpenCV, configures, builds, runs.
Details/troubleshooting in `cuda-render/QUICKSTART_VERIFIED.md`.

To produce the bike-format dataset from raw output:
```powershell
python cuda-render/conversion/to_bike_format.py <raw_root> output --timebin 2048 --hw 64
```

---

## Summary — files touched today

- **3 source files edited:** `copydata.cu` (1), `main.cpp` (4), `display_6_render.cpp` (4)
- **13 new files added** (build system, scripts, docs, converters) — list in section A
- Full rationale for each in `CHANGELOG.md`
