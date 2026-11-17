@echo off
echo ========================================================
echo Starting Miyapur Quick Commerce Backend (FastAPI)
echo http://127.0.0.1:8000
echo API Docs: http://127.0.0.1:8000/docs
echo ========================================================
cd /d "%~dp0backend"
venv\Scripts\python.exe run_backend.py
pause
