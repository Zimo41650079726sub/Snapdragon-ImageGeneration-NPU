# Read-only environment check. Safe to run at any time; changes nothing.
. "$PSScriptRoot\common.ps1"
$ErrorActionPreference = 'Continue'

function Show([string]$label, $ok, [string]$detail) {
    $mark = if ($ok) { '[OK]  ' } else { '[--]  ' }
    $color = if ($ok) { 'Green' } else { 'Yellow' }
    Write-Host ("{0}{1,-28} {2}" -f $mark, $label, $detail) -ForegroundColor $color
}

$arch = $env:PROCESSOR_ARCHITECTURE
Show 'Windows on ARM64' ($arch -eq 'ARM64') $arch

$npu = Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object { $_.FriendlyName -match 'Hexagon.*NPU' }
$npuVer = if ($npu) { ($npu | Get-PnpDeviceProperty DEVPKEY_Device_DriverVersion -ErrorAction SilentlyContinue).Data } else { '' }
Show 'Hexagon NPU device' ([bool]$npu -and $npu.Status -eq 'OK') "$($npu.FriendlyName) $npuVer"

$opts = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control').SystemStartOptions
Show 'Test signing enabled' ($opts -match 'TESTSIGNING') 'bcdedit /set testsigning on (needs Secure Boot off)'

$sb = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' -ErrorAction SilentlyContinue).UEFISecureBootEnabled
Show 'Secure Boot off' ($sb -eq 0) "UEFISecureBootEnabled=$sb"

$bl = (New-Object -ComObject Shell.Application).NameSpace('C:').Self.ExtendedProperty('System.Volume.BitLockerProtection')
$blText = switch ($bl) { 1 { 'on' } 2 { 'off' } 5 { 'SUSPENDED' } default { "state $bl" } }
Show 'BitLocker (C:)' $true "$blText  (suspend before touching Secure Boot, resume afterwards)"

$cert = Get-ChildItem Cert:\LocalMachine\Root, Cert:\LocalMachine\TrustedPublisher -ErrorAction SilentlyContinue |
    Where-Object Subject -eq 'CN=GGML.HTP.v1'
Show 'Signing cert trusted' (@($cert).Count -ge 2) 'CN=GGML.HTP.v1 in Root + TrustedPublisher'

$vc = Find-VsArm64;          Show 'Visual Studio (ARM64 C++)' ([bool]$vc) "$vc"
$llvm = Find-LlvmBin;        Show 'LLVM clang' ([bool]$llvm) "$llvm"
foreach ($t in 'cmake', 'ninja', 'git', 'python') {
    $c = Get-Command $t -ErrorAction SilentlyContinue; Show $t ([bool]$c) "$($c.Source)"
}
$sdk = Get-HexagonSdkRoot;   Show 'Hexagon SDK' ([bool]$sdk) "$sdk"
$i2c = Find-KitTool 'Inf2Cat.exe' @('x86'); Show 'WDK inf2cat' ([bool]$i2c) "$i2c"
$st = Find-KitTool 'signtool.exe';          Show 'signtool' ([bool]$st) "$st"
$mk = Find-KitTool 'makecert.exe';          Show 'makecert' ([bool]$mk) "$mk"

Write-Host "`nWork dir: $Work"
