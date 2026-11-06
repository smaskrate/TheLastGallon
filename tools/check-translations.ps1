<#
.SYNOPSIS
  Checks EN/IT translation parity and that referenced keys exist.
.DESCRIPTION
  * Every EN json file has an IT counterpart with exactly the same keys.
  * Keys referenced in Lua (string literals starting with IGUI_TLG_,
    ContextMenu_TLG_, Tooltip_TLG_, Sandbox_TLG_), fluid DisplayName values,
    item ids (ItemName "TLG.<id>") and sandbox option translations exist in EN.
  * Dynamic prefixes (IGUI_TLG_Fuel_, IGUI_TLG_TreatDone_, IGUI_TLG_Method_)
    are checked against the registry/handler values listed below.
  Exit code 1 when anything is missing.
#>
$ErrorActionPreference = "Stop"
$repo = Split-Path -Parent $PSScriptRoot
$media = Join-Path $repo "Contents\mods\TheLastGallon\common\media"
$tr = Join-Path $media "lua\shared\Translate"
$problems = @()

function Load-Keys([string]$path) {
    $obj = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
    return @($obj.PSObject.Properties.Name)
}

$en = @{}
foreach ($f in Get-ChildItem (Join-Path $tr "EN") -Filter *.json) {
    $keys = Load-Keys $f.FullName
    foreach ($k in $keys) { $en[$k] = $f.Name }
    $itPath = Join-Path (Join-Path $tr "IT") $f.Name
    if (-not (Test-Path $itPath)) { $problems += "IT missing file $($f.Name)"; continue }
    $it = Load-Keys $itPath
    foreach ($k in $keys) { if ($it -notcontains $k) { $problems += "IT/$($f.Name) missing $k" } }
    foreach ($k in $it) { if ($keys -notcontains $k) { $problems += "IT/$($f.Name) has extra $k" } }
}

