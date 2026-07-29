<#
================================================================================
  simulate_folder.ps1  -  simulate EVERY model under a source folder in one go.

  Finds all  <name>/models/model_normalized.obj  under <SourceRoot>, prepares
  each (triangulate+normalize), renders them all, and writes the bike-style
  dataset to <OutName>\0\<name>\ .

  USAGE:
     powershell -ExecutionPolicy Bypass -File .\simulate_folder.ps1 <SourceRoot> [options]

  EXAMPLES:
     .\simulate_folder.ps1 ..\NLOS-DATA
     .\simulate_folder.ps1 ..\NLOS-DATA -Poses 3 -OutName output-nlos
     .\simulate_folder.ps1 ..\NLOS-DATA -Single -HW 64 -TimeBin 2048
================================================================================
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true, Position=0)][string]$SourceRoot,
    [int]   $Poses   = 1,
    [int]   $TimeBin = 2048,
    [int]   $HW      = 64,
    [double]$Extent  = 0.9,
    [switch]$Single,
    [string]$OutName = "output-nlos"
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
$models     = Join-Path $RepoRoot "data\batch-models"
$raw        = Join-Path $RepoRoot "data\batch-raw"
$out        = Join-Path $RepoRoot $OutName
$prep       = Join-Path $CudaRender "conversion\prepare_obj.py"
$tobike     = Join-Path $CudaRender "conversion\to_bike_format.py"

if (-not (Test-Path $SourceRoot)) { Die "source not found: $SourceRoot" }

# cmake (bundled with VS)
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$VsRoot  = & $vswhere -latest -property installationPath
$CMake   = Join-Path $VsRoot "Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
if (-not (Test-Path $CMake)) { $CMake = "cmake" }

if (-not (Test-Path (Join-Path $BuildDir "Release\nlos_render.exe"))) {
    Step "First-time setup (setup.ps1 -NoRun)"
    & (Join-Path $CudaRender "setup.ps1") -NoRun
    if ($LASTEXITCODE -ne 0) { Die "setup.ps1 failed - run it manually once, then retry." }
}

# 1) collect canonical models: <name>/models/model_normalized.obj
Step "Collecting models under $SourceRoot"
$objs = Get-ChildItem -Recurse $SourceRoot -Filter "model_normalized.obj" -File |
        Where-Object { $_.Directory.Name -eq "models" }
if (-not $objs) { Die "no <name>/models/model_normalized.obj found under $SourceRoot" }
Write-Host ("found {0} models" -f $objs.Count)

# 2) prepare each into a fresh staging folder
Step "Preparing $($objs.Count) models"
Remove-Item -Recurse -Force $models, $raw -ErrorAction SilentlyContinue
$count = 0
foreach ($o in $objs) {
    $name = $o.Directory.Parent.Name          # the <name> folder
    python $prep "$($o.FullName)" "$models" "$name" --extent $Extent 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) { $count++ } else { Write-Host "  [skip] $name (prepare failed)" -ForegroundColor Yellow }
}
if ($count -eq 0) { Die "no models prepared." }
Write-Host "prepared $count models"

# 3) patch render config
Step ("Configuring  HW={0}  TimeBin={1}  {2}  models={3}" -f $HW, $TimeBin, ($(if($Single){"1 pose"}else{"$Poses poses"})), $count)
$t = Get-Content $mainCpp -Raw
$t = $t -replace '(parentFlder\s*=\s*")[^"]*(")',    "`${1}$RepoFwd/data/batch-models`${2}"
$t = $t -replace '(parentSvFolder\s*=\s*")[^"]*(")', "`${1}$RepoFwd/data/batch-raw`${2}"
$t = $t -replace 'int height = \d+;', "int height = $HW;"
$t = $t -replace 'int width = \d+;',  "int width = $HW;"
if ($Single) {
    $t = $t -replace 'bool definerot = \w+;', 'bool definerot = true;'
    $t = $t -replace 'int rnum = \d+;',       'int rnum = 1;'
} else {
    $t = $t -replace 'bool definerot = \w+;', 'bool definerot = false;'
    $t = $t -replace 'int rnum = \d+;',       "int rnum = $Poses;"
}
$t = $t -replace 'int rendernum = \d+;', "int rendernum = $count;"
Set-Content $mainCpp $t -Encoding UTF8

$d = Get-Content $dispCpp -Raw
$d = $d -replace '#define NTBIN \d+', "#define NTBIN $TimeBin"
Set-Content $dispCpp $d -Encoding UTF8

# 4) build
Step "Building"
& $CMake --build $BuildDir --config Release | Out-Null
if ($LASTEXITCODE -ne 0) { Die "build failed." }

# 5) render all models (one run)
Step "Rendering $count models"
Push-Location (Join-Path $BuildDir "Release")
& ".\nlos_render.exe" *>&1 | Select-String "done!" | Select-Object -Last 1
$rc = $LASTEXITCODE
Pop-Location
if ($rc -ne 0) { Die "render failed (exit $rc)." }

# 6) convert to bike layout
Step "Converting to bike format -> $OutName"
python $tobike "$raw" "$out" --timebin $TimeBin --hw $HW
if ($LASTEXITCODE -ne 0) { Die "to_bike_format failed." }

$ns = (Get-ChildItem -Recurse (Join-Path $out "0") -Directory -Filter "shine_*" -ErrorAction SilentlyContinue).Count
$nm = (Get-ChildItem (Join-Path $out "0") -Directory -ErrorAction SilentlyContinue).Count
Write-Host ("`nDONE: {0} models, {1} samples -> {2}\0\   ({3}x{3}x{4})" -f $nm, $ns, $OutName, $HW, $TimeBin) -ForegroundColor Green
