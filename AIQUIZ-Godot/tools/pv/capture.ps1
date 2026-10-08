# Captures one PV shot (tests/pv/shots/<shot>.gd) with the real game.
#   powershell -File tools/pv/capture.ps1 -Shot intro_solo [-Take 1] [-Seed 1] [-Quality high]
# Frames (1920x1080 JPEG) and marks.json go to G:/aiquiz_pv_raw/<shot>_t<take>/, the Movie Maker
# AVI (audio + 1280x720 reference) to movie.avi beside them, the console log to run.log.
param(
    [Parameter(Mandatory = $true)][string]$Shot,
    [int]$Take = 1,
    [int]$Seed = 0,
    [string]$Quality = "high",
    [string]$RawRoot = "G:/aiquiz_pv_raw"
)
$ErrorActionPreference = "Stop"
$project = Resolve-Path (Join-Path $PSScriptRoot "../..")
$godot = Join-Path $project "Godot_v4.7.2-stable_win64_console.exe"
if ($Seed -eq 0) { $Seed = $Take }
$out = "$RawRoot/${Shot}_t$Take"
if (Test-Path $out) { Remove-Item -Recurse -Force $out }
New-Item -ItemType Directory -Force "$out/frames" | Out-Null
$arguments = @("--path", $project, "--script", "res://tests/pv/pv_bootstrap.gd", "--resolution", "1920x1080",
    "--position", "0,0", "--fixed-fps", "60", "--write-movie", "$out/movie.avi",
    "--", "shot=$Shot", "take=$Take", "seed=$Seed", "quality=$Quality", "out=$out")
$started = Get-Date
# Godot writes harmless errors to stderr; PowerShell 5.1 must not treat them as terminating.
$ErrorActionPreference = "Continue"
& $godot @arguments 2>&1 | ForEach-Object { "$_" } | Set-Content -Encoding utf8 "$out/run.log"
$code = $LASTEXITCODE
$minutes = [math]::Round(((Get-Date) - $started).TotalMinutes, 1)
$done = Select-String -Path "$out/run.log" -Pattern "PV_DONE" | Select-Object -Last 1
Write-Output "exit=$code minutes=$minutes $($done.Line)"
exit $code
