@echo off
setlocal

set "PROJECT_DIR=%~dp0."
set "GODOT_EXE=%~dp0..\Godot_v4.6.3-stable_win64.exe"

if exist "%GODOT_EXE%" goto launch

for %%G in (godot.exe godot4.exe) do (
    for /f "delims=" %%P in ('where %%G 2^>nul') do (
        set "GODOT_EXE=%%P"
        goto launch
    )
)

echo.
echo [ERROR] Godot 4 executable was not found.
echo Expected: %~dp0..\Godot_v4.6.3-stable_win64.exe
echo.
echo Install Godot 4 or place the executable at the expected path,
echo then run BeamPresetReviewer.cmd again.
echo.
pause
exit /b 1

:launch
start "AIQUIZ Beam Preset Reviewer" "%GODOT_EXE%" --path "%PROJECT_DIR%" --scene "res://tools/beam_reviewer/beam_preset_reviewer.tscn"
if errorlevel 1 (
    echo.
    echo [ERROR] The beam preset reviewer could not be started.
    echo Godot: %GODOT_EXE%
    echo Project: %PROJECT_DIR%
    echo.
    pause
    exit /b 1
)

endlocal
