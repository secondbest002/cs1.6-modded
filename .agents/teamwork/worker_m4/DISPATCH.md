# Dispatch for Worker M4: Batch Launcher & Setup Automation

## Mandatory Integrity Warning
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

## Mission
Implement and verify `CS16_Mod_Manager.bat` in the game root directory `d:\Games\Counter-Strike\Counter-Strike 1.6 Original\CS16_Mod_Manager.bat`:
1. Use the production specification from `explorer_survey_3/handoff.md`:
   - `@echo off` and `setlocal enabledelayedexpansion`.
   - `cd /d "%~dp0"` to anchor directory to game root.
   - Python discovery (looping through `python`, `py`, verifying with `--version`).
   - Friendly error message if Python is missing.
   - Auto-check and installation of missing GUI packages:
     `%PY_CMD% -c "import customtkinter, PIL" >nul 2>&1`
     If errorlevel neq 0, run `%PY_CMD% -m pip install customtkinter pillow`.
   - Verify `tools\cs16_mod_hub\main.py` entrypoint exists.
   - Launch logic:
     - Check for `pythonw` executable.
     - If `%1` is `--console` or `--debug`, run directly via `%PY_CMD% tools\cs16_mod_hub\main.py %*`.
     - Otherwise, launch windowless via `start "" %LAUNCH_CMD% tools\cs16_mod_hub\main.py %*`.
2. STRICT ZERO EMOJIS: Ensure only clean monochrome brackets and ASCII/Unicode glyphs are used (e.g. `[*]`, `[ERROR]`, `[OK]`).
3. Verification Requirements:
   - Run: `python -m unittest tests/test_launcher.py`
   - Run: `python -m unittest tests/test_emoji_cleanliness.py`
   - Run: `python tests/run_all_tests.py` (ALL tests in all tiers should now pass with 0 skips!).
   - Document commands, results, and write `handoff.md`.


## 2026-10-18T05:27:03Z
[Message] timestamp=2026-10-18T05:27:03Z sender=3d51e094-ca80-4fe0-b7bc-d17c26a16d3d priority=MESSAGE_PRIORITY_HIGH content=You are Worker M4.
Your working directory is:
d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\worker_m4
Authoritative request:
d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\ORIGINAL_REQUEST.md
Project plan:
d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\orchestrator_1\PROJECT.md
Your dispatch instructions:
d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\worker_m4\DISPATCH.md

DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Implement CS16_Mod_Manager.bat in game root, execute tests/test_launcher.py and master test runner tests/run_all_tests.py, verify 0 emojis, write handoff.md, and send a message.
