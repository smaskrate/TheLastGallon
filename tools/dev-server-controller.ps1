<#
.SYNOPSIS
  Runs the TLGDev dedicated server with a controllable console (long-running).
.DESCRIPTION
  Starts the server through cmd.exe so stdout/stderr go to files while this
  script keeps the console input pipe. Any line written to
  <devcache>/server-control.txt is forwarded to the server console (for
  example "save" or "quit"); the file is then cleared. The script exits when
  the server exits. Intended to be started in the background.
.PARAMETER GameDir
  Project Zomboid install directory (default: two levels above the repository).
.PARAMETER DevCache
  Cache directory (default %LOCALAPPDATA%\TheLastGallon\devcache).
.PARAMETER Fresh
  Delete the TLGDev world save (never anything else) before starting.
#>
param([string]$GameDir = "", [string]$DevCache = "", [switch]$Fresh)
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
if (-not $GameDir) { $GameDir = $env:PZ_GAME_DIR }
if (-not $GameDir) { $GameDir = (Resolve-Path (Join-Path $repo "..\..")).Path }
if (-not $DevCache) { $DevCache = Join-Path $env:LOCALAPPDATA "TheLastGallon\devcache" }
& (Join-Path $PSScriptRoot "setup-devenv.ps1") -DevCache $DevCache | Out-Null
if ($Fresh) {
    $save = Join-Path $DevCache "Saves\Multiplayer\TLGDev"
    if (Test-Path $save) { Remove-Item -Recurse -Force $save }
}
$values = @{}
Get-Content (Join-Path $DevCache "dev-credentials.txt") | ForEach-Object { $k, $v = $_ -split "=", 2; $values[$k] = $v }

$java = Join-Path $GameDir "jre64\bin\java.exe"
$jvm = "--enable-native-access=ALL-UNNAMED --add-exports=java.base/jdk.internal.misc=ALL-UNNAMED " +
    "-XX:+UseZGC -XX:-CreateCoredumpOnCrash -XX:-OmitStackTraceInFastThrow -Xmx3072m " +
    "-Djava.library.path=./natives/;./natives/win64/;./ -cp ./;projectzomboid.jar zombie.network.GameServer " +
    "-nosteam ""-cachedir=$DevCache"" -servername TLGDev -adminusername admin -adminpassword $($values.admin) " +
    "-ip 127.0.0.1 -port 16361 -udpport 16362"
$out = Join-Path $DevCache "server-stdout.txt"
$err = Join-Path $DevCache "server-stderr.txt"
$control = Join-Path $DevCache "server-control.txt"
Set-Content -Path $control -Value "" -Encoding ascii

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "cmd.exe"
$psi.Arguments = "/c """"$java"" $jvm > ""$out"" 2> ""$err"""""
$psi.WorkingDirectory = $GameDir
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$psi.CreateNoWindow = $true
$proc = [System.Diagnostics.Process]::Start($psi)
$proc.Id | Set-Content (Join-Path $DevCache "server-controller.pid")
# .NET writes a UTF-8 preamble (BOM) into the pipe when it creates
# Process.StandardInput, so the server would read the first command as
# "<BOM>quit" ("Unknown command"). Absorb the BOM with an empty first line and
# send everything else through an ASCII writer.
$stdin = New-Object System.IO.StreamWriter($proc.StandardInput.BaseStream, (New-Object System.Text.ASCIIEncoding))
$stdin.AutoFlush = $true
$stdin.WriteLine("")
Write-Host "controller started server shell pid $($proc.Id)"
while (-not $proc.HasExited) {
    Start-Sleep -Seconds 2
    $lines = @(Get-Content $control -ErrorAction SilentlyContinue | Where-Object { $_.Trim() })
    if ($lines.Count -gt 0) {
        Set-Content -Path $control -Value "" -Encoding ascii
        foreach ($l in $lines) {
            Write-Host "-> $l"
            $stdin.WriteLine($l.Trim())
        }
    }
}
Write-Host "server exited with code $($proc.ExitCode)"
