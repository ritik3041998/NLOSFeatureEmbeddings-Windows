<#
================================================================================
  simulate_obj.ps1  -  generate NLOS data for ONE .obj in a single command.

  Does everything: prepare (triangulate+normalize) -> configure -> build ->
  render -> convert to the `bike` layout under  <repo>\output\0\<name>\ .

  USAGE:
     powershell -ExecutionPolicy Bypass -File .\simulate_obj.ps1 <your.obj> <name>

  EXAMPLES:
     .\simulate_obj.ps1  C:\models\car.obj   car               # 5 random poses
     .\simulate_obj.ps1  C:\models\car.obj   car -Single        # 1 fixed sample
     .\simulate_obj.ps1  C:\models\car.obj   car -Poses 10      # 10 poses
     .\simulate_obj.ps1  C:\models\car.obj   car -HW 128 -TimeBin 1024 -Extent 0.7

  Run it once per model; output\ accumulates all models (output\0\<name>\...).
  Requires that the project was built once already (else it auto-runs setup.ps1).
================================================================================
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0)][string]$Obj,
    [Parameter(Mandatory=$true, Position=1)][string]$Name,
    [double]$Extent  = 0.9,
    [int]   $Poses   = 5,
    [int]   $TimeBin = 2048,
    [int]   $HW      = 64,
    [switch]$Single
)
$ErrorActionPreference = "Stop"
function Step($m){ Write-Host "`n=== $m ===" -ForegroundColor Cyan }
function Die($m){ Write-Host "ERROR: $m" -ForegroundColor Red; exit 1 }

$CudaRender = $PSScriptRoot
$RepoRoot   = Split-Path $CudaRender -Parent
$RepoFwd    = $RepoRoot -replace '\\','/'
$mainCpp    = Join-Path $CudaRender "render\src\main.cpp"
$dispCpp    = Join-Path $CudaRender "render\src\display_6_render.cpp"
$BuildDir   = Join-Path $CudaRender "build"
$models     = Join-Path $RepoRoot "data\my-models"
$raw        = Join-Path $RepoRoot "data\my-raw"
$out        = Join-Path $RepoRoot "output"

if (-not (Test-Path $Obj)) { Die "obj not found: $Obj" }

# locate the CMake bundled with Visual Studio
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$VsRoot  = & $vswhere -latest -property installationPath
$CMake   = Join-Path $VsRoot "Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
if (-not (Test-Path $CMake)) { $CMake = "cmake" }

# first-time: configure + build the project (installs libs via setup.ps1)
if (-not (Test-Path (Join-Path $BuildDir "Release\nlos_render.exe"))) {
    Step "First-time setup (setup.ps1 -NoRun)"
    & (Join-Path $CudaRender "setup.ps1") -NoRun
    if ($LASTEXITCODE -ne 0) { Die "setup.ps1 failed - run it manually once, then retry." }
}

# 1) prepare the obj (fresh my-models with just this model)
Step "Preparing '$Name' from $Obj"
Remove-Item -Recurse -Force $models, $raw -ErrorAction SilentlyContinue
python (Join-Path $CudaRender "conversion\prepare_obj.py") "$Obj" "$models" "$Name" --extent $Extent
if ($LASTEXITCODE -ne 0) { Die "prepare_obj.py failed." }

# 2) patch the render config
Step ("Configuring  HW={0}  TimeBin={1}  {2}" -f $HW, $TimeBin, ($(if($Single){"single sample"}else{"$Poses poses"})))
$t = Get-Content $mainCpp -Raw
$t = $t -replace '(parentFlder\s*=\s*")[^"]*(")',    "`${1}$RepoFwd/data/my-models`${2}"
$t = $t -replace '(parentSvFolder\s*=\s*")[^"]*(")', "`${1}$RepoFwd/data/my-raw`${2}"
$t = $t -replace 'int height = \d+;', "int height = $HW;"
$t = $t -replace 'int width = \d+;',  "int width = $HW;"
if ($Single) {
    $t = $t -replace 'bool definerot = \w+;', 'bool definerot = true;'
    $t = $t -replace 'int rnum = \d+;',       'int rnum = 1;'
} else {
    $t = $t -replace 'bool definerot = \w+;', 'bool definerot = false;'
    $t = $t -replace 'int rnum = \d+;',       "int rnum = $Poses;"
}
$t = $t -replace 'int rendernum = \d+;', 'int rendernum = 1;'
Set-Content $mainCpp $t -Encoding UTF8

$d = Get-Content $dispCpp -Raw
$d = $d -replace '#define NTBIN \d+', "#define NTBIN $TimeBin"
Set-Content $dispCpp $d -Encoding UTF8

# 3) build
Step "Building"
& $CMake --build $BuildDir --config Release | Out-Null
if ($LASTEXITCODE -ne 0) { Die "build failed." }

# 4) render
Step "Rendering '$Name'"
Push-Location (Join-Path $BuildDir "Release")
& ".\nlos_render.exe" *>&1 | Select-Object -Last 1
$rc = $LASTEXITCODE
Pop-Location
if ($rc -ne 0) { Die "render failed (exit $rc)." }

# 5) convert to bike layout (accumulates in output\)
Step "Converting to bike format"
python (Join-Path $CudaRender "conversion\to_bike_format.py") "$raw" "$out" --timebin $TimeBin --hw $HW
if ($LASTEXITCODE -ne 0) { Die "to_bike_format.py failed." }

$n = (Get-ChildItem -Recurse (Join-Path $out "0\$Name") -Directory -Filter "shine_*" -ErrorAction SilentlyContinue).Count
Write-Host ("`nDONE: {0} sample(s) -> output\0\{1}\   ({2}x{2}x{3})" -f $n, $Name, $HW, $TimeBin) -ForegroundColor Green
