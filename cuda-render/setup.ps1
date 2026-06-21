<#
================================================================================
  setup.ps1  -  one-command build & run for the NLOS cuda-render data generator
  on a fresh Windows 11 machine.

  USAGE (from anywhere):
      powershell -ExecutionPolicy Bypass -File .\setup.ps1            # build + run
      powershell -ExecutionPolicy Bypass -File .\setup.ps1 -NoRun     # build only
      powershell -ExecutionPolicy Bypass -File .\setup.ps1 -Clean     # wipe build/ first

  WHAT IT DOES AUTOMATICALLY:
    * finds the repo from this script's location (paste the folder anywhere)
    * installs GLEW/GLFW/GLM via vcpkg          (downloads vcpkg if missing)
    * downloads + extracts prebuilt OpenCV       (if missing)
    * patches the bunny data paths to THIS machine's location
    * configures (CUDA 11.8 + RTX/sm auto), builds Release, copies the OpenCV dll
    * runs nlos_render.exe

  PREREQUISITES IT ONLY CHECKS (install these once, manually):
    1. Visual Studio 2022 + "Desktop development with C++" workload
    2. CUDA Toolkit 11.8   (NOT 12.x)
    3. An NVIDIA GPU + recent driver
================================================================================
#>
[CmdletBinding()]
param(
    [switch]$NoRun,
    [switch]$Clean,
    [string]$VcpkgRoot   = "C:\dev\vcpkg",
    [string]$OpenCVRoot  = "C:\dev\opencv",
    [string]$OpenCVVer   = "4.10.0",
    [int]   $CudaArch    = 0          # 0 = auto-detect from the installed GPU
)

$ErrorActionPreference = "Stop"
function Step($m){ Write-Host "`n=== $m ===" -ForegroundColor Cyan }
function Die($m){ Write-Host "ERROR: $m" -ForegroundColor Red; exit 1 }

# ---- paths -------------------------------------------------------------------
$CudaRender = $PSScriptRoot                       # ...\cuda-render
$RepoRoot   = Split-Path $CudaRender -Parent      # repo root (contains \data)
$RepoFwd    = $RepoRoot -replace '\\','/'
Write-Host "Repo root: $RepoRoot"

# ---- prereq 1: CUDA 11.8 -----------------------------------------------------
Step "Checking CUDA 11.8"
$CudaDir = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v11.8"
if (-not (Test-Path "$CudaDir\bin\nvcc.exe")) {
    Die "CUDA 11.8 not found at $CudaDir.`n      Install it from https://developer.nvidia.com/cuda-11-8-0-download-archive (NOT CUDA 12.x)."
}
& "$CudaDir\bin\nvcc.exe" --version | Select-String "release" | ForEach-Object { Write-Host "  $_" }

# ---- prereq 2: Visual Studio 2022 + C++ --------------------------------------
Step "Checking Visual Studio 2022 (C++ workload)"
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) { Die "Visual Studio Installer not found. Install VS 2022 Community + 'Desktop development with C++'." }
$VsRoot = & $vswhere -latest -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $VsRoot) { Die "VS 2022 with the C++ toolset not found. Add 'Desktop development with C++' in the VS Installer." }
Write-Host "  VS: $VsRoot"
$CMake = Join-Path $VsRoot "Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
if (-not (Test-Path $CMake)) { $CMake = "cmake" }   # fall back to PATH
Write-Host "  cmake: $CMake"

# ---- detect GPU compute capability ------------------------------------------
if ($CudaArch -eq 0) {
    try {
        $cc = (& nvidia-smi --query-gpu=compute_cap --format=csv,noheader | Select-Object -First 1).Trim()
        $CudaArch = [int]($cc -replace '\.','')      # "8.6" -> 86
    } catch { $CudaArch = 86 }                        # default RTX 3050
}
Write-Host "  CUDA architecture: sm_$CudaArch"

