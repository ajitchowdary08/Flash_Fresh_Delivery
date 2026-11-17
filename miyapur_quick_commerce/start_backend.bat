@echo off
echo ========================================================
echo Starting Flash Fresh Quick Commerce Backend (FastAPI)
echo https://flash-fresh.onrender.com
echo API Docs: https://flash-fresh.onrender.com/docs
echo ========================================================
cd /d "%~dp0backend"
venv\Scripts\python.exe run_backend.py
pause
