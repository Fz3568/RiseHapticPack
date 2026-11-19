@echo off
rem Builds ..\reframework\plugins\RiseHapticTrigger.dll with MinGW-w64 gcc.
rem gcc must be on PATH, or set GCC to its full path first (e.g. set GCC=C:\mingw64\bin\gcc.exe).
setlocal
if "%GCC%"=="" set GCC=gcc
cd /d "%~dp0"
%GCC% -O2 -Wall -Wextra -shared -static-libgcc -o ..\reframework\plugins\RiseHapticTrigger.dll RiseHapticTrigger.c -lsetupapi -lhid -lcfgmgr32
if errorlevel 1 (
    echo Build failed.
    exit /b 1
)
echo Built ..\reframework\plugins\RiseHapticTrigger.dll
