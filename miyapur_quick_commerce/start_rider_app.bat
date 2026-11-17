@echo off
echo ========================================================
echo Launching Flash Fresh Delivery Partner (Rider) App
echo ========================================================
cd /d "%~dp0rider_app"
flutter run -d chrome
pause
