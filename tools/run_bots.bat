@echo off
rem A Cow or Chicken - load test: 8 test bots join the server on this PC for 10 minutes.
rem Start tools\run_server.bat first, then double-click this file.
rem Other numbers, from a terminal: run_bots.bat -Count 4 -Minutes 2 -Address 192.168.1.20
setlocal
title A Cow or Chicken - test bots
cd /d "%~dp0.."
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_bots.ps1" %*
echo.
pause
