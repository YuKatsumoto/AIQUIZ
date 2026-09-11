@echo off
chcp 65001 > nul
set "ROOT=%~dp0..\..\AIQUIZ-v1\AIQUIZ-v1"
if not exist "%ROOT%\2D_pygame.py" (
  echo 旧版 2D_pygame.py が見つかりません:
  echo   %ROOT%
  pause
  exit /b 1
)
cd /d "%ROOT%"
set LLM_MODE=OFFLINE
echo 旧版 AIQUIZ 2D をオフラインモードで起動します...
python "2D_pygame.py"
if errorlevel 1 (
  echo.
  echo 起動に失敗しました。Python と pygame が入っているか確認してください。
  echo   pip install pygame
  pause
)
