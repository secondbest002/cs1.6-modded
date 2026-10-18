@echo off
setlocal enabledelayedexpansion

:: ============================================================================
:: Counter-Strike 1.6 Portable Release Packager
:: Creates a self-contained portable ZIP package ready for any PC
:: ============================================================================

cd /d "%~dp0"
echo ============================================================================
echo [*] Counter-Strike 1.6 Portable Release Packager
echo ============================================================================

python -c "
import os, zipfile, sys

output_zip = 'CS16_Portable_Game.zip'
print(f'[*] Building {output_zip}...')

# Exclude large caches, dumps, git history
exclude_dirs = {'.git', '__pycache__', 'crashdumps', 'htmlcache', '.agents'}
exclude_exts = {'.pyc', '.bak', '.tmp', '.log', '.zip'}

file_count = 0
total_size = 0

with zipfile.ZipFile(output_zip, 'w', zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk('.'):
        dirs[:] = [d for d in dirs if d not in exclude_dirs]
        for f in files:
            ext = os.path.splitext(f)[1].lower()
            if ext in exclude_exts or f == output_zip:
                continue
            path = os.path.join(root, f)
            arcname = os.path.relpath(path, '.')
            z.write(path, arcname)
            file_count += 1
            total_size += os.path.getsize(path)

print(f'[✓] Package created successfully!')
print(f'    Files: {file_count}')
print(f'    Raw size: {total_size / (1024*1024):.2f} MB')
print(f'    ZIP size: {os.path.getsize(output_zip) / (1024*1024):.2f} MB')
print(f'    File: {output_zip}')
"

echo.
echo ============================================================================
echo [✓] Done! You can transfer CS16_Portable_Game.zip to any device.
echo ============================================================================
pause
