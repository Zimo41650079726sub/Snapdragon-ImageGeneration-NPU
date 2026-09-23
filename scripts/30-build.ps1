# Builds stable-diffusion.cpp (sd-cli / sd-server) against llama.cpp's ggml with the Hexagon backend,
# then stages the HTP libraries (v73..v81) plus the .inf into build-npu\htp for signing.
. "$PSScriptRoot\common.ps1"

$vcvars = Find-VsArm64
$llvm   = Find-LlvmBin
$sdk    = Get-HexagonSdkRoot
if (-not $vcvars) { throw 'Visual Studio with the ARM64 C++ toolset not found.' }
if (-not $llvm)   { throw 'LLVM clang not found (winget install LLVM.LLVM).' }
if (-not $sdk)    { throw 'Hexagon SDK not found. Run 20-get-sources.ps1 first.' }
$tools = Get-HexagonToolsRoot $sdk
$ggmlSrc = (Join-Path $LlamaDir 'ggml') -replace '\\', '/'
$toolchain = (Join-Path $LlamaDir 'cmake\arm64-windows-llvm.cmake') -replace '\\', '/'

$configure = @(
    'cmake', '-S', "`"$SdDir`"", '-B', "`"$BuildDir`"", '-G', 'Ninja',
    '-DCMAKE_BUILD_TYPE=Release',
    "-DCMAKE_TOOLCHAIN_FILE=$toolchain",
    '"-DCMAKE_C_FLAGS=-march=armv8.7a+fp16+dotprod+i8mm -D_GNU_SOURCE"',
    '"-DCMAKE_CXX_FLAGS=-march=armv8.7a+fp16+dotprod+i8mm -D_GNU_SOURCE"',
    '-DGGML_HEXAGON=ON', '-DGGML_OPENMP=OFF', '-DGGML_LLAMAFILE=OFF',
    "`"-DHEXAGON_SDK_ROOT=$sdk`"", "`"-DHEXAGON_TOOLS_ROOT=$tools`"",
    '-DPREBUILT_LIB_DIR=windows_aarch64',
    '-DSD_BUILD_SHARED_GGML_LIB=ON',
    # Signing is done separately by 40-sign-htp.ps1 (upstream's in-build signing cannot take a pfx password).
    '-DGGML_HEXAGON_HTP_CERT=',
    # libwebm builds as a DLL without exports on Windows and breaks the link; not needed for images.
    '-DSD_WEBM=OFF',
    # sd.cpp's bundled ggml has an older Hexagon backend that crashes the DSP; use llama.cpp's.
    '-DSD_USE_UPSTREAM_GGML=ON', "-DSD_GGML_SOURCE_DIR=$ggmlSrc"
) -join ' '

# PYTHONUTF8: on non-English Windows, Python defaults to the ANSI code page and the
# OpenCL/Hexagon code generators choke on UTF-8 sources.
$cmd = "call `"$vcvars`" arm64 >nul && set `"PATH=$llvm;%PATH%`" && set PYTHONUTF8=1 && " +
       "set `"HEXAGON_SDK_ROOT=$sdk`" && set `"HEXAGON_TOOLS_ROOT=$tools`" && set `"HEXAGON_HTP_CERT=`" && " +
       "$configure && cmake --build `"$BuildDir`" -j $([Environment]::ProcessorCount)"

Write-Step 'Configuring and building (10-15 minutes on first run)'
$log = Join-Path $Work 'build-npu.log'
cmd /c $cmd *> $log
if ($LASTEXITCODE -ne 0) {
    Get-Content $log | Select-String 'error|FAILED' | Select-Object -Last 15
    throw "Build failed, see $log"
}

Write-Step "Staging HTP libraries into $HtpDir"
New-Item -ItemType Directory -Force $HtpDir | Out-Null
Get-ChildItem $HtpDir -File | Remove-Item
$skels = Get-ChildItem $BuildDir -Recurse -Filter 'libggml-htp-v*.so' | Where-Object FullName -match 'htp-v\d+-build'
if (-not $skels) { throw 'No libggml-htp-v*.so found in the build tree.' }
$skels | Copy-Item -Destination $HtpDir
Copy-Item (Join-Path $LlamaDir 'ggml\src\ggml-hexagon\libggml-htp.inf') $HtpDir

Write-Host "`nBuilt: $BuildDir\bin\sd-cli.exe" -ForegroundColor Green
Write-Host "Next: run 40-sign-htp.ps1 (the NPU refuses unsigned libraries)."
