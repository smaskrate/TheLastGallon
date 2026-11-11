<#
.SYNOPSIS
  Runs the multiplayer harness: the TLGDev dedicated server and one or two
  clients on this machine, unattended.
.DESCRIPTION
  Each process has its own isolated cache under %LOCALAPPDATA%\TheLastGallon
  (mpserver, mpclient1, mpclient2), deployed by setup-devenv.ps1. The
  server's world is made fresh each run (only its TLGDev save is deleted),
  with one spawn point (the single-player harness's open ground at
  10660,10645, so no spawn town is asked for) and no zombies. Once the
  server is up, the console creates the test accounts tlga and tlgb with
  admin access (adduser, setaccesslevel; the user role with -NonAdmin),
  their passwords random and kept in mpserver\dev-credentials.txt, never
  printed.

  Each client gets its role (TLG_harness_request.txt: mp-a, mp-b) and the
  connection (TLG_harness_connect.txt) in its cache's Lua folder. The
  harness (TLGHarness/MPHarness.lua) joins by IP as vanilla's Join by IP
  popup does, passes character creation with the screens' own Next
  handlers, runs its steps and quits. As the single-player launcher does,
  this script posts the click a finished world load waits for to each
  client's window. The clients run without -debug, as players do.

  Results: each client's <cache>\Lua\TLG_harness_mp.txt and the server's
  mpserver\Lua\TLG_harness_mpserver.txt. The server's own stdout holds the
  account passwords (adduser echoes them), so it is never printed or
  archived; only its lines naming the accounts are shown, the passwords
  masked.
.PARAMETER Clients
  1 (client A only) or 2 (A and B).
.PARAMETER TimeoutMinutes
  Watchdog limit for the whole run.
.PARAMETER ModSource
  Folder deployed as the mod (default: the repository's).
.PARAMETER Only
  carry: only the vessel's pickup, the gaits, its put-down and the two
  players taking it at once (two clients); heavy: only vanilla's meteorite
  taken off the floor (one client); machines: a running vessel moved by the
  world menu's Grab, and two players loading one fermenter at once (two
  clients), with a vessel taken out of a crate; fuel: pours, refuelling and
  siphoning at the Gas2Go pumps, a generator and a car (one client);
  conversion: a generator converted at the workshop; carconv: a car
  converted; stills: both stills and the drying column (one client each,
  on the shortest day). effects: what poor fuel does to an engine (D-031)
  with the server applying it: a car idling on stale petrol loses power and
  wears, the start gate and the stall option on a blend it cannot take, and
  a generator's wear charged at a refuel (two clients: A drives, B
  watches). timers: the machines' hourly readings and ten-minute notes on
  the server (D-032), beside a campfire the server builds and lights, and
  what each timer costs there (one client). Both on the shortest day.
  knowledge: What I know about it, read from the Fuel menu on a client after
  a kit sample and a look answered by the server, then after the can is
  opened (one client). With -Restart the can stays sealed: after both
  tests the player leaves, the server is saved, stopped and started again,
  and the player joins again and reads it once more. death: A carries a
  running vessel and dies; B asks the server where the vessel is and what
  its record says, then reads it a while later (two clients, on the
  shortest day). wrongfuel: wrong fuel damages engines (D-037) with the
  server applying it: a petrol car, an ambulance, a petrol generator and a
  Diesel Generator; refused starts and what they cost, starts on fuel that
  harms as the server's draws give, power, wear and exhaust by the litre,
  a failure, the mod's pour refused until confirmed, and the sandbox
  option off, each seen on the server and on the client (one client).
  handbook3: the crafting window for the Wood Retort, the Wash Tank and
  the Reactor with the handbook read: refused below the level, made at it.
  handbook3u: the three refused at Welding 5 with nothing read (one
  client each). menus: the mod's world menu entries where the click is on
  their thing, for a can, a machine, a generator and a car the server put
  down, at zoom 1, 0.5 and 1.5 (one client).
.PARAMETER NoMod
  Server and clients without The Last Gallon, the harness alone: a control
  for what vanilla does (with -Only heavy).
.PARAMETER NonAdmin
  Both test accounts are plain players (setaccesslevel user). The server's
  lines naming a kick or the anti-cheat are printed after the run either way.
