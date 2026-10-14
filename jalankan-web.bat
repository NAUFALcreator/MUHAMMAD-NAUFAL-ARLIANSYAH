@echo off
title SIAntri Server Web
echo ======================================================
echo           MEMULAI SERVER SIAntri WEB
echo ======================================================
echo.

where python >nul 2>nul
if %errorlevel% equ 0 (
    set PY=python
) else (
    where py >nul 2>nul
    if %errorlevel% equ 0 (
        set PY=py
    ) else (
        echo [ERROR] Python tidak ditemukan di sistem!
        echo Pastikan Python telah terinstall dan dicentang "Add python.exe to PATH".
        pause
        exit /b 1
    )
)

set WEB_DIR=""
if exist "%~dp0siantri-queueflow\web" (
    set WEB_DIR="%~dp0siantri-queueflow\web"
) else if exist "%~dp0web" (
    set WEB_DIR="%~dp0web"
) else (
    echo [ERROR] Folder web tidak ditemukan!
    pause
    exit /b 1
)

echo 1. Membuka browser ke http://localhost:8080 ...
start http://localhost:8080
echo.
echo 2. Menjalankan server lokal di port 8080 ...
echo    (Tutup jendela ini atau tekan Ctrl + C untuk berhenti)
echo ======================================================

%PY% -m http.server 8080 --directory %WEB_DIR%
pause
