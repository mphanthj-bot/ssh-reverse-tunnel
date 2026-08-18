@echo off
:: ============================================================
:: run_setup.bat – tự động chọn PowerShell phiên phù hợp
:: Chạy 1 lần trên máy khách Windows 10/11 để đăng ký SSH
:: ============================================================
setlocal
set "SCRIPT_DIR=%~dp0"
cd "%SCRIPT_DIR%"

:: Thử PowerShell 7 trước (nếu có), fallback là PS5
pwsh -NoProfile -Command "Write-Host 'PS7 available'" 2>nul && (
    echo Using PowerShell 7
    pwsh -NoProfile -File .\setup_windows_ssh.ps1 %*
    exit /b %errorlevel%
)

:: Fallback PS5
echo Using PowerShell 5 (default)
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup_windows_ssh.ps1 %*
exit /b %errorlevel%