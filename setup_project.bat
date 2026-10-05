@echo off
flutter create --platforms=android,ios .
if errorlevel 1 exit /b %errorlevel%
flutter pub get
pause
