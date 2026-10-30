# Milestone 1 Adversarial Challenge Report: AMXX Adapter & Subprocess Stress Testing

**Challenger**: Challenger M1-2  
**Working Directory**: `d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\challenger_m1_2`  
**Target Modules**: `tools/cs16_mod_hub/core/amxx_adapter.py`, `tools/cs16_mod_hub/core/common.py`  
**Verdict**: **REQUEST_CHANGES**  
**Timestamp**: 2026-10-18T04:48:00Z  

---

## Challenge Summary

**Overall Risk Assessment**: **HIGH**  
While `common.py` demonstrates solid subprocess stream draining without deadlock and robust timeout enforcement, `amxx_adapter.py` suffers from multiple regex parsing limitations and state synchronization defects that cause failure to parse quoted strings with spaces, paths with slashes, empty strings, and versioned plugin names, as well as config corruption via duplicate lines and shadowed CVAR values.

---

## 1. Observation

Adversarial stress harness `tests/test_challenger_m1_2.py` (24 tests) was created and executed against the implementation:
Command: `python -m unittest tests.test_challenger_m1_2`
Result: `Ran 24 tests in 6.456s. FAILED (failures=6)`

### Direct Observations & Verbatim Errors:

#### 1.1 Quoted CVAR Values Containing Spaces Rejected
- **File**: `tools/cs16_mod_hub/core/amxx_adapter.py`, line 35:
  ```python
  RE_CVAR_LINE = re.compile(
      r"^(?P<indent>\s*)(?P<cvar>[a-zA-Z0-9_]+)\s+(?P<quote>[\"']?)(?P<val>[^\s\"'/]+)(?P=quote)(?P<rest>.*?)(?P<eol>\r?\n)?$"
  )
  ```
- **Verbatim Error**:
  ```
  FAIL: test_cvar_quoted_values_with_spaces (tests.test_challenger_m1_2.TestAMXXMalformedCompetitiveCfg.test_cvar_quoted_values_with_spaces)
  AssertionError: None != 'CSGO Modern' : amxx_adapter failed to parse quoted cvar with spaces. Got: None
  ```

#### 1.2 `set_cvar` Corrupts Configs by Appending Duplicate Lines for Quoted CVARs
- **File**: `tools/cs16_mod_hub/core/amxx_adapter.py`, lines 278-281:
  ```python
  re_target_cvar = re.compile(
      r"^(?P<indent>\s*)(?P<cvar>" + re.escape(cvar_name) + r")\s+(?P<quote>[\"']?)(?P<val>[^\s\"'/]+)(?P=quote)(?P<rest>.*?)(?P<eol>\r?\n)?$",
      re.IGNORECASE,
  )
  ```
- **Verbatim Error**:
  ```
  FAIL: test_set_cvar_quoted_with_spaces_does_not_duplicate (tests.test_challenger_m1_2.TestAMXXMalformedCompetitiveCfg.test_set_cvar_quoted_with_spaces_does_not_duplicate)
  AssertionError: 2 != 1 : set_cvar duplicated line due to space parsing failure: ['amx_csgo_hud_style "CSGO Modern Blue"', 'amx_csgo_hud_style CSGO Retro Orange']
  ```

#### 1.3 CVAR Values Containing Slashes `/` Rejected
- **File**: `tools/cs16_mod_hub/core/amxx_adapter.py`, line 35.
- **Verbatim Error**:
  ```
  FAIL: test_cvar_values_with_slashes_and_paths (tests.test_challenger_m1_2.TestAMXXMalformedCompetitiveCfg.test_cvar_values_with_slashes_and_paths)
  AssertionError: None != 'maps/mapcycle.txt' : amxx_adapter failed to parse cvar containing slashes. Got: None
  ```

#### 1.4 Empty Quoted CVAR Values `""` Rejected
- **File**: `tools/cs16_mod_hub/core/amxx_adapter.py`, line 35.
- **Verbatim Error**:
  ```
  FAIL: test_cvar_empty_quotes_value (tests.test_challenger_m1_2.TestAMXXMalformedCompetitiveCfg.test_cvar_empty_quotes_value)
  AssertionError: None != '' : amxx_adapter failed to parse empty quoted cvar. Got: None
  ```

