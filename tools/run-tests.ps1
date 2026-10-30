<#
.SYNOPSIS
  Runs the domain test suite on the Kahlua VM shipped with the game.
.DESCRIPTION
  Compiles tools/kahlua-runner (JDK 17, reflection only) when needed and runs
  tests/run_all.lua with the game's own Java runtime and projectzomboid.jar.
  The working directory is switched to the game install directory because
  Kahlua's J2SEPlatform loads ./stdlib.lua from there, as the game does.
.PARAMETER Filter
  Optional substring of test case names to run.
.PARAMETER Seed
  Seed for randomized/state-machine tests (default 20261030).
.PARAMETER GameDir
  Project Zomboid install directory. Defaults to $env:PZ_GAME_DIR, then to the
  directory two levels above this repository.
.PARAMETER Entry
  Alternative entry script (relative to the repository), e.g. tests/support/runtime_probe.lua.
#>
param(
    [string]$Filter = "",
    [int]$Seed = 20261030,
    [string]$GameDir = "",
    [string]$Entry = "tests/run_all.lua"
)
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
if (-not $GameDir) { $GameDir = $env:PZ_GAME_DIR }
if (-not $GameDir) { $GameDir = (Resolve-Path (Join-Path $repo "..\..")).Path }
$jar = Join-Path $GameDir "projectzomboid.jar"
$java = Join-Path $GameDir "jre64\bin\java.exe"
if (-not (Test-Path $jar)) { throw "projectzomboid.jar not found in $GameDir" }

$src = Join-Path $PSScriptRoot "kahlua-runner\KahluaRunner.java"
$build = Join-Path $PSScriptRoot "kahlua-runner\build"
$cls = Join-Path $build "KahluaRunner.class"
if (-not (Test-Path $cls) -or (Get-Item $src).LastWriteTime -gt (Get-Item $cls).LastWriteTime) {
    New-Item -ItemType Directory -Force $build | Out-Null
    & javac --release 17 -d $build $src
    if ($LASTEXITCODE -ne 0) { throw "javac failed" }
}

$lua = Join-Path $repo "Contents\mods\TheLastGallon\common\media\lua"
$roots = @(
    "--root", (Join-Path $lua "shared"),
    "--root", (Join-Path $lua "server"),
    "--root", (Join-Path $lua "client"),
    "--root", (Join-Path $repo "tests")
)
if ($Entry -like "*compile_check*") {
    # Also syntax-check the dev harness mod.
    $h = Join-Path $repo "tests\ingame\TheLastGallonHarness\common\media\lua"
    $roots += @("--root", (Join-Path $h "shared"), "--root", (Join-Path $h "server"), "--root", (Join-Path $h "client"))
}
# PowerShell drops empty-string arguments to native programs and the Windows
# java launcher glob-expands "*", so "all" is the no-filter placeholder.
if (-not $Filter) { $Filter = "all" }
Push-Location $GameDir
try {
    & $java -cp "$build;$jar" KahluaRunner @roots (Join-Path $repo $Entry) $Filter "$Seed"
    $code = $LASTEXITCODE
} finally {
    Pop-Location
}
exit $code
