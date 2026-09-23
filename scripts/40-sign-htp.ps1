# Generates libggml-htp.cat for the staged HTP libraries and signs it with your certificate.
# Re-run after every rebuild: the catalog covers the exact bytes of each .so.
param([string]$Pfx = (Join-Path $HOME 'Certs\ggml-htp-v1.pfx'))
. "$PSScriptRoot\common.ps1"

if (-not (Test-Path $Pfx)) { throw "Certificate $Pfx not found. Run 10-make-cert.ps1 first." }
if (-not (Test-Path (Join-Path $HtpDir 'libggml-htp.inf'))) { throw 'Nothing staged. Run 30-build.ps1 first.' }

$inf2cat  = Find-KitTool 'Inf2Cat.exe' @('x86')
$signtool = Find-KitTool 'signtool.exe'
if (-not $inf2cat)  { throw 'inf2cat not found. Install the WDK: winget install --id Microsoft.WindowsWDK.10.0.26100 -e' }
if (-not $signtool) { throw 'signtool not found (Windows SDK).' }

Write-Step 'Generating catalog'
Remove-Item (Join-Path $HtpDir 'libggml-htp.cat') -ErrorAction SilentlyContinue
& $inf2cat "/driver:$HtpDir" '/os:10_25H2_ARM64' | Select-Object -Last 3
if (-not (Test-Path (Join-Path $HtpDir 'libggml-htp.cat'))) { throw 'inf2cat did not produce libggml-htp.cat' }

Write-Step 'Signing'
$sec = Read-Host 'PFX password' -AsSecureString
$pw  = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
& $signtool sign /fd sha256 /f $Pfx /p $pw (Join-Path $HtpDir 'libggml-htp.cat')
if ($LASTEXITCODE -ne 0) { throw 'signtool sign failed' }
& $signtool verify /pa (Join-Path $HtpDir 'libggml-htp.cat')
if ($LASTEXITCODE -ne 0) { throw 'Signature does not verify. Is the certificate in Root + TrustedPublisher?' }

Write-Host "`nSigned. Next: 50-generate.ps1" -ForegroundColor Green
