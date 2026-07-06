@echo off
echo ============================================
echo   AI Balance Monitor - Windows Installer
echo ============================================
echo.

REM Check Python
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] Python is not installed.
    echo Please install Python 3.8+ from https://python.org
    echo Make sure to check "Add Python to PATH" during installation.
    pause
    exit /b 1
)

echo [OK] Python found
echo.

REM Install dependencies
echo Installing dependencies...
pip install -r requirements.txt
if %errorlevel% neq 0 (
    echo [ERROR] Failed to install dependencies.
    pause
    exit /b 1
)

echo.
echo [DONE] Installation complete!
echo.
echo To start the monitor:
echo   python ai_balance_monitor.py
echo.
echo Or double-click ai_balance_monitor.py in File Explorer.
echo.
echo First run: right-click the tray icon ^> Manage Keys to add your API keys.
pause