$referenced = New-Object System.Collections.Generic.HashSet[string]
$luaFiles = Get-ChildItem -Recurse -File (Join-Path $media "lua") -Filter *.lua
foreach ($f in $luaFiles) {
    $text = Get-Content $f.FullName -Raw
    foreach ($m in [regex]::Matches($text, '"((IGUI|ContextMenu|Tooltip|Sandbox)_TLG_[A-Za-z0-9_]+)"')) {
        # Literals ending in "_" are prefixes for dynamic keys (checked below).
        if (-not $m.Groups[1].Value.EndsWith("_")) { [void]$referenced.Add($m.Groups[1].Value) }
    }
}
foreach ($m in [regex]::Matches((Get-Content (Join-Path $media "scripts\TLG_fluids.txt") -Raw), 'DisplayName\s*=\s*([A-Za-z0-9_]+)')) {
    [void]$referenced.Add($m.Groups[1].Value)
}
foreach ($m in [regex]::Matches(((Get-ChildItem (Join-Path $media "scripts") -Filter "TLG_*.txt" | ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n"), '(?m)^\s*item\s+([A-Za-z0-9_]+)\s*\r?$')) {
    [void]$referenced.Add("TLG." + $m.Groups[1].Value)
}
# A recipe's name in the crafting window and the craft menu is its key in
# Recipes.json (BC Translator.getRecipeName: the id itself when missing;
# RT-SP runs 191-192 found every recipe shown by its id).
$recipeCount = 0
foreach ($m in [regex]::Matches(((Get-ChildItem (Join-Path $media "scripts") -Filter "TLG_*.txt" | ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n"), '(?m)^\s*craftRecipe\s+([A-Za-z0-9_]+)\s*\r?$')) {
    [void]$referenced.Add($m.Groups[1].Value)
    $recipeCount++
}
if ($recipeCount -eq 0) { $problems += "no craftRecipe found in scripts/TLG_*.txt (pattern out of date?)" }
$sandbox = Get-Content (Join-Path $media "sandbox-options.txt") -Raw
foreach ($block in [regex]::Matches($sandbox, 'option\s+[\w\.]+\s*\{([^}]*)\}')) {
    $body = $block.Groups[1].Value
    $t = [regex]::Match($body, 'translation\s*=\s*(\w+)').Groups[1].Value
    $page = [regex]::Match($body, 'page\s*=\s*(\w+)').Groups[1].Value
    if ($t) { [void]$referenced.Add("Sandbox_$t") }
    if ($page) { [void]$referenced.Add("Sandbox_$page") }
    if ($body -match 'type\s*=\s*enum') {
        $n = [int][regex]::Match($body, 'numValues\s*=\s*(\d+)').Groups[1].Value
        $vt = [regex]::Match($body, 'valueTranslation\s*=\s*(\w+)').Groups[1].Value
        for ($i = 1; $i -le $n; $i++) { [void]$referenced.Add("Sandbox_${vt}_option$i") }
    }
}
foreach ($id in "gasoline","ethanol","diesel","biodiesel","water","sediment","plant_oil","methanol","glycerin","propane","biogas","woodgas") {
    [void]$referenced.Add("IGUI_TLG_Fuel_$id")
}
foreach ($op in "stabilize","filter","separate","seal","unseal","clean") { [void]$referenced.Add("IGUI_TLG_TreatDone_$op") }
foreach ($m in "visual","kit","lab") { [void]$referenced.Add("IGUI_TLG_Method_$m"); [void]$referenced.Add("IGUI_TLG_TestName_$m") }
foreach ($s in "Ready","InputsReserved","Processing","Paused","OutputReady","Faulted","Maintenance","Decommissioned") { [void]$referenced.Add("IGUI_TLG_MachineState_$s") }
foreach ($s in "OutputReady_fermenter","OutputReady_still","OutputReady_dryer","OutputReady_stopped","OutputReady_stopped_fermenter") { [void]$referenced.Add("IGUI_TLG_MachineState_$s") }
foreach ($s in "sugar_eq","stillage","spent_lime","quicklime_kg","yeast_starter") { [void]$referenced.Add("IGUI_TLG_Fuel_$s") }
foreach ($s in "not_processing","not_paused","nothing_to_abort","batch_spoiled") { [void]$referenced.Add("IGUI_TLG_MachineFail_$s") }
foreach ($s in "no_heat","too_cold","too_hot","paused_by_player","not_placed","output_full","batch_spoiled") { [void]$referenced.Add("IGUI_TLG_Pause_$s") }
foreach ($s in "output_full_fermenter") { [void]$referenced.Add("IGUI_TLG_Pause_$s") }
foreach ($s in "prepare","ferment","heat_up","distill","dry") { [void]$referenced.Add("IGUI_TLG_Stage_$s") }
foreach ($s in "none","Planned","InProgress","Commissioned","Cancelled","Removed","Reverted","Invalidated") { [void]$referenced.Add("IGUI_TLG_ConvState_$s") }
foreach ($s in "inspect","prepare","install","configure","test","commission") { [void]$referenced.Add("IGUI_TLG_ConvStage_$s") }
foreach ($s in "engine_si_stock","engine_si_flex","generator_si_stock","generator_si_flex","engine_ci_stock","engine_ci_bio","generator_ci_stock","generator_gas") { [void]$referenced.Add("IGUI_TLG_Profile_$s") }
foreach ($s in "flex_generator","gas_generator","flex_car_normal","flex_small_car","flex_pickup_truck","flex_step_van") { [void]$referenced.Add("IGUI_TLG_Conversion_$s") }

foreach ($k in $referenced) {
    if (-not $en.ContainsKey($k)) { $problems += "EN missing referenced key $k" }
}
if ($problems.Count -gt 0) {
    $problems | Sort-Object | ForEach-Object { Write-Host "TRANSLATION $_" }
    Write-Host "translations: $($problems.Count) problem(s), $($en.Count) EN keys, $($referenced.Count) referenced"
    exit 1
}
Write-Host "translations: OK ($($en.Count) EN keys, $($referenced.Count) referenced, IT parity)"
exit 0
