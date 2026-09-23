# Fetches the pinned llama.cpp (for its ggml) and stable-diffusion.cpp, applies the patches, installs the
# Hexagon SDK (needed to build the host side), and in 'signed' mode downloads the Microsoft-signed HTP
# libraries from the GenieX SDK.
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

function Get-Verified([string]$Url, [string]$Out, [string]$Sha256) {
    if (-not ((Test-Path $Out) -and (Test-FileSha256 $Out $Sha256))) {
        Invoke-WebRequest -UseBasicParsing $Url -OutFile $Out
    }
    if (-not (Test-FileSha256 $Out $Sha256)) { throw "SHA256 mismatch for $Out (download corrupted or changed upstream)" }
}

New-Item -ItemType Directory -Force $Work | Out-Null
Write-Host "Mode: $Mode"

Write-Step "llama.cpp @ $($LlamaCppCommit.Substring(0, 7))"
# Re-checkout from scratch so re-running never stacks patches twice.
if (Test-Path (Join-Path $LlamaDir '.git')) { git -C $LlamaDir checkout -q --force . ; git -C $LlamaDir clean -q -fd }
Get-PinnedRepo $LlamaCppRepo $LlamaCppCommit $LlamaDir
Apply-Patch $LlamaDir (Join-Path $RepoRoot 'patches\llama.cpp-ggml-hexagon-inplace-view-src.patch')
if ($Mode -eq 'signed') {
    $pdir = Join-Path $Work "geniex-patches-$GenieXTag"
    New-Item -ItemType Directory -Force $pdir | Out-Null
    foreach ($name in $GenieXPatches.Keys) {
        $out = Join-Path $pdir $name
        Get-Verified "https://raw.githubusercontent.com/qualcomm/GenieX/$GenieXTag/sdk/patches/$name" $out $GenieXPatches[$name]
        Apply-Patch $LlamaDir $out
    }
    Apply-Patch $LlamaDir (Join-Path $RepoRoot 'patches\llama.cpp-ggml-hexagon-geniex-4ff829-workarounds.patch')
}

Write-Step "stable-diffusion.cpp @ $($SdCppCommit.Substring(0, 7))"
if (Test-Path (Join-Path $SdDir '.git')) { git -C $SdDir checkout -q --force . }
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

if ($Mode -eq 'signed') {
    Write-Step "GenieX $GenieXTag SDK (Microsoft-signed HTP libraries, ~85 MB)"
    New-Item -ItemType Directory -Force $GenieXDir | Out-Null
    $zip = Join-Path $GenieXDir 'geniex-sdk.zip'
    Get-Verified $GenieXSdkUrl $zip $GenieXSdkSha256
    if (-not (Test-Path (Join-Path $HtpDir 'libggml-htp.cat'))) {
        Expand-Archive $zip -DestinationPath $GenieXDir -Force
    }
    $sig = Get-AuthenticodeSignature (Join-Path $HtpDir 'libggml-htp.cat')
    if ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'Microsoft') {
        throw "Unexpected signature on libggml-htp.cat: $($sig.Status) $($sig.SignerCertificate.Subject)"
    }
    Write-Host "   libggml-htp.cat signed by: $($sig.SignerCertificate.Subject.Split(',')[0])"
}

Write-Host "`nSources ready in $Work" -ForegroundColor Green
