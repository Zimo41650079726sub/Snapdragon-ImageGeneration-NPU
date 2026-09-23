# Shared settings and helpers. Dot-source from the other scripts: . "$PSScriptRoot\common.ps1"

$ErrorActionPreference = 'Stop'

# Pinned upstream revisions this recipe was verified with (2026-09-23).
$LlamaCppRepo   = 'https://github.com/ggml-org/llama.cpp.git'
$LlamaCppCommit = 'e6ab7c1a41054a888ada952eab4c886444c2f5ad'
$SdCppRepo      = 'https://github.com/leejet/stable-diffusion.cpp.git'
$SdCppCommit    = 'c92d73c408515c94beef32161bb5960764fde7a0'
$HexagonSdkVer  = '6.6.0.0'

$RepoRoot = Split-Path -Parent $PSScriptRoot
if (-not $env:SNPU_WORK) { $env:SNPU_WORK = Join-Path $HOME 'snapdragon-npu-work' }
$Work     = $env:SNPU_WORK
$LlamaDir = Join-Path $Work 'llama.cpp'
$SdDir    = Join-Path $Work 'stable-diffusion.cpp'
$BuildDir = Join-Path $SdDir 'build-npu'
$HtpDir   = Join-Path $BuildDir 'htp'

function Find-VsArm64 {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (-not (Test-Path $vswhere)) { return $null }
    $path = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.ARM64 -property installationPath
    if (-not $path) { return $null }
    $vcvars = Join-Path $path 'VC\Auxiliary\Build\vcvarsall.bat'
    if (Test-Path $vcvars) { return $vcvars }
    return $null
}

function Find-LlvmBin {
    foreach ($p in @("$env:ProgramFiles\LLVM\bin", "$env:LOCALAPPDATA\Programs\LLVM\bin")) {
        if (Test-Path (Join-Path $p 'clang.exe')) { return $p }
    }
    $c = Get-Command clang.exe -ErrorAction SilentlyContinue
    if ($c) { return Split-Path -Parent $c.Source }
    return $null
}

# Newest copy of a Windows Kits tool (inf2cat ships only as x86; signtool prefers arm64).
function Find-KitTool([string]$Name, [string[]]$Arches = @('arm64', 'x64', 'x86')) {
    $root = Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10\bin'
    if (-not (Test-Path $root)) { return $null }
    $versions = Get-ChildItem $root -Directory | Where-Object Name -match '^\d+\.\d+\.\d+\.\d+$' |
        Sort-Object { [version]$_.Name } -Descending
    foreach ($v in $versions) {
        foreach ($a in $Arches) {
            $f = Join-Path $v.FullName "$a\$Name"
            if (Test-Path $f) { return $f }
        }
    }
    foreach ($a in $Arches) {
        $f = Join-Path $root "$a\$Name"
        if (Test-Path $f) { return $f }
    }
    return $null
}

function Get-HexagonSdkRoot {
    $u = [Environment]::GetEnvironmentVariable('HEXAGON_SDK_ROOT', 'User')
    if ($env:HEXAGON_SDK_ROOT) { return $env:HEXAGON_SDK_ROOT }
    if ($u) { return $u }
    $d = "C:\Qualcomm\Hexagon_SDK\$HexagonSdkVer"
    if (Test-Path $d) { return $d }
    return $null
}

function Get-HexagonToolsRoot([string]$SdkRoot) {
    $u = [Environment]::GetEnvironmentVariable('HEXAGON_TOOLS_ROOT', 'User')
    if ($env:HEXAGON_TOOLS_ROOT) { return $env:HEXAGON_TOOLS_ROOT }
    if ($u) { return $u }
    $t = Get-ChildItem (Join-Path $SdkRoot 'tools\HEXAGON_Tools') -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
    if ($t) { return $t.FullName }
    return $null
}

function Write-Step([string]$msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
