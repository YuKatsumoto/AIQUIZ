# Captures several PV shots one after another (see tools/pv/capture.ps1).
#   powershell -File tools/pv/capture_all.ps1 -Shots subject_walls,sea_solo,intro_solo,duo [-Take 1]
param(
    [string[]]$Shots = @("subject_walls", "sea_solo", "intro_solo", "duo"),
    [int]$Take = 1,
    [string]$Quality = "high"
)
$capture = Join-Path $PSScriptRoot "capture.ps1"
# "-File" passes "a,b,c" as one string.
$list = $Shots | ForEach-Object { $_ -split "," } | Where-Object { $_ }
foreach ($shot in $list) {
    $result = & powershell -ExecutionPolicy Bypass -File $capture -Shot $shot -Take $Take -Quality $Quality
    Write-Output "[$shot] $result"
}
