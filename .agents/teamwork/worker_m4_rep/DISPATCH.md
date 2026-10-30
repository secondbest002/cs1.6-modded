# Dispatch for Worker M4 (Replacement)

## Mandatory Integrity Warning
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

## Mission
Resume and complete Milestone 4: Implement and verify `CS16_Mod_Manager.bat` in the game root `d:\Games\Counter-Strike\Counter-Strike 1.6 Original\CS16_Mod_Manager.bat`:

### Detailed Specifications for `CS16_Mod_Manager.bat`
```bat
@echo off
setlocal enabledelayedexpansion

:: ============================================================================
:: Counter-Strike 1.6 Mod Hub - Unified Desktop Launcher
:: Modern Dark Slate Mod Manager Automation Script
:: ============================================================================

title Counter-Strike 1.6 Mod Hub Launcher

:: 1. Anchor working directory to game root
cd /d "%~dp0"

:: 2. Locate valid Python installation
set "PY_CMD="
for %%P in (python py) do (
    if not defined PY_CMD (
        %%P --version >nul 2>&1
        if !errorlevel! equ 0 set "PY_CMD=%%P"
    )
)

if not defined PY_CMD (
    echo.
    echo ============================================================================
    echo [ERROR] Python 3 installation was not found in your system PATH.
    echo ============================================================================
    echo The CS 1.6 Mod Hub requires Python 3.10 or newer.
    echo Please download and install Python from https://www.python.org/
    echo Ensure you check "Add python.exe to PATH" during installation.
    echo.
    pause
    exit /b 1
)

:: 3. Check for required GUI packages: customtkinter and pillow
%PY_CMD% -c "import customtkinter, PIL" >nul 2>&1
if !errorlevel! neq 0 (
    echo.
    echo ============================================================================
    echo [*] Checking GUI Dependencies...
    echo [*] Required packages missing. Auto-installing: customtkinter pillow
    echo ============================================================================
    echo.
    %PY_CMD% -m pip install customtkinter pillow
    if !errorlevel! neq 0 (
        echo.
        echo [ERROR] Automated dependency installation failed.
        echo Please ensure you have internet access and run:
        echo   %PY_CMD% -m pip install customtkinter pillow
        echo.
        pause
        exit /b 1
    )
    echo.
    echo [OK] Dependencies installed successfully.
    echo ============================================================================
)

:: 4. Verify main application entry point exists
if not exist "tools\cs16_mod_hub\main.py" (
    echo.
    echo [ERROR] Entry point not found: tools\cs16_mod_hub\main.py
    echo Please verify that the tools directory is properly installed.
    echo.
    pause
    exit /b 1
)

:: 5. Determine launch command (pythonw for silent GUI, python for console/debug)
set "LAUNCH_CMD=%PY_CMD%"
where pythonw >nul 2>&1
if %errorlevel% equ 0 (
    set "LAUNCH_CMD=pythonw"
)

:: 6. Launch Application
if "%~1"=="--console" (
    echo [*] Launching CS 1.6 Mod Hub in console mode...
    %PY_CMD% tools\cs16_mod_hub\main.py %*
) else if "%~1"=="--debug" (
    echo [*] Launching CS 1.6 Mod Hub in debug mode...
    %PY_CMD% tools\cs16_mod_hub\main.py %*
) else (
    start "" %LAUNCH_CMD% tools\cs16_mod_hub\main.py %*
)

endlocal
exit /b 0
```

### Verification Requirements
1. Write the batch file to `d:\Games\Counter-Strike\Counter-Strike 1.6 Original\CS16_Mod_Manager.bat`.
2. Run test suites:
   - `python -m unittest tests/test_launcher.py`
   - `python -m unittest tests/test_emoji_cleanliness.py`
   - `python tests/run_all_tests.py`
3. Document commands, results, write `handoff.md`, and notify parent.


## 2026-10-18T05:40:43Z
[Message] timestamp=2026-10-18T05:40:43Z sender=3d51e094-ca80-4fe0-b7bc-d17c26a16d3d priority=MESSAGE_PRIORITY_HIGH
You are Worker M4 (Replacement).
Your working directory is:
d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\worker_m4_rep
Authoritative request:
d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\ORIGINAL_REQUEST.md
Your dispatch instructions:
d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\worker_m4_rep\DISPATCH.md

DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Implement CS16_Mod_Manager.bat in the game root, run tests/test_launcher.py, tests/test_emoji_cleanliness.py, and tests/run_all_tests.py, verify 0 emojis, write handoff.md, and send a message.
