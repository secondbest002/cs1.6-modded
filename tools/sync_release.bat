@echo off
setlocal enabledelayedexpansion

:: ============================================================================
:: Counter-Strike 1.6 - Git Multi-Worktree Release Synchronization
:: Zero Unicode Emojis - ASCII Standard Batch Wrapper
:: ============================================================================

title CS 1.6 - Git Multi-Worktree Release Sync

:: Ensure Python is available
where python >nul 2>nul
if %errorlevel% neq 0 (
    where py >nul 2>nul
    if !errorlevel! neq 0 (
        echo [ERROR] Python was not found in PATH.
        echo Please install Python 3.8+ and ensure it is added to your PATH.
        pause
        exit /b 1
    ) else (
        set PY_CMD=py -3
    )
) else (
    set PY_CMD=python
)

:: Run sync script passing all parameters
%PY_CMD% "%~dp0sync_release.py" %*
set SYNC_EXIT_CODE=%ERRORLEVEL%

if %SYNC_EXIT_CODE% neq 0 (
    echo.
    echo [ERROR] Synchronization ended with errors (exit code %SYNC_EXIT_CODE%).
)

:: If double-clicked from Explorer (CMDCMDLINE matches cmd /c)
echo %CMDCMDLINE% | find /i "%~0" >nul
if not errorlevel 1 (
    echo.
    echo Press any key to exit...
    pause >nul
)

exit /b %SYNC_EXIT_CODE%
