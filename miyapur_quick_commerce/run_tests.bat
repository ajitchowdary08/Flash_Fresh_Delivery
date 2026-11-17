@echo off
echo ========================================================
echo       FLASH FRESH & SUNDAY MEAT - PYTEST SUITE
echo ========================================================
echo.
cd /d "%~dp0backend"
.\venv\Scripts\python.exe -m pytest tests/
echo.
echo ========================================================
pause
