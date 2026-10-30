@echo off
setlocal enabledelayedexpansion
title CS 1.6 Asset Studio - Quick Inspector

cd /d "%~dp0"

echo =======================================================================
echo          CS 1.6 ASSET STUDIO - DRAG ^& DROP INSPECTOR
echo =======================================================================
echo.

if "%~1"=="" goto :no_file

set TARGET_FILE=%~1
set FILE_EXT=%~x1

:: Detect Python
where python >nul 2>nul
if %errorlevel% neq 0 (
    where py >nul 2>nul
    if %errorlevel% neq 0 (
        echo [ERROR] Python not found. Please install Python 3.9+.
        pause
        exit /b 1
    ) else (
        set PY_CMD=py -3
    )
) else (
    set PY_CMD=python
)

echo Target File: %TARGET_FILE%
echo Extension  : %FILE_EXT%
echo.

:: Check file extension
if /i "%FILE_EXT%"==".mdl" (
    echo === [GoldSrc IDST v10 Model Analysis] ===
    %PY_CMD% scripts\cs16_studio.py info -w "%TARGET_FILE%"
    echo.
    echo -----------------------------------------------------------------------
    set /p OPEN_UI="Would you like to launch the Web Studio Dashboard now? [Y/N]: "
    if /i "!OPEN_UI!"=="Y" (
        start "" "%~dp0CS16_Asset_Studio.bat"
    )
    goto :done
)

if /i "%FILE_EXT%"==".png" goto :inspect_image
if /i "%FILE_EXT%"==".jpg" goto :inspect_image
if /i "%FILE_EXT%"==".jpeg" goto :inspect_image
if /i "%FILE_EXT%"==".bmp" goto :inspect_image
if /i "%FILE_EXT%"==".webp" goto :inspect_image

echo [WARN] Unrecognized file type '%FILE_EXT%'.
echo Supported files: .mdl (models) or .png/.jpg/.bmp/.webp (textures ^& stickers).
goto :done

:inspect_image
echo === [Image Texture ^& Sticker Analysis] ===
%PY_CMD% -c "import sys; from pathlib import Path; from PIL import Image; p=Path(sys.argv[1]); img=Image.open(p); has_alpha = img.mode in ('RGBA', 'LA') or ('transparency' in img.info); print(f'Image Dimensions : {img.width} x {img.height} pixels'); print(f'Color Mode       : {img.mode}'); print(f'Alpha Channel    : {\"Yes (Transparent)\" if has_alpha else \"No (Opaque)\"}'); print('\nSuitability Recommendation:'); is_sq = abs(img.width - img.height) <= 32; print('  * 3D Sticker Slot : ' + ('PERFECT MATCH (High transparency decal)' if has_alpha and is_sq else ('Compatible (Auto-padded)' if has_alpha else 'Needs transparency for decal'))); print('  * Weapon Body Bake: ' + ('Ready for Click-and-Drag Composite' if has_alpha else 'Solid texture overlay')); print('  * Weapon Body Skin: ' + ('Usable as weapon wrap' if not has_alpha else 'Contains alpha (can be converted)'))" "%TARGET_FILE%"
echo.
echo -----------------------------------------------------------------------
set /p COPY_STK="Copy this image into your personal 'assets/my_stickers/' folder? [Y/N]: "
if /i "!COPY_STK!"=="Y" (
    if not exist "assets\my_stickers" mkdir "assets\my_stickers"
    copy /y "%TARGET_FILE%" "assets\my_stickers\"
    echo [Success] Copied to assets\my_stickers\%~nx1! It is now visible in the Web Studio Library.
)
goto :done

:no_file
echo [INFO] No file was dropped!
echo.
echo How to use:
echo   1. In Windows Explorer, grab any .mdl model or image file (.png, .jpg, .bmp, .webp)
echo   2. Drag and drop it directly onto this "Drop_Here_To_Inspect.bat" icon.
echo   3. Detailed texture, slot layout, and suitability analysis will appear here!
echo.

:done
echo.
pause
