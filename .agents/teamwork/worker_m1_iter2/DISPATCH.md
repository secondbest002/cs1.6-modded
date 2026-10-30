# Dispatch for Worker M1 (Iteration 2 Fixes)

## Mandatory Integrity Warning
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

## Mission
Apply the specific technical fixes identified by Reviewer M1-2 and Challenger M1-2 to `tools/cs16_mod_hub/core/amxx_adapter.py`, `tools/cs16_mod_hub/core/common.py`, and `tests/test_amxx.py`.

## Required Fixes

### 1. `tools/cs16_mod_hub/core/amxx_adapter.py`
1. **CRLF Line-Ending Preservation**:
   - `read_text()` automatically translates `\r\n` to `\n` in memory on Windows, breaking `_detect_line_ending()`.
   - Replace `read_text()` with `file_path.read_bytes().decode("utf-8", errors="replace")` everywhere in `AmxxAdapter` so actual `\r\n` characters are preserved in memory and written back out.
2. **`RE_CVAR_LINE` and `set_cvar` Regex Improvements**:
   - Update `RE_CVAR_LINE` to allow:
     - Spaces inside quotes (e.g. `hostname "My CS 1.6 Server"`, `amx_csgo_hud_style "CSGO Modern"`).
     - Slashes in values (e.g. `mapcyclefile "maps/mapcycle.txt"`).
     - Empty quotes (e.g. `sv_password ""`).
     - Inline comments following the value (e.g. `// comment` or `; comment`).
   - In `set_cvar`: Update all matching CVAR lines (or deduplicate) so a trailing duplicate doesn't shadow the new setting.
3. **`RE_PLUGIN_LINE` Plugin Name Pattern**:
   - Allow dots in the plugin name (e.g. `[a-zA-Z0-9_\-\/\.]+\.amxx`) so versioned plugins like `admin_sql.1.8.amxx` are correctly detected.
4. **`_atomic_write_file` Retry Logic**:
   - Add a retry loop (3 attempts with `time.sleep(0.05)`) around `os.replace` to gracefully handle transient Windows file locks.

### 2. `tools/cs16_mod_hub/core/common.py`
- In `run_script_streaming`: Ensure that on `subprocess.TimeoutExpired`, threads `t_out` and `t_err` are joined with a short timeout (`t.join(timeout=1.0)`) and pipes closed, preventing lingering threads.

### 3. `tests/test_amxx.py`
- Add disk CRLF preservation test: Verify `plugins_file.read_bytes()` retains `b"\r\n"` after `set_plugin_status`.
- Add test for quoted CVARs with spaces, slashes, and empty strings.

## Working Directory
`d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\worker_m1_iter2`

## Exclusively Owned Files
- `tools/cs16_mod_hub/core/amxx_adapter.py`
- `tools/cs16_mod_hub/core/common.py`
- `tests/test_amxx.py`

## Verification Requirements
Run:
- `python -m unittest tests/test_amxx.py`
- `python tests/run_all_tests.py`
- Verify zero emojis in code.
Document commands, results, and write `handoff.md`.


## 2026-10-18T04:51:01Z
You are Worker M1 (Iteration 2).
Your working directory is:
d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\worker_m1_iter2
Authoritative request:
d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\ORIGINAL_REQUEST.md
Your dispatch instructions:
d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\worker_m1_iter2\DISPATCH.md

DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Apply the required fixes to tools/cs16_mod_hub/core/amxx_adapter.py, tools/cs16_mod_hub/core/common.py, and tests/test_amxx.py. Run the tests, verify passing status, write handoff.md, and send a message.