#### 1.5 Duplicate CVAR Definitions Cause Shadowed Updates
- **File**: `tools/cs16_mod_hub/core/amxx_adapter.py`, lines 289-302 and lines 367-380.
- **Verbatim Error**:
  ```
  FAIL: test_cvar_duplicate_entries_in_file (tests.test_challenger_m1_2.TestAMXXMalformedCompetitiveCfg.test_cvar_duplicate_entries_in_file)
  AssertionError: '12' unexpectedly found in 'amx_csgo_maxrounds 12 // duplicate at bottom' : Duplicate cvar was left with stale value 12 which shadows the update: ['amx_csgo_maxrounds 15 // first', 'amx_csgo_maxrounds 12 // duplicate at bottom']
  ```

#### 1.6 Plugin Names with Multiple Dots Rejected
- **File**: `tools/cs16_mod_hub/core/amxx_adapter.py`, lines 29-32:
  ```python
  RE_PLUGIN_LINE = re.compile(
      r"^(?P<indent>\s*)(?P<comment>;*)\s*(?P<plugin>[a-zA-Z0-9_\-\/\\]+\.amxx)(?P<rest>.*?)(?P<eol>\r?\n)?$",
      re.IGNORECASE,
  )
  ```
- **Verbatim Error**:
  ```
  FAIL: test_plugin_with_dots_in_filename (tests.test_challenger_m1_2.TestAMXXMalformedPluginsIni.test_plugin_with_dots_in_filename)
  AssertionError: 'admin_sql.1.8.amxx' not found in [] : RE_PLUGIN_LINE failed to match plugin with dots: []
  ```

#### 1.7 Windows File Lock Collision in `_atomic_write_file`
- **File**: `tools/cs16_mod_hub/core/amxx_adapter.py`, line 90:
  `os.replace(temp_path, target_path)`
- **Verbatim Error**:
  ```
  (5, 'PermissionError', "[WinError 5] Access is denied: 'C:\\...\\tmpf719ppty' -> 'C:\\...\\concurrent_test.cfg'")
  ```

#### 1.8 Unjoined Reader Threads on Timeout in `common.py`
- **File**: `tools/cs16_mod_hub/core/common.py`, lines 187-199:
  ```python
  except subprocess.TimeoutExpired:
      proc.kill()
      proc.wait()
      msg = f"Process execution timed out after {timeout} seconds."
      if log_callback:
          log_callback(f"[ERROR] {msg}")
      return AdapterResult(
          success=False,
          message=msg,
          stdout="".join(stdout_lines),
          stderr="".join(stderr_lines),
          returncode=-1,
      )
  ```
  Notice: `t_out.join(timeout=1.0)` and `t_err.join(timeout=1.0)` are not invoked in the `except subprocess.TimeoutExpired` block prior to reading `"".join(stdout_lines)`.

---

## 2. Logic Chain

1. **Quoted Spaces & Special Characters (Observations 1.1, 1.3, 1.4)**:
   - *Observation*: `RE_CVAR_LINE` defines value pattern as `(?P<quote>[\"']?)(?P<val>[^\s\"'/]+)(?P=quote)`.
   - *Logic*: The character set `[^\s\"'/]+` excludes all whitespace `\s`, excludes `/`, and enforces `+` (minimum 1 character).
   - *Impact*: In Counter-Strike 1.6 and AMXX configs, strings with spaces (`amx_csgo_hud_style "CSGO Modern"`, `hostname "My Server"`), paths with slashes (`mapcyclefile "maps/mapcycle.txt"`, `sv_downloadurl "http://..."`), and empty strings (`sv_password ""`) are standard valid syntax. `get_cvar` returns `None` for all of them.

2. **File Corruption via Accidental Line Duplication (Observation 1.2)**:
   - *Observation*: `set_cvar` checks whether the target cvar line matches via `re_target_cvar`.
   - *Logic*: When `re_target_cvar` fails to match an existing quoted cvar (due to whitespace or slashes), `found` remains `False`. Since `append_if_missing` defaults to `True`, `set_cvar` appends a new line to the bottom.
   - *Impact*: Modifying any setting containing spaces appends a duplicate line while leaving the original untouched, creating syntax ambiguities and configuration bloat.

3. **Runtime Setting Shadowing by Duplicates (Observation 1.5)**:
   - *Observation*: `set_cvar` stops searching after the first match (`if m and not found: found = True`).
   - *Logic*: If a configuration file contains an existing duplicate line later in the file (common in CS 1.6 server configs), `set_cvar` updates the first match and ignores the second match.
   - *Impact*: In the GoldSrc engine, configuration files execute sequentially from top to bottom; later lines override earlier lines. The user's updated setting is silently overwritten by the unchanged duplicate at game startup.