.PARAMETER Restart
  With the full run: instead of A leaving and joining again, both clients
  leave to the main menu, the server is saved, stopped and started again
  on the same world, and both join again (each client waits for
  Lua\TLG_harness_mpgo.txt, written once the server is up again).
.PARAMETER ModAway
  With -Only gensprite (one client): the server is saved and stopped
  twice. Its second session runs without The Last Gallon (the server's
  Mods line names the harness alone), its third with the mod again. The
  client leaves before each stop and joins each session. The harness's
  mod.info loses its "require" line in the deployed copies for the whole
  run, so the session without the mod does not load it. Each session's
  server log is kept as server-stdout-<n>.txt.
.PARAMETER DropVault
  With -Restart: before the restart the server store is saved without the
  vault of TLG/Authority/Vault.lua, as the mod saved it before the V-01
  fix (security audit 2026-11-05), so the restarted server starts a vault
  on a world that has records and adopts them.
#>
param([string]$GameDir = "", [ValidateRange(1, 2)][int]$Clients = 1, [int]$TimeoutMinutes = 30, [string]$ModSource = "",
    [ValidateSet("", "carry", "heavy", "machines", "fuel", "conversion", "carconv", "stills", "effects", "timers", "audit", "knowledge", "death", "biodiesel", "gensprite", "handbook", "handbook3", "handbook3u", "wrongfuel", "menus")][string]$Only = "",
    [switch]$NoMod,
    [switch]$NonAdmin, [switch]$Restart, [switch]$DropVault, [switch]$ModAway)
$ErrorActionPreference = "Stop"
if (Get-Process -Name LogonUI -ErrorAction SilentlyContinue) {
    Write-Host "The Windows session is locked; unlock the desktop and run again."
    exit 2
}
$repo = Split-Path -Parent $PSScriptRoot
if (-not $GameDir) { $GameDir = $env:PZ_GAME_DIR }
if (-not $GameDir) { $GameDir = (Resolve-Path (Join-Path $repo "..\..")).Path }
$base = Join-Path $env:LOCALAPPDATA "TheLastGallon"
$serverCache = Join-Path $base "mpserver"
$roles = @("mp-a", "mp-b")[0..($Clients - 1)]
$users = @("tlga", "tlgb")
$clientCaches = @(1..$Clients | ForEach-Object { Join-Path $base "mpclient$_" })
$active = if ($NoMod) { @("TheLastGallonHarness") } else { @("TheLastGallon", "TheLastGallonHarness") }

& (Join-Path $PSScriptRoot "setup-devenv.ps1") -DevCache $serverCache -ModSource $ModSource -ActiveMods $active | Out-Null
foreach ($c in $clientCaches) {
    & (Join-Path $PSScriptRoot "setup-devenv.ps1") -DevCache $c -ModSource $ModSource -ActiveMods $active | Out-Null
}

