# Puts the game's user files back from a capture's backup (only needed when a capture was killed
# before it could restore them itself).
#   powershell -File tools/pv/restore_user.ps1 -Take G:/aiquiz_pv_raw/intro_solo_t2
param([Parameter(Mandatory = $true)][string]$Take)
$user = Join-Path $env:APPDATA "Godot/app_userdata/AIQUIZ 3D"
$backup = Join-Path $Take "user_backup"
if (-not (Test-Path $backup)) { Write-Error "no backup in $Take"; exit 1 }
Get-ChildItem $backup -File | ForEach-Object {
    $target = Join-Path $user $_.Name
    if (-not (Test-Path $target) -or (Get-FileHash $target).Hash -ne (Get-FileHash $_.FullName).Hash) {
        Copy-Item $_.FullName $target -Force
        Write-Output "restored $($_.Name)"
    }
}