# ---- vcpkg + GLEW/GLFW/GLM ---------------------------------------------------
Step "Setting up vcpkg + GLEW/GLFW/GLM"
if (-not (Test-Path "$VcpkgRoot\vcpkg.exe")) {
    if (-not (Test-Path $VcpkgRoot)) { git clone https://github.com/microsoft/vcpkg $VcpkgRoot }
    & "$VcpkgRoot\bootstrap-vcpkg.bat" -disableMetrics
}
& "$VcpkgRoot\vcpkg.exe" install glew:x64-windows glfw3:x64-windows glm:x64-windows
if ($LASTEXITCODE -ne 0) { Die "vcpkg install failed." }

# ---- prebuilt OpenCV ---------------------------------------------------------
Step "Setting up OpenCV $OpenCVVer (prebuilt)"
if (-not (Test-Path "$OpenCVRoot\build\OpenCVConfig.cmake")) {
    $exe = "C:\dev\opencv-$OpenCVVer-windows.exe"
    if (-not (Test-Path $exe)) {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest "https://github.com/opencv/opencv/releases/download/$OpenCVVer/opencv-$OpenCVVer-windows.exe" -OutFile $exe
    }
    Start-Process $exe -ArgumentList "-o`"$(Split-Path $OpenCVRoot -Parent)`" -y" -Wait
}
if (-not (Test-Path "$OpenCVRoot\build\OpenCVConfig.cmake")) { Die "OpenCV extract failed." }
$OcvDll = Get-ChildItem "$OpenCVRoot\build\x64\vc16\bin\opencv_world*.dll" | Select-Object -First 1
Write-Host "  OpenCV dll: $($OcvDll.Name)"

# ---- patch bunny data paths to THIS machine ----------------------------------
Step "Patching data paths in main.cpp"
$mainCpp = Join-Path $CudaRender "render\src\main.cpp"
$txt = Get-Content $mainCpp -Raw
$txt = $txt -replace '(string\s+parentFlder\s*=\s*")[^"]*(")',    "`${1}$RepoFwd/data/bunny-model`${2}"
$txt = $txt -replace '(string\s+parentSvFolder\s*=\s*")[^"]*(")', "`${1}$RepoFwd/data/bunny-renders`${2}"
Set-Content $mainCpp $txt -Encoding UTF8
Write-Host "  input : $RepoFwd/data/bunny-model"
Write-Host "  output: $RepoFwd/data/bunny-renders"

# ---- configure + build -------------------------------------------------------
Step "Configuring"
$BuildDir = Join-Path $CudaRender "build"
if ($Clean -and (Test-Path $BuildDir)) { Remove-Item -Recurse -Force $BuildDir }
$VcpkgFwd = $VcpkgRoot -replace '\\','/'
$OcvFwd   = $OpenCVRoot -replace '\\','/'
$cfgArgs = @(
    "-B", $BuildDir, "-S", $CudaRender,
    "-G", "Visual Studio 17 2022", "-A", "x64", "-T", "cuda=11.8",
    "-DCMAKE_TOOLCHAIN_FILE=$VcpkgFwd/scripts/buildsystems/vcpkg.cmake",
    "-DOpenCV_DIR=$OcvFwd/build",
    "-DCMAKE_CUDA_ARCHITECTURES=$CudaArch",
    "-DCMAKE_CUDA_FLAGS=-allow-unsupported-compiler"
)
& $CMake @cfgArgs
if ($LASTEXITCODE -ne 0) { Die "CMake configure failed." }

Step "Building (Release)"
& $CMake --build $BuildDir --config Release
if ($LASTEXITCODE -ne 0) { Die "Build failed." }

$Exe = Join-Path $BuildDir "Release\nlos_render.exe"
if (-not (Test-Path $Exe)) { Die "Executable not produced." }
Copy-Item $OcvDll.FullName (Split-Path $Exe -Parent) -Force
Write-Host "`nBUILD OK -> $Exe" -ForegroundColor Green

# ---- run ---------------------------------------------------------------------
if ($NoRun) { Write-Host "(-NoRun set; skipping execution)"; exit 0 }
Step "Running renderer"
Push-Location (Split-Path $Exe -Parent)
& $Exe
$code = $LASTEXITCODE
Pop-Location
if ($code -ne 0) { Die "Renderer exited with code $code." }
Write-Host "`nDONE. Output in: $RepoRoot\data\bunny-renders" -ForegroundColor Green
