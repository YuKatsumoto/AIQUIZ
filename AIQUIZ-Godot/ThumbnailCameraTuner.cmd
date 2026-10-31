@echo off
setlocal

rem Thumbnail camera tuner (tests/pv_capture/pv_thumbtune_runtime.gd).
rem   ThumbnailCameraTuner.cmd [shot] [frame] [quality] [extra args...]
rem   e.g. ThumbnailCameraTuner.cmd t5 63
rem        ThumbnailCameraTuner.cmd t5 63 low
rem        ThumbnailCameraTuner.cmd t5 63 ultra cam=7.3,1.1,-12,3.4,2.57,1.44,42
rem Defaults: shot t5, the frame finish.py uses, quality ultra.
rem Use ultra (same as the final capture) to freeze exactly the same moment.
rem All arguments are passed to Godot as they are (cmd would split "a=b" if we parsed them here).

set "PROJECT_DIR=%~dp0."

for %%P in (
    "%~dp0Godot_v4.7.2-stable_win64_console.exe"
    "%~dp0..\Godot_v4.7.2-stable_win64_console.exe"
    "%USERPROFILE%\Downloads\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
) do (
    if exist %%P (
        set "GODOT_EXE=%%~P"
        goto launch
    )
)
for %%G in (godot.exe godot4.exe) do (
    for /f "delims=" %%P in ('where %%G 2^>nul') do (
        set "GODOT_EXE=%%P"
        goto launch
    )
)

echo.
echo [ERROR] Godot 4.7 executable was not found.
echo Place Godot_v4.7.2-stable_win64_console.exe next to this file and run it again.
echo.
pause
exit /b 1

:launch
rem Rewinding (B key) writes the next args to RELAUNCH and quits; we start Godot again with them.
set "THUMBTUNE_LAUNCHER=1"
set "RELAUNCH=%~dp0artifacts\pv_capture\thumbtune_relaunch.txt"
if exist "%RELAUNCH%" del "%RELAUNCH%"
set "ARGS=%*"
echo Godot: %GODOT_EXE%

:run
echo Args: %ARGS%
"%GODOT_EXE%" --path "%PROJECT_DIR%" --resolution 1920x1080 --fixed-fps 480 --script res://tests/pv_capture/pv_take_bootstrap.gd -- take=thumbtune quality=ultra sub=8 %ARGS%
if exist "%RELAUNCH%" (
    set /p ARGS=<"%RELAUNCH%"
    del "%RELAUNCH%"
    echo.
    echo Rewinding...
    goto run
)
echo.
echo Saved images and args: artifacts\pv_capture\thumb_^<shot^>_tune\
pause
endlocal
