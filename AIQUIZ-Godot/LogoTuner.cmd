@echo off
setlocal

rem Thumbnail title logo tuner (docs/pv/thumbnail/logo_tuner.py).
rem   LogoTuner.cmd [name]
rem   e.g. LogoTuner.cmd              (t8_blender)
rem        LogoTuner.cmd t5_blender
rem Drag the logo to move it, mouse wheel to resize, Ctrl+S to save
rem (writes docs/pv/thumbnail/logo_layout.json and final/<name>.png/.jpg).

cd /d "%~dp0"
python docs\pv\thumbnail\logo_tuner.py %*
if errorlevel 1 pause
endlocal
