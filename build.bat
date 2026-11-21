@echo off
rem Octopus Fragment one-click build script. Real logic lives in build.ps1.
rem Usage: build.bat            (build with current version)
rem        build.bat 1.0.4      (bump version then build)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1" %*
exit /b %ERRORLEVEL%
