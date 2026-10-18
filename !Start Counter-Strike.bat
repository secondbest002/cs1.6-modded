@echo off
setlocal enabledelayedexpansion

:: ============================================================================
:: Counter-Strike 1.6 Portable Launcher
:: Automatically configures registry on new machines and launches the game
:: ============================================================================

:: 1. Anchor working directory to game folder
cd /d "%~dp0"

:: 2. Check if Half-Life settings exist in registry; if not, import portable settings
reg query "HKCU\Software\Valve\Half-Life\Settings" /v Key >nul 2>&1
if !errorlevel! neq 0 (
    echo [*] First time launch on this machine detected.
    echo [*] Applying portable registry settings...
    reg import portable_settings.reg >nul 2>&1
    echo [✓] Registry initialized successfully.
)

:: 3. Launch Counter-Strike 1.6
start "" hl.exe -game cstrike -steam -nomaster -noforcemparms -noforcemaccel
exit