# Fetches the pinned llama.cpp (for its ggml) and stable-diffusion.cpp, applies the patches,
# and installs the Hexagon SDK via llama.cpp's official setup script.
. "$PSScriptRoot\common.ps1"

function Get-PinnedRepo([string]$Url, [string]$Commit, [string]$Dir) {
    if (-not (Test-Path (Join-Path $Dir '.git'))) {
        New-Item -ItemType Directory -Force $Dir | Out-Null
        git -C $Dir init -q
        git -C $Dir remote add origin $Url
    }
    git -C $Dir fetch -q --depth 1 origin $Commit
    git -C $Dir checkout -q --force FETCH_HEAD
    if ($LASTEXITCODE -ne 0) { throw "checkout of $Commit failed in $Dir" }
}

function Apply-Patch([string]$Dir, [string]$Patch) {
    git -C $Dir apply --check $Patch 2>$null
    if ($LASTEXITCODE -eq 0) {
        git -C $Dir apply $Patch
        Write-Host "   applied $(Split-Path -Leaf $Patch)"
        return
    }
    git -C $Dir apply --reverse --check $Patch 2>$null
    if ($LASTEXITCODE -eq 0) { Write-Host "   already applied $(Split-Path -Leaf $Patch)"; return }
    throw "Patch $Patch does not apply to $Dir"
}

New-Item -ItemType Directory -Force $Work | Out-Null

Write-Step "llama.cpp @ $($LlamaCppCommit.Substring(0, 7))"
Get-PinnedRepo $LlamaCppRepo $LlamaCppCommit $LlamaDir
Apply-Patch $LlamaDir (Join-Path $RepoRoot 'patches\llama.cpp-ggml-hexagon-inplace-view-src.patch')

Write-Step "stable-diffusion.cpp @ $($SdCppCommit.Substring(0, 7))"
Get-PinnedRepo $SdCppRepo $SdCppCommit $SdDir
# ggml comes from llama.cpp and libwebm is disabled, so only these submodules are needed.
git -C $SdDir submodule update --init --depth 1 examples/server/frontend thirdparty/libwebp
Apply-Patch $SdDir (Join-Path $RepoRoot 'patches\sdcpp-rope-no-repeat.patch')

if (-not (Get-HexagonSdkRoot)) {
    Write-Step "Hexagon SDK $HexagonSdkVer (downloads ~1 GB into C:\Qualcomm)"
    python (Join-Path $LlamaDir 'scripts\snapdragon\setup-sdk.py') --hexagon $HexagonSdkVer
    if ($LASTEXITCODE -ne 0) { throw 'setup-sdk.py failed' }
} else {
    Write-Step "Hexagon SDK already present: $(Get-HexagonSdkRoot)"
}

Write-Host "`nSources ready in $Work" -ForegroundColor Green
