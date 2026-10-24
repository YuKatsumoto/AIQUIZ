@echo off
rem Start the AIQUIZ ops viewer and open it in the browser.
rem If it is already running, just open the browser.
cd /d "%~dp0"
set "OPS_URL=http://localhost:3002/#money"
netstat -ano | findstr /r /c:"127.0.0.1:3002 .*LISTENING" >nul
if not errorlevel 1 (
  start "" "%OPS_URL%"
  exit /b 0
)
if not exist node_modules call npm install
rem Open the browser once the server accepts connections (up to 30 seconds).
start "" /min powershell -NoProfile -WindowStyle Hidden -Command "for ($i = 0; $i -lt 60; $i++) { try { (New-Object Net.Sockets.TcpClient('127.0.0.1', 3002)).Close(); Start-Process '%OPS_URL%'; exit } catch { Start-Sleep -Milliseconds 500 } }"
title AIQUIZ ops - close this window to stop
node server.js
pause
