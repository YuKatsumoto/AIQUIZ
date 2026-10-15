@echo off
rem Opens the AIQUIZ logo editor in the browser. Close this window when done.
cd /d "%~dp0..\.."
python tools\logo_editor\server.py
if errorlevel 1 pause