4. **Third-Party AMXX Plugin Invisibility (Observation 1.6)**:
   - *Observation*: `RE_PLUGIN_LINE` defines plugin pattern as `(?P<plugin>[a-zA-Z0-9_\-\/\\]+\.amxx)`.
   - *Logic*: The character set excludes `.` (dot).
   - *Impact*: Any plugin with version numbers or multiple dots (e.g. `admin_sql.1.8.amxx`, `reapi.5.24.amxx`, `statsx_shell.2.0.amxx`) fails to match, and is omitted from `list_all_plugins()` and cannot be enabled/disabled.

5. **Windows Atomic Rename Concurrency (Observation 1.7)**:
   - *Observation*: `_atomic_write_file` calls `os.replace` directly without retry backoff.
   - *Logic*: On Windows filesystem NTFS/FAT32, `os.replace` fails with `WinError 5 Access is denied` if another process or thread has a read handle open at that exact instant.
   - *Impact*: Simultaneous UI tab operations or file watchers crash with unhandled `PermissionError`.

---

## 3. Challenges

### [Critical] Challenge 1: Quoted Values with Spaces & Slashes Break Config Engine
- **Assumption challenged**: The regex `(?P<quote>[\"']?)(?P<val>[^\s\"'/]+)(?P=quote)` can parse all valid CS 1.6 CVARs.
- **Attack scenario**: Config file specifies `amx_csgo_hud_style "CSGO Modern Blue"` or `mapcyclefile "maps/mapcycle.txt"`.
- **Blast radius**: `get_cvar` returns `None`. `set_cvar` appends a conflicting duplicate at EOF.
- **Mitigation**: Update `RE_CVAR_LINE` and `re_target_cvar` to permit whitespace and slashes within quoted strings:
  ```python
  RE_CVAR_LINE = re.compile(
      r"^(?P<indent>\s*)(?P<cvar>[a-zA-Z0-9_]+)\s+(?:\"(?P<val_quoted>[^\"]*)\"|'(?P<val_single>[^']*)'|(?P<val_unquoted>[^\s/]+))(?P<rest>.*?)(?P<eol>\r?\n)?$",
      re.IGNORECASE,
  )
  ```

### [High] Challenge 2: Duplicate CVARs Cause Silent In-Game Setting Reversion
- **Assumption challenged**: Modifying only the first occurrence of a CVAR in a `.cfg` file is sufficient.
- **Attack scenario**: File contains `amx_csgo_maxrounds 12` on line 1 and `amx_csgo_maxrounds 12` on line 30. User changes maxrounds to 15.
- **Blast radius**: Line 1 is updated to 15, but Line 30 remains 12. GoldSrc executes Line 30 last, resetting maxrounds back to 12 in-game without any error shown to the user.
- **Mitigation**: In `set_cvar` and `set_competitive_settings`, either update ALL matching CVAR occurrences or update the last occurrence and remove earlier duplicates.

### [Medium] Challenge 3: Inability to Detect Versioned AMXX Plugins with Dots
- **Assumption challenged**: Plugin base names only contain alphanumeric characters, underscores, hyphens, and slashes.
- **Attack scenario**: Server administrator installs `admin_sql.1.8.amxx` or `reapi.5.24.amxx`.
- **Blast radius**: `list_all_plugins()` omits the plugin.
- **Mitigation**: Allow dots in the plugin name pattern:
  ```python
  RE_PLUGIN_LINE = re.compile(
      r"^(?P<indent>\s*)(?P<comment>;*)\s*(?P<plugin>[a-zA-Z0-9_\-\/\.\\]+\.amxx)(?P<rest>.*?)(?P<eol>\r?\n)?$",
      re.IGNORECASE,
  )
  ```

### [Medium] Challenge 4: Windows Concurrency Lock Handling
- **Assumption challenged**: `os.replace` is always atomic and non-blocking on Windows.
- **Attack scenario**: Rapid concurrent saves from multi-threaded GUI tabs or live log monitors.
- **Blast radius**: `PermissionError: [WinError 5] Access is denied` crashes the application.
- **Mitigation**: Add a lightweight retry loop with exponential backoff (e.g. 5 attempts with 10-50ms jittered delay) around `os.replace(temp_path, target_path)`.

