@echo off
rem Record a 2-player S09 session for the PV (tests/pv_capture/pv_s09_play_runtime.gd, see docs/pv/takes/s09_play.md).
rem Optional argument: record name (default s09_play_rec). Use a new name to keep earlier records, e.g. record_s09_play.cmd s09_play_rec2
cd /d "%~dp0..\.."
set TAG=%1
if "%TAG%"=="" set TAG=s09_play_rec
echo Starting S09 record: %TAG%  (wait for [REC] at the top left, then press Enter to start)
Godot_v4.7.2-stable_win64_console.exe --path . --resolution 1920x1080 --fixed-fps 60 --script res://tests/pv_capture/pv_take_bootstrap.gd -- take=s09_play mode=record quality=ultra tag=%TAG% > "artifacts\pv_capture\%TAG%_run.log" 2>&1
echo.
echo Saved: artifacts\pv_capture\%TAG%\inputs.json
pause
