@echo off
echo ========================================================
echo Launching Miyapur Delivery Partner (Rider) App
echo ========================================================
cd /d "%~dp0rider_app"
flutter run -d chrome
pause