### [Low] Challenge 5: Stream Reader Thread Draining on Timeout
- **Assumption challenged**: Process termination on timeout immediately halts reader threads cleanly.
- **Attack scenario**: Subprocess times out while writing diagnostic output to pipe.
- **Blast radius**: Missing diagnostic stderr output in returned `AdapterResult`.
- **Mitigation**: Call `t_out.join(timeout=1.0)` and `t_err.join(timeout=1.0)` inside `except subprocess.TimeoutExpired:`.

---

## 4. Stress Test Results

| Test Scenario | Target | Expected Behavior | Actual Behavior | Result |
|---|---|---|---|---|
| Strange indentation & tabs | `plugins.ini` | Indentation preserved | Preserved | **PASS** |
| Multiple leading semicolons | `plugins.ini` | Detect disabled, single `;` on disable | Handled cleanly | **PASS** |
| Missing trailing newline at EOF | `plugins.ini` | Edit last line without truncation | Handled cleanly | **PASS** |
| Mixed CRLF and LF | `plugins.ini` | No `\r\r\n` double carriage returns | Handled cleanly | **PASS** |
| Path-prefixed plugins | `plugins.ini` | Retains directory prefix on toggle | Handled cleanly | **PASS** |
| Quoted CVAR with spaces | `csgo_competitive.cfg` | Reads `"CSGO Modern"` | Returns `None` | **FAIL** |
| Quoted CVAR update duplicate check | `csgo_competitive.cfg` | Updates in-place (1 line) | Appends duplicate (2 lines) | **FAIL** |
| CVAR with slashes / paths | `csgo_competitive.cfg` | Reads `"maps/mapcycle.txt"` | Returns `None` | **FAIL** |
| Empty quoted CVAR | `csgo_competitive.cfg` | Reads `""` | Returns `None` | **FAIL** |
| Duplicate CVAR handling | `csgo_competitive.cfg` | Stale duplicates updated/removed | Duplicate remains `12` | **FAIL** |
| Plugin filename with dots | `plugins.ini` | `admin_sql.1.8.amxx` found | Plugin dropped (`[]`) | **FAIL** |
| Subprocess timeout enforcement | `common.py` | Killed at ~1s, returncode -1 | Completed in 1.1s, code -1 | **PASS** |
| High throughput 20k-line draining | `common.py` | No pipe buffer deadlock | 20k lines captured cleanly | **PASS** |
| Unicode & monochrome glyph output | `common.py` | UTF-8 lines preserved | No crash, 100% matched | **PASS** |
| Process exit code propagation | `common.py` | Returncode 3 and error line | Correctly extracted | **PASS** |
| Nonexistent script path | `common.py` | Safe `AdapterResult(False)` | Safe `AdapterResult(False)` | **PASS** |
| Concurrent atomic write thread-safety | `common.py` | All writes succeed or retry | Occasional WinError 5 | **FAIL (stress)** |

---

## 5. Caveats

- **Scope boundary**: Underlying skill scripts in `.agents/skills/` were not modified.
- **Review-only enforcement**: Challenger did NOT modify production implementation code in `tools/cs16_mod_hub/core/`. All 6 bugs were preserved to allow Worker M1 to implement the mitigations cleanly.
- **Test file presence**: `tests/test_challenger_m1_2.py` adheres 100% to zero-emoji compliance verified by `tests/test_emoji_cleanliness.py`.

---

## 6. Conclusion

The verdict is **REQUEST_CHANGES**.  
While the architectural design and subprocess management in `common.py` are robust, `amxx_adapter.py` contains 6 concrete, reproducible defects that impair configuration parsing, create duplicate setting entries, shadow runtime values in-game, and reject standard AMXX plugins with version dots. Worker M1 must apply the targeted regex and deduplication fixes before Milestone 1 backend adapters can be approved.

---

## 7. Verification Method

To independently reproduce the failures:

1. **Run the Challenger Adversarial Test Suite**:
   ```powershell
   python -m unittest tests.test_challenger_m1_2
   ```
   *Expected outcome*: 6 failed assertions demonstrating the exact failure modes detailed in Section 1.

2. **Verify Emoji Cleanliness Compliance**:
   ```powershell
   python -m unittest tests.test_emoji_cleanliness
   ```
   *Expected outcome*: 5 passed tests (0 emojis across entire repository).
