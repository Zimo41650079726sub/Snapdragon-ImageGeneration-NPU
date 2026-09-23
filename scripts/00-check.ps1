# Read-only environment check. Safe to run at any time; changes nothing.
. "$PSScriptRoot\common.ps1"
$ErrorActionPreference = 'Continue'

function Show([string]$label, $ok, [string]$detail) {
    $mark = if ($ok) { '[OK]  ' } else { '[--]  ' }
    $color = if ($ok) { 'Green' } else { 'Yellow' }
    Write-Host ("{0}{1,-28} {2}" -f $mark, $label, $detail) -ForegroundColor $color
}
function Info([string]$label, [string]$detail) { Write-Host ("[..]  {0,-28} {1}" -f $label, $detail) }

Write-Host "Mode: $Mode   (set `$env:SNPU_MODE='self-signed' for the test-signing route)`n"

$arch = $env:PROCESSOR_ARCHITECTURE
Show 'Windows on ARM64' ($arch -eq 'ARM64') $arch

$npu = Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match 'Hexagon.*NPU' }
$npuVer = if ($npu) { ($npu | Get-PnpDeviceProperty DEVPKEY_Device_DriverVersion -ErrorAction SilentlyContinue).Data } else { '' }
Show 'Hexagon NPU device' ([bool]$npu -and $npu.Status -eq 'OK') "$($npu.FriendlyName) $npuVer"

$opts = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control').SystemStartOptions
$ts = $opts -match 'TESTSIGNING'
$sb = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' -ErrorAction SilentlyContinue).UEFISecureBootEnabled
$bl = (New-Object -ComObject Shell.Application).NameSpace('C:').Self.ExtendedProperty('System.Volume.BitLockerProtection')
$blText = switch ($bl) { 1 { 'on' } 2 { 'off' } 5 { 'SUSPENDED' } default { "state $bl" } }

if ($Mode -eq 'signed') {
    Info 'Test signing' ($(if ($ts) { 'on (not needed in signed mode; you can turn it off)' } else { 'off (good)' }))
    Info 'Secure Boot' ($(if ($sb -eq 1) { 'on (good)' } else { "off (not needed in signed mode)" }))
    Info 'BitLocker (C:)' $blText
    $cat = Join-Path $HtpDir 'libggml-htp.cat'
    if (Test-Path $cat) {
        $sig = Get-AuthenticodeSignature $cat
        Show 'Signed HTP libraries' ($sig.Status -eq 'Valid' -and $sig.SignerCertificate.Subject -match 'Microsoft') "$($sig.Status): $($sig.SignerCertificate.Subject.Split(',')[0])"
    } else {
        Show 'Signed HTP libraries' $false "not downloaded yet (20-get-sources.ps1)"
    }
} else {
    Show 'Test signing enabled' $ts 'bcdedit /set testsigning on (needs Secure Boot off)'
    Show 'Secure Boot off' ($sb -eq 0) "UEFISecureBootEnabled=$sb"
    Info 'BitLocker (C:)' "$blText  (suspend before touching Secure Boot, resume afterwards)"
    $cert = Get-ChildItem Cert:\LocalMachine\Root, Cert:\LocalMachine\TrustedPublisher -ErrorAction SilentlyContinue |
        Where-Object Subject -eq 'CN=GGML.HTP.v1'
    Show 'Signing cert trusted' (@($cert).Count -ge 2) 'CN=GGML.HTP.v1 in Root + TrustedPublisher'
    $i2c = Find-KitTool 'Inf2Cat.exe' @('x86'); Show 'WDK inf2cat' ([bool]$i2c) "$i2c"
    $st = Find-KitTool 'signtool.exe';          Show 'signtool' ([bool]$st) "$st"
}

$vc = Find-VsArm64;          Show 'Visual Studio (ARM64 C++)' ([bool]$vc) "$vc"
$llvm = Find-LlvmBin;        Show 'LLVM clang' ([bool]$llvm) "$llvm"
foreach ($t in 'cmake', 'ninja', 'git', 'python') {
    $c = Get-Command $t -ErrorAction SilentlyContinue; Show $t ([bool]$c) "$($c.Source)"
}
$sdk = Get-HexagonSdkRoot;   Show 'Hexagon SDK' ([bool]$sdk) "$sdk"
Show 'sd-cli built' (Test-Path (Join-Path $BuildDir 'bin\sd-cli.exe')) (Join-Path $BuildDir 'bin')

Write-Host "`nWork dir: $Work"
