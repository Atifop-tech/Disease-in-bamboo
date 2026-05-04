@echo off
echo Setting up ADB port forwarding for Flask API...
adb reverse tcp:5000 tcp:5000

if %errorlevel% neq 0 (
    echo [ERROR] Failed to set up port forwarding. Make sure your device is connected via USB and USB Debugging is enabled.
    pause
    exit /b %errorlevel%
)

echo Port forwarding successful!
echo.
echo Starting Flutter app...
flutter run
