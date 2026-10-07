@echo off
rem A Cow or Chicken - start the game server on this PC.
rem Double-click this file. Leave the window open while everyone plays.
setlocal
title A Cow or Chicken - server
cd /d "%~dp0.."

set "GODOT_EXE=%GODOT%"
if not defined GODOT_EXE set "GODOT_EXE=C:\Godot\Godot_v4.7.2-stable_win64_console.exe"

if not exist "%GODOT_EXE%" (
	echo Could not find Godot here:
	echo     %GODOT_EXE%
	echo.
	echo Install Godot 4.7.2 to C:\Godot, or ask Gabe.
	echo.
	pause
	exit /b 1
)

echo Starting the server. This window has no game in it - that is normal.
echo Wait for the line that says "server up", then everyone can join.
echo To stop the server, close this window.
echo.
"%GODOT_EXE%" --headless --path . -- --server

echo.
echo The server has stopped.
pause