# Each cache by its final path. A server sums the mods' pose files by their
# path relative to the mod folder's canonical path (BC
# AdvancedAnimator.loadModMedia, ZomboidFileSystem.getRelativeFile), but walks
# them under the path it was given. When the two differ (a link, or Windows
# redirecting %LOCALAPPDATA% for a packaged app's processes, which the game's
# Java resolves) no pose file is found relative and the server stops before
# loading any Lua (run 136: "couldn't find ...tlgcarryvessel.xml").
Add-Type @"
using System; using System.Runtime.InteropServices; using System.Text; using Microsoft.Win32.SafeHandles;
public static class TlgFinalPath {
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr sec, uint disp, uint flags, IntPtr tmpl);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern uint GetFinalPathNameByHandleW(SafeFileHandle h, StringBuilder buf, uint len, uint flags);
    public static string Of(string path) {
        using (SafeFileHandle h = CreateFileW(path, 0, 7, IntPtr.Zero, 3, 0x02000000, IntPtr.Zero)) {
            if (h.IsInvalid) return path;
            StringBuilder sb = new StringBuilder(1024);
            uint n = GetFinalPathNameByHandleW(h, sb, 1024, 0);
            if (n == 0 || n >= 1024) return path;
            string s = sb.ToString();
            if (s.StartsWith(@"\\?\UNC\")) return @"\\" + s.Substring(8);
            return s.StartsWith(@"\\?\") ? s.Substring(4) : s;
        }
    }
}
"@
$serverCache = [TlgFinalPath]::Of($serverCache)
$clientCaches = @($clientCaches | ForEach-Object { [TlgFinalPath]::Of($_) })
Write-Host "caches: $serverCache; $($clientCaches -join '; ')"
# Without the mod the harness must not require it (its mod.info does, and
# run 143's server loaded the mod for it). Only the deployed copies change;
# the next deploy mirrors the repository's back.
if ($NoMod -or $ModAway) {
    foreach ($c in @($serverCache) + $clientCaches) {
        $info = Join-Path $c "mods\TheLastGallonHarness\42\mod.info"
        (Get-Content $info) | Where-Object { $_ -notmatch "^require=" } | Set-Content -Encoding ascii $info
    }
}

# Accounts: kept beside the server's own credentials (setup-devenv.ps1).
$credFile = Join-Path $serverCache "dev-credentials.txt"
$cred = [ordered]@{}
Get-Content $credFile | ForEach-Object { $k, $v = $_ -split "=", 2; if ($k) { $cred[$k] = $v } }
$chars = (48..57) + (65..90) + (97..122)
foreach ($u in $users) {
    if (-not $cred.Contains($u)) { $cred[$u] = -join ($chars | Get-Random -Count 20 | ForEach-Object { [char]$_ }) }
}
($cred.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) | Set-Content -Encoding ascii $credFile

# A fresh world each run: only the server's TLGDev save goes.
$save = Join-Path $serverCache "Saves\Multiplayer\TLGDev"
if (Test-Path $save) { Remove-Item -Recurse -Force $save }
$serverDir = Join-Path $serverCache "Server"
# The server's mods, set each run (the server rewrites the rest of its ini).
$ini = Join-Path $serverDir "TLGDev.ini"
(Get-Content $ini) -replace "^Mods=.*$", "Mods=$($active -join ';')" | Set-Content -Encoding ascii $ini
@"
function SpawnRegions()
	return {
		{ name = "TLG harness", serverfile = "TLGDev_spawnpoints.lua" },
	}
end
"@ | Set-Content -Encoding ascii (Join-Path $serverDir "TLGDev_spawnregions.lua")
@"
function SpawnPoints()
	return {
		unemployed = {
			{ posX = 10660, posY = 10645, posZ = 0 },
		},
	}
end
"@ | Set-Content -Encoding ascii (Join-Path $serverDir "TLGDev_spawnpoints.lua")
# No zombies: Zombies 6 is "None" (Sandbox_ZombieCount_option6); the server
# reads each option it finds and keeps the rest at their defaults
# (SandboxOptions.loadServerLuaFile, BC). The server harness logs the
# values it got. The conversion's 7.5 work hours fit the run on the
# shortest day (DayLength 1: 15 minutes, Sandbox_DayLength_option1), and
# the fuel case's generator and car burn enough there to be seen (run 156
# read none in half a minute on the default day).
$dayLength = if (@("conversion", "fuel", "carconv", "stills", "effects", "timers", "death") -contains $Only) { "`n    DayLength = 1," } else { "" }
# The audit case (AuditCases.lua) runs with the grid on: without power
# IsoObject.getPipedFuelAmount reports no fuel at all (BC 42.21; audit run 1
# found "no pump with stock" with ElecShutModifier = 0), so the pumps' case
# needs a powered station.
@"
SandboxVars = {
    VERSION = 6,$dayLength
    Zombies = 6,
    ZombieConfig = {
        PopulationMultiplier = 0.0,
        PopulationStartMultiplier = 0.0,
        PopulationPeakMultiplier = 0.0,
    },
}
"@ | Set-Content -Encoding ascii (Join-Path $serverDir "TLGDev_SandboxVars.lua")

# First-run prompts, as tools/run-sp-harness.ps1 answers them (the user's
# own answered values read only).
$userOptions = Join-Path $env:USERPROFILE "Zomboid\options.ini"
$keys = @("termsOfServiceVersion", "doneNewSaveFolder", "showFirstTimeSearchTutorial",
    "showFirstAnimalZoneInfo", "shownWelcomeMessageVersion")
$opts = [ordered]@{ version = "1"; fullScreen = "false"; screenWidth = "1280"; screenHeight = "720"; language = "EN";
    showFirstTimeSneakTutorial = "false"; showWelcomeMessage2 = "false"; tutorialDone = "true";
    showSurvivalGuide = "false" }
if (Test-Path $userOptions) {
    foreach ($line in Get-Content $userOptions) {
        $k, $v = $line -split "=", 2
        if ($keys -contains $k) { $opts[$k] = $v }
    }
}
# A file an earlier launch left: removed, or emptied where it cannot be
# (launch 246: the removal did nothing, the client's old results still said
# DONE and the client was stopped 30 s in; launch 229 the same in single
# player).
function Clear-Stale([string]$path) {
    Remove-Item $path -ErrorAction SilentlyContinue
    if (Test-Path $path) {
        Clear-Content $path -ErrorAction SilentlyContinue
        Write-Host "WARNING: $(Split-Path -Leaf $path) from an earlier launch could not be removed; emptied"
    }
}
for ($i = 0; $i -lt $Clients; $i++) {
    $c = $clientCaches[$i]
    ($opts.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) | Set-Content -Encoding ascii (Join-Path $c "options.ini")
    $lua = Join-Path $c "Lua"
    New-Item -ItemType Directory -Force $lua | Out-Null
    foreach ($f in "TLG_harness_mp.txt", "TLG_harness_mpstate.txt", "TLG_harness_mpgo.txt", "TLG_harness_mpsnap.txt") {
        Clear-Stale (Join-Path $lua $f)
    }
    Set-Content -Encoding ascii (Join-Path $lua "TLG_harness_request.txt") -Value $roles[$i]
    @("ip=127.0.0.1", "port=16361", "user=$($users[$i])", "password=$($cred[$users[$i]])",
        "serverPassword=$($cred.serverPassword)", "only=$Only", "restart=$(if ($Restart -or $ModAway) { '1' } else { '0' })",
        "dropVault=$(if ($DropVault) { '1' } else { '0' })") |
        Set-Content -Encoding ascii (Join-Path $lua "TLG_harness_connect.txt")
}
$serverLua = Join-Path $serverCache "Lua"
New-Item -ItemType Directory -Force $serverLua | Out-Null
Clear-Stale (Join-Path $serverLua "TLG_harness_mpserver.txt")

# A harness server left from an earlier run holds the port and its log
# files (run 136's printed "Server Terminated" and kept running).
function Stop-HarnessServers {
    Get-CimInstance Win32_Process -Filter "Name = 'java.exe'" | Where-Object {
        $_.CommandLine -match "zombie\.network\.GameServer" -and $_.CommandLine -match "TheLastGallon\\mpserver" } |
        ForEach-Object { Write-Host "stopping harness server $($_.ProcessId)"; Stop-Process -Id $_.ProcessId -Force }
}
Stop-HarnessServers

function Read-Shared([string]$path) {
    if (-not (Test-Path $path)) { return "" }
    $fs = [System.IO.File]::Open($path, "Open", "Read", "ReadWrite, Delete")
    try { return (New-Object System.IO.StreamReader($fs)).ReadToEnd() } finally { $fs.Dispose() }
}
$deadline = (Get-Date).AddMinutes($TimeoutMinutes)
$started = Get-Date

# The server, its console on a pipe (as tools/dev-server-controller.ps1).
$java = Join-Path $GameDir "jre64\bin\java.exe"
$jvm = "--enable-native-access=ALL-UNNAMED --add-exports=java.base/jdk.internal.misc=ALL-UNNAMED " +
    "-XX:+UseZGC -XX:-CreateCoredumpOnCrash -XX:-OmitStackTraceInFastThrow -Xmx3072m " +
    "-Djava.library.path=./natives/;./natives/win64/;./ -cp ./;projectzomboid.jar zombie.network.GameServer " +
    "-nosteam ""-cachedir=$serverCache"" -servername TLGDev -adminusername admin -adminpassword $($cred.admin) " +
    "-ip 127.0.0.1 -port 16361 -udpport 16362"
$serverOut = Join-Path $serverCache "server-stdout.txt"
$serverErr = Join-Path $serverCache "server-stderr.txt"
# The first server's log, kept through a restart for the scan at the end.
$serverOut1 = Join-Path $serverCache "server-stdout-1.txt"
Remove-Item $serverOut1 -ErrorAction SilentlyContinue
foreach ($n in 2, 3) { Remove-Item (Join-Path $serverCache "server-stdout-$n.txt") -ErrorAction SilentlyContinue }
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = "cmd.exe"
$psi.Arguments = "/c """"$java"" $jvm > ""$serverOut"" 2> ""$serverErr"""""
$psi.WorkingDirectory = $GameDir
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$psi.CreateNoWindow = $true

# Starts the server and waits for it to say it is up. The last log still
# says SERVER STARTED (run 139 sent the account commands before the new
# server read its console), so it goes first.
function Start-HarnessServer {
    Remove-Item $serverOut, $serverErr -ErrorAction SilentlyContinue
    $t0 = Get-Date
    $script:server = [System.Diagnostics.Process]::Start($psi)
    # .NET writes a UTF-8 BOM into the pipe first; an empty first line absorbs it.
    $script:console = New-Object System.IO.StreamWriter($script:server.StandardInput.BaseStream,
        (New-Object System.Text.ASCIIEncoding))
    $script:console.AutoFlush = $true
    $script:console.WriteLine("")
    Write-Host "server started (shell pid $($script:server.Id))"
    while ((Get-Date) -lt $deadline -and -not $script:server.HasExited -and
        (Read-Shared $serverOut) -notmatch "\*\*\* SERVER STARTED") {
        Start-Sleep -Seconds 3
    }
    if ($script:server.HasExited -or (Read-Shared $serverOut) -notmatch "\*\*\* SERVER STARTED") {
        Write-Host "server did not start (shell exited: $($script:server.HasExited) $(if ($script:server.HasExited) { $script:server.ExitCode }))"
        (Read-Shared $serverErr) -split "`n" | Where-Object { $_ -match "ERROR|Exception|couldn't" } | Select-Object -Last 6 |
            ForEach-Object { $l = $_.Trim(); foreach ($p in $cred.Values) { if ($p) { $l = $l.Replace($p, "********") } }; Write-Host "server: $l" }
        Stop-HarnessServers
        return $false
    }
    Write-Host "server up after $([int]((Get-Date) - $t0).TotalSeconds) s"
    return $true
}

# Saves the world and quits through the console.
function Stop-HarnessServer {
    $script:console.WriteLine("save")
    Start-Sleep -Seconds 5
    $script:console.WriteLine("quit")
    $grace = (Get-Date).AddSeconds(120)
    while ((Get-Date) -lt $grace -and -not $script:server.HasExited) { Start-Sleep -Seconds 3 }
    if (-not $script:server.HasExited) {
        Write-Host "watchdog: stopping the server"
        Stop-Process -Id $script:server.Id -Force
    }
    Stop-HarnessServers
}

if (-not (Start-HarnessServer)) { exit 4 }
# The accounts outlive the world in the server's database, so the level is
# set each run, by role name (BC Roles: banned, user, priority, observer,
# gm, moderator, admin). Run 152 skipped it and run 153 sent "none", which
# the server refused ("Access Level '' unknown"): both stayed admin.
$level = if ($NonAdmin) { "user" } else { "admin" }
foreach ($u in $users) {
    $console.WriteLine("adduser ""$u"" ""$($cred[$u])""")
    Start-Sleep -Seconds 2
    $console.WriteLine("setaccesslevel ""$u"" ""$level""")
    Start-Sleep -Seconds 2
}
# The lines naming the accounts, passwords masked.
$text = Read-Shared $serverOut
foreach ($u in $users) {
    $text -split "`n" | Where-Object { $_ -match [regex]::Escape($u) } | ForEach-Object {
        $l = $_.Trim()
        foreach ($p in $cred.Values) { if ($p) { $l = $l.Replace($p, "********") } }
        Write-Host "server: $l"
    }
}

# The clients.
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class TlgMpWin {
    [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
    [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
"@
function Send-GameClick([IntPtr]$hwnd) {
    $r = New-Object TlgMpWin+RECT
    [TlgMpWin]::GetClientRect($hwnd, [ref]$r) | Out-Null
    $lp = [IntPtr]((([int](($r.B - $r.T) / 2)) -shl 16) -bor [int](($r.R - $r.L) / 2))
    [TlgMpWin]::PostMessage($hwnd, 0x0201, [IntPtr]1, $lp) | Out-Null  # WM_LBUTTONDOWN
    Start-Sleep -Milliseconds 300
    [TlgMpWin]::PostMessage($hwnd, 0x0202, [IntPtr]0, $lp) | Out-Null  # WM_LBUTTONUP
}
$json = Get-Content (Join-Path $GameDir "ProjectZomboid64.json") -Raw | ConvertFrom-Json
$vm = @($json.vmArgs | Where-Object { $_ -notmatch '^-Dzomboid.steam=' }) + @("-Dzomboid.steam=0", "-XX:+UseZGC")
$procs = @()
for ($i = 0; $i -lt $Clients; $i++) {
    $c = $clientCaches[$i]
    $clientArgs = $vm + @("-cp", ($json.classpath -join ";"), ($json.mainClass -replace "/", "."), "-nosteam", "-nosound", "-cachedir=$c")
    $p = Start-Process -FilePath $java -ArgumentList $clientArgs -WorkingDirectory $GameDir `
        -RedirectStandardOutput (Join-Path $c "client-stdout.txt") -RedirectStandardError (Join-Path $c "client-stderr.txt") -PassThru
    Write-Host "client $($roles[$i]) started, pid $($p.Id)"
    $procs += $p
    # Client B joins once A is in the game, so the two loads do not compete.
    if ($i -lt $Clients - 1) {
        while ((Get-Date) -lt $deadline -and -not $p.HasExited -and
            (Read-Shared (Join-Path $c "Lua\TLG_harness_mp.txt")) -notmatch "(?m)^STEP ") {
            Start-Sleep -Seconds 5
            $log = Read-Shared (Join-Path $c "console.txt")
            if (([regex]::Matches($log, "game loading took")).Count -gt ([regex]::Matches($log, "STATE: exit zombie\.gameStates\.GameLoadingState")).Count) {
                $p.Refresh()
                if ($p.MainWindowHandle -ne [IntPtr]::Zero) { Send-GameClick $p.MainWindowHandle }
            }
        }
    }
}

$clicks = 0
$restarted = $false
# -ModAway: the sessions so far, and the Mods line of each next one.
$session = 1
function Set-ServerMods([string[]]$mods) {
    (Get-Content $ini) -replace "^Mods=.*$", "Mods=$($mods -join ';')" | Set-Content -Encoding ascii $ini
    Write-Host "server Mods=$($mods -join ';')"
}
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 5
    # -Restart: once every client waits at the main menu, the server goes
    # down saved and comes up again on the same world.
    if ($ModAway) {
        $goFile = Join-Path $clientCaches[0] "Lua\TLG_harness_mpgo.txt"
        $state = Read-Shared (Join-Path $clientCaches[0] "Lua\TLG_harness_mpstate.txt")
        # The go-file goes once the client has taken it, so the next wait
        # at the main menu waits for the next restart.
        if ((Test-Path $goFile) -and $state -notmatch "phase=restart_wait") { Remove-Item $goFile -ErrorAction SilentlyContinue }
        if ($session -lt 3 -and -not (Test-Path $goFile) -and $state -match "phase=restart_wait") {
            Write-Host "the client left after session ${session}: restarting the server"
            Stop-HarnessServer
            Move-Item -Force $serverOut (Join-Path $serverCache "server-stdout-$session.txt")
            $session++
            Set-ServerMods $(if ($session -eq 2) { @("TheLastGallonHarness") } else { $active })
            if (-not (Start-HarnessServer)) { break }
            Set-Content -Encoding ascii $goFile -Value "go=1"
        }
    }
    if ($Restart -and -not $restarted) {
        $left = @($clientCaches | Where-Object {
            (Read-Shared (Join-Path $_ "Lua\TLG_harness_mpstate.txt")) -match "phase=restart_wait" }).Count
        if ($left -eq $Clients) {
            Write-Host "all clients left: restarting the server"
            Stop-HarnessServer
            Move-Item -Force $serverOut $serverOut1
            $restarted = $true
            if (-not (Start-HarnessServer)) { break }
            foreach ($c in $clientCaches) { Set-Content -Encoding ascii (Join-Path $c "Lua\TLG_harness_mpgo.txt") -Value "go=1" }
        }
    }
    $allDone = $true
    for ($i = 0; $i -lt $Clients; $i++) {
        $c = $clientCaches[$i]; $p = $procs[$i]
        if ((Read-Shared (Join-Path $c "Lua\TLG_harness_mp.txt")) -notmatch "(?m)^DONE") { $allDone = $false }
        if ($p.HasExited) { continue }
        $log = Read-Shared (Join-Path $c "console.txt")
        if (([regex]::Matches($log, "game loading took")).Count -gt ([regex]::Matches($log, "STATE: exit zombie\.gameStates\.GameLoadingState")).Count) {
            $p.Refresh()
            if ($p.MainWindowHandle -ne [IntPtr]::Zero) { Send-GameClick $p.MainWindowHandle; $clicks++ }
        }
    }
    if ($allDone) { break }
    if (@($procs | Where-Object { -not $_.HasExited }).Count -eq 0) { break }
}
Write-Host "click-to-start clicks sent: $clicks"
$grace = (Get-Date).AddSeconds(90)
while ((Get-Date) -lt $grace -and @($procs | Where-Object { -not $_.HasExited }).Count -gt 0) { Start-Sleep -Seconds 3 }
foreach ($p in $procs) { if (-not $p.HasExited) { Write-Host "watchdog: stopping client $($p.Id)"; Stop-Process -Id $p.Id -Force } }

if (-not $script:server.HasExited) { Stop-HarnessServer }
Stop-HarnessServers
Write-Host "server exited"
if ($ModAway) {
    Move-Item -Force $serverOut (Join-Path $serverCache "server-stdout-$session.txt") -ErrorAction SilentlyContinue
    # Each session's lines of the mod, and of mods loaded; no account line
    # matches these patterns.
    foreach ($n in 1..3) {
        $f = Join-Path $serverCache "server-stdout-$n.txt"
        Write-Host "===== server session ${n}:"
        (Read-Shared $f) -split "`n" | Where-Object { $_ -match "\[TLG\]\[(ERROR|WARN)|The Last Gallon .* ready|was missing and is back|loading TheLastGallon|mod .* (is missing|not found)" } |
            Select-Object -First 12 | ForEach-Object { Write-Host "server: $($_.Trim())" }
    }
}
# A kicked client shows only as missing checks otherwise.
((Read-Shared $serverOut1) + "`n" + (Read-Shared $serverOut)) -split "`n" |
    Where-Object { $_ -match "(?i)\bkick(ed)?\b|anti-?cheat|\bbanned\b" } | ForEach-Object {
    $l = $_.Trim()
    foreach ($p in $cred.Values) { if ($p) { $l = $l.Replace($p, "********") } }
    Write-Host "server: $l"
}

for ($i = 0; $i -lt $Clients; $i++) {
    $f = Join-Path $clientCaches[$i] "Lua\TLG_harness_mp.txt"
    Write-Host "===== client $($roles[$i]): $f"
    if (Test-Path $f) { Get-Content $f } else { Write-Host "no results file"; Get-Content (Join-Path $clientCaches[$i] "client-stdout.txt") -Tail 30 }
    $shots = Join-Path $clientCaches[$i] "Screenshots"
    if (Test-Path $shots) {
        Get-ChildItem $shots -File | Where-Object { $_.LastWriteTime -ge $started } | ForEach-Object { Write-Host "screenshot: $($_.FullName)" }
    }
}
$f = Join-Path $serverLua "TLG_harness_mpserver.txt"
Write-Host "===== server: $f"
if (Test-Path $f) { Get-Content $f } else { Write-Host "no results file" }
# 0 when every client finished its steps (whatever they found), else 5;
# not robocopy's last code, which run 139 returned.
exit $(if ($allDone) { 0 } else { 5 })
