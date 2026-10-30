<#
.SYNOPSIS
  Asks the controller-managed TLGDev server to save and quit cleanly.
#>
param([string]$DevCache = "", [int]$TimeoutSeconds = 120)
if (-not $DevCache) { $DevCache = Join-Path $env:LOCALAPPDATA "TheLastGallon\devcache" }
Set-Content -Path (Join-Path $DevCache "server-control.txt") -Value "quit" -Encoding ascii
$deadline = (Get-Date).AddSeconds($TimeoutSeconds)
while ((Get-Date) -lt $deadline) {
    $j = Get-CimInstance Win32_Process -Filter "Name='java.exe'" | Where-Object { $_.CommandLine -match 'servername TLGDev' }
    if (-not $j) { Write-Host "TLGDev stopped"; exit 0 }
    Start-Sleep -Seconds 2
}
Write-Host "TLGDev did not stop within $TimeoutSeconds s"
exit 1
