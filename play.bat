@echo off
rem Dead Days - one-click launcher.
rem Double-click this file to play. Edit GODOT below if your Godot lives elsewhere.
setlocal
set "GODOT=D:\GameDev\Godot_v4.7.2-stable_win64.exe"
if not exist "%GODOT%" (
  echo [ERROR] Godot not found: %GODOT%
  echo Edit GODOT in this .bat to point at your Godot 4.7 executable.
  pause
  exit /b 1
)
start "" "%GODOT%" --path "%~dp0godot"
