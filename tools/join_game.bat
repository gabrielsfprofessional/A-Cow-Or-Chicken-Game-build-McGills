@echo off
rem A Cow or Chicken - join a game.
rem Double-click this file, then type the server address or just press Enter.
setlocal
title A Cow or Chicken - join
cd /d "%~dp0.."

set "GODOT_EXE=C:\Godot\Godot_v4.7.2-stable_win64.exe"

if not exist "%GODOT_EXE%" (
	echo Could not find Godot here:
	echo     %GODOT_EXE%
	echo.
	echo Install Godot 4.7.2 to C:\Godot, or ask Gabe.
	echo.
	pause
	exit /b 1
)

set "ADDRESS=%~1"
if not defined ADDRESS set /p "ADDRESS=Server address (Enter = this PC): "
if not defined ADDRESS set "ADDRESS=127.0.0.1"

echo.
echo Joining %ADDRESS% ...
start "" "%GODOT_EXE%" --path . -- "--join=%ADDRESS%"
