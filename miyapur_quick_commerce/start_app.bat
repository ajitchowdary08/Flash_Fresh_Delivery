@echo off
echo ========================================================
echo Launching Flash Fresh Quick Commerce Flutter App
echo ========================================================
cd /d "%~dp0customer_app"
flutter run -d chrome
pause
