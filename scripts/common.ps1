# Shared settings and helpers. Dot-source from the other scripts: . "$PSScriptRoot\common.ps1"

$ErrorActionPreference = 'Stop'

# Two ways to get HTP (NPU-side) libraries the Windows driver will load:
#   signed      (default) Microsoft-signed libraries from Qualcomm's GenieX SDK. Works in normal
#               Windows (Secure Boot on, no test signing). The host side must be built from the same
#               llama.cpp revision + GenieX's hexagon patches so the two halves speak the same protocol.
#   self-signed Build the HTP libraries yourself from a newer llama.cpp and sign them with your own
#               certificate. ~1.4x faster DiT today, but needs test-signing mode (see README appendix).
if (-not $env:SNPU_MODE) { $env:SNPU_MODE = 'signed' }
$Mode = $env:SNPU_MODE
if ($Mode -notin 'signed', 'self-signed') { throw "SNPU_MODE must be 'signed' or 'self-signed' (got '$Mode')" }

# Pinned upstream revisions this recipe was verified with (2026-09-23).
$LlamaCppRepo = 'https://github.com/ggml-org/llama.cpp.git'
$SdCppRepo    = 'https://github.com/leejet/stable-diffusion.cpp.git'
$SdCppCommit  = 'c92d73c408515c94beef32161bb5960764fde7a0'
$HexagonSdkVer = '6.6.0.0'

# GenieX v0.7.0 ships llama.cpp 4ff829ec plus these hexagon patches; its HTP libraries are signed by
# "Microsoft Windows Hardware Compatibility Publisher".
$GenieXTag       = 'v0.7.0'
$GenieXSdkUrl    = "https://github.com/qualcomm/GenieX/releases/download/$GenieXTag/geniex-sdk-windows-arm64-$GenieXTag.zip"
$GenieXSdkSha256 = '661edfb20c41daa49befacc12a922aeb6a17770d3228b346b4c62dfa5715b99e'
$GenieXPatches = [ordered]@{
    'llama-hexagon-power-mode.patch'        = 'e3e5dcdb4363d28e26b6a550dfabf5f401fa91aca31d730fb51162d7aa1cd159'
    'llama-hexagon-power-mode-setter.patch' = '2e47781e4c98f8f1d6bd097fa8b46c90af14d3dbc616e1fff4bcf1fa3c4564ca'
    'llama-hexagon-release-sessions.patch'  = '98ce1c9849f43764b4f3ae2fd1437848edaca616d22bf4ea18873674bfab961a'
}

if ($Mode -eq 'signed') {
    $LlamaCppCommit = '4ff829ec2e2f526aa6afba529eebbfb3ef1f95ec'
} else {
    $LlamaCppCommit = 'e6ab7c1a41054a888ada952eab4c886444c2f5ad'
}
if ($env:SNPU_LLAMA_COMMIT) { $LlamaCppCommit = $env:SNPU_LLAMA_COMMIT }

$RepoRoot = Split-Path -Parent $PSScriptRoot
if (-not $env:SNPU_WORK) { $env:SNPU_WORK = Join-Path $HOME 'snapdragon-npu-work' }
$Work      = $env:SNPU_WORK
$LlamaDir  = Join-Path $Work 'llama.cpp'
$SdDir     = Join-Path $Work 'stable-diffusion.cpp'
$BuildDir  = Join-Path $SdDir 'build-npu'
$GenieXDir = Join-Path $Work "geniex-sdk-$GenieXTag"
# Folder the NPU loads libggml-htp-v*.so (and its signed .cat) from.
if ($Mode -eq 'signed') {
    $HtpDir = Join-Path $GenieXDir 'sdk-windows-arm64\lib\llama_cpp'
} else {
    $HtpDir = Join-Path $BuildDir 'htp'
}

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

function Test-FileSha256([string]$Path, [string]$Expected) {
    return (Get-FileHash -Algorithm SHA256 $Path).Hash.ToLower() -eq $Expected.ToLower()
}

function Write-Step([string]$msg) { Write-Host "==> $msg" -ForegroundColor Cyan }
