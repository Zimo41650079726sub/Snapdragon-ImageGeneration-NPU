# Generates an image with the diffusion model (DiT) on the Hexagon NPU; text encoder and VAE stay on the CPU.
#
#   .\50-generate.ps1 -Model klein -ModelDir D:\models -Prompt "a lovely cat"
#
# -Model picks the file names and sampler defaults below; override any of them with the other parameters.
param(
    [ValidateSet('klein', 'zimage', 'krea2', 'qwen21')] [string]$Model = 'klein',
    [string]$ModelDir = (Join-Path $HOME 'sd-models'),
    [string]$Prompt = 'a lovely cat',
    [int]$Width = 512, [int]$Height = 512,
    [int]$Steps = 0, [long]$Seed = 42,
    [string]$Out = (Join-Path (Get-Location) 'output.png'),
    [string]$Diffusion, [string]$Llm, [string]$Vae,
    [switch]$Cpu,           # run everything on the CPU (baseline / comparison)
    [int]$Threads = 0
)
. "$PSScriptRoot\common.ps1"

# File names as distributed on Hugging Face; point -ModelDir at the folder holding them.
$presets = @{
    klein  = @{ d = 'flux-2-klein-4b-Q4_0.gguf';     l = 'Qwen3-4B-Instruct-2507-Q4_K_M.gguf';                         v = 'flux2-vae.safetensors';               steps = 4;  g = @('--cfg-scale', '1') }
    zimage = @{ d = 'z-image-turbo-Q4_0.gguf';        l = 'Qwen3-4B-Instruct-2507-Q4_K_M.gguf';                         v = 'ae.safetensors';                      steps = 8;  g = @('--cfg-scale', '1', '--guidance', '3.5') }
    krea2  = @{ d = 'Krea2-Turbo-HD-V1-Q4_0.gguf';    l = 'Qwen3-VL-4B-Instruct-Uncensored-abliterated.Q4_0.gguf';      v = 'wan_2.1_vae.safetensors';             steps = 8;  g = @('--cfg-scale', '1', '--guidance', '1.0') }
    qwen21 = @{ d = 'qwen_image_2.1-Q4_0.gguf';       l = 'Qwen3VL-8B-Instruct-Q4_K_M.gguf';                            v = 'qwen_image_2.1_vae_bf16.safetensors'; steps = 20; g = @('--cfg-scale', '6.0') }
}
$p = $presets[$Model]
if (-not $Diffusion) { $Diffusion = Join-Path $ModelDir $p.d }
if (-not $Llm)       { $Llm = Join-Path $ModelDir $p.l }
if (-not $Vae)       { $Vae = Join-Path $ModelDir $p.v }
if ($Steps -le 0)    { $Steps = $p.steps }
if ($Threads -le 0)  { $Threads = [Environment]::ProcessorCount }
foreach ($f in $Diffusion, $Llm, $Vae) { if (-not (Test-Path $f)) { throw "Model file not found: $f" } }

$exe = Join-Path $BuildDir 'bin\sd-cli.exe'
if (-not (Test-Path $exe)) { throw 'sd-cli.exe not found. Run 30-build.ps1 first.' }
# Do not put $HtpDir on PATH: the GenieX folder also holds its own ggml DLLs.
$env:PATH = "$BuildDir\bin;$env:PATH"

if ($Cpu) {
    $placement = @('--backend', 'cpu')
} else {
    if (-not (Test-Path (Join-Path $HtpDir 'libggml-htp.cat'))) {
        if ($Mode -eq 'signed') { throw "Signed HTP libraries missing in $HtpDir. Run 20-get-sources.ps1." }
        throw 'HTP libraries are not signed. Run 40-sign-htp.ps1.'
    }
    # The NPU session loads libggml-htp-v*.so (and checks the signed .cat) from this folder.
    $env:ADSP_LIBRARY_PATH = $HtpDir
    # CONCAT/CONT run at ~0.1-0.3 GB/s on the HTP today; the CPU does them far faster.
    $env:GGML_HEXAGON_OPFILTER = 'CONCAT|CONT'
    # The HTP reports 0 MiB free, so auto-fit would keep the weights on the CPU; place them explicitly.
    $placement = @('--backend', 'diffusion=HTP0,te=cpu,vae=cpu',
                   '--params-backend', 'diffusion=HTP0,te=cpu,vae=cpu', '--auto-fit', 'off')
}

& $exe --diffusion-model $Diffusion --llm $Llm --vae $Vae @placement --diffusion-fa -t $Threads `
    -p $Prompt @($p.g) --steps $Steps --sampling-method euler -W $Width -H $Height --seed $Seed -o $Out
if ($LASTEXITCODE -ne 0) { throw "sd-cli failed (exit $LASTEXITCODE)" }
Write-Host "`nSaved $Out" -ForegroundColor Green
