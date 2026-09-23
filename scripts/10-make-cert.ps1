# Only for SNPU_MODE=self-signed (README appendix). Not needed for the default 'signed' mode.
# Creates a self-signed code-signing certificate and trusts it machine-wide.
# Run in an ELEVATED PowerShell, after test signing is enabled.
# makecert shows two password dialogs: set a password, then enter it again.
. "$PSScriptRoot\common.ps1"

$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script from an elevated (Administrator) PowerShell.'
}

$certDir = Join-Path $HOME 'Certs'
New-Item -ItemType Directory -Force $certDir | Out-Null
$pvk = Join-Path $certDir 'ggml-htp-v1.pvk'
$cer = Join-Path $certDir 'ggml-htp-v1.cer'
$pfx = Join-Path $certDir 'ggml-htp-v1.pfx'
if (Test-Path $pfx) { throw "$pfx already exists. Remove it first if you really want a new certificate." }

$makecert = Find-KitTool 'makecert.exe'
$pvk2pfx  = Find-KitTool 'pvk2pfx.exe'
if (-not $makecert -or -not $pvk2pfx) { throw 'makecert/pvk2pfx not found. Install the Windows SDK (comes with Visual Studio).' }

Write-Step 'Creating certificate (two password dialogs will appear)'
& $makecert -r -pe -ss PrivateCertStore -n CN=GGML.HTP.v1 -eku 1.3.6.1.5.5.7.3.3 -sv $pvk $cer
if (-not (Test-Path $cer)) { throw 'makecert did not produce the .cer file.' }

$sec = Read-Host 'Enter the same password again (used for the .pfx)' -AsSecureString
$pw  = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
& $pvk2pfx -pvk $pvk -spc $cer -pfx $pfx -pi $pw -po $pw
if (-not (Test-Path $pfx)) { throw 'pvk2pfx failed (wrong password?).' }

Write-Step 'Trusting the certificate (Root + TrustedPublisher)'
certutil -addstore Root $cer | Out-Null
certutil -addstore TrustedPublisher $cer | Out-Null

Write-Host "`nDone. Keep $pfx safe: anyone holding it can sign code this PC trusts." -ForegroundColor Green
Write-Host 'Consider moving the .pvk off this PC once the build is signed.'
