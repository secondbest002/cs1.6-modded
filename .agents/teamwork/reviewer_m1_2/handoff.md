# Milestone 1 Review & Adversarial Challenge Report

**Reviewer**: Reviewer M1-2 (reviewer, critic)  
**Working Directory**: `d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\reviewer_m1_2`  
**Target Milestone**: M1 (Core Backend Adapters & Safety Engine)  
**Target Worker**: Worker M1  
**Verdict**: **REQUEST_CHANGES**  
**Overall Risk Assessment**: HIGH  
**Timestamp**: 2026-10-18T04:49:00Z  

---

## 1. Observation

### 1.1 Automated Test Execution
All baseline test suites pass cleanly:
1. `python -m unittest tests/test_adapters.py`: Ran 30 tests in 11.572s — **OK**.
2. `python -m unittest tests/test_backups.py`: Ran 8 tests in 0.309s — **OK**.
3. `python -m unittest tests/test_amxx.py`: Ran 10 tests in 0.153s — **OK**.
4. `python -m unittest tests/test_preview.py`: Ran 8 tests in 0.132s — **OK**.
5. `python -m unittest tests/test_emoji_cleanliness.py`: Ran 5 tests in 0.051s — **OK (skipped=1)**.
6. `python tests/run_all_tests.py`: Ran 66 tests (60 passed, 6 skipped, 0 failed) in 22.48s — **SUCCESS**.

### 1.2 Independent Adversarial Stress-Tests
Independent stress scripts executed in reviewer environment:
1. `verify_palette_preview.py`: Successfully validated in-memory GoldSrc texture extraction, HSV color math, transparent index 255 key preservation on masked textures (`flags & 0x40`), and `TexturePreviewCache` performance.
2. `verify_amxx_crlf.py`: Failed with line-ending corruption error:
```
Status before: True
Set plugin status result: True
Raw bytes after disable:
b'; AMX Mod X plugins\n\nadmin.amxx\t\t; admin base\n;team_weapon_skins.amxx\t; Per-team weapon skin switcher\n;csgo_usps_silencer.amxx\t; Silencer lock\n'
Contains CRLF: False
CRLF count: 0, Naked LF count: 5
FAIL: Line endings corrupted! CRLF was converted to LF.
```

### 1.3 Exact Code Findings in `tools/cs16_mod_hub/core/amxx_adapter.py`
In `tools/cs16_mod_hub/core/amxx_adapter.py`:
- Line 146 in `set_plugin_status`:
  ```python
  text = self.plugins_ini.read_text(encoding="utf-8", errors="replace")
  eol = _detect_line_ending(text)
  ```
- Lines 251, 270 in `get_cvar`, `set_cvar`:
  ```python
  text = self.competitive_cfg.read_text(encoding="utf-8", errors="replace")
  ```
- Line 353 in `set_competitive_settings`:
  ```python
  text = self.competitive_cfg.read_text(encoding="utf-8", errors="replace")
  ```
- Lines 61-63 in `_detect_line_ending`:
  ```python
  def _detect_line_ending(text: str) -> str:
      """Detects whether text uses Windows CRLF or Unix LF."""
      return "\r\n" if "\r\n" in text else "\n"
  ```
- Lines 82-90 in `_atomic_write_file`:
  ```python
  temp_file = tempfile.NamedTemporaryFile("w", dir=target_dir, delete=False, encoding="utf-8", newline="")
  temp_path = Path(temp_file.name)
  try:
      temp_file.write(content)
      temp_file.flush()
      os.fsync(temp_file.fileno())
      temp_file.close()
      os.replace(temp_path, target_path)
  ```

---

## 2. Logic Chain

1. **Root Cause of Line-Ending Corruption**:
   - In Python standard library `Path.read_text()` (`pathlib.Path`), the underlying `open()` call defaults to `newline=None` (universal newlines mode enabled).
   - In universal newlines mode, Python translates all input `\r\n` line endings into `\n` before returning the string.
   - Consequently, `text` in `set_plugin_status()` contains zero occurrences of `\r\n`.
   - `_detect_line_ending(text)` evaluates `"\r\n" in text` to `False` and always returns `"\n"`.
   - `lines = text.splitlines(keepends=True)` produces lines ending exclusively in `\n`.
   - `_atomic_write_file()` writes `content` with `newline=""`, preserving the exact string passed to it. Because the string has only `\n`, the target file on disk is written with Unix LF line endings.
   - Therefore, whenever `AmxxAdapter` edits a Windows CRLF `plugins.ini` file, it silently corrupts the file's line endings from `\r\n` to `\n`.

2. **Why the Regression Escaped Existing Tests**:
   - In `tests/test_amxx.py`, `SAMPLE_PLUGINS_INI` is defined as a Python multiline string literal `"""..."""` which defaults to `\n` in memory.
   - `tests/test_amxx.py` tests local helper function `independent_toggle_plugin()` on in-memory strings rather than asserting binary disk bytes on disk after `AmxxAdapter.set_plugin_status()`.
   - In `tests/test_adapters.py`, `test_get_and_set_plugin_status()` tests logical return values but does not inspect raw disk bytes (`b'\r\n'`) on `plugins.ini`.

3. **Integrity Assessment**:
   - No hardcoded test values, facades, dummy bypasses, or fabricated outputs were found. The backend implementations in `model_adapter.py`, `palette_preview.py`, `sticker_adapter.py`, `vibrance_adapter.py`, and `common.py` contain genuine, robust logic.
   - The line-ending issue is a genuine implementation defect that violates Requirement R1 and PROJECT.md contract specifications ("Preserves line order, section comments, inline comments, and exact line endings").

---

## 3. Findings & Challenges

### [Critical] Finding 1: AMXX Line-Ending Corruption (CRLF to LF)
- **What**: Modifying `plugins.ini` converts all Windows CRLF (`\r\n`) line endings into Unix LF (`\n`).
- **Where**: `tools/cs16_mod_hub/core/amxx_adapter.py`, lines 131, 146, 194, 224, 251, 270, 353.
- **Why**: `Path.read_text()` enables Python universal newlines translation (`newline=None`), stripping `\r\n` on read. `_detect_line_ending()` never sees `\r\n` and returns `\n`.
- **Blast Radius**: Corrupts file format for GoldSrc/AMX Mod X Windows server configurations that expect native Windows CRLF endings.
- **Mitigation / Suggested Fix**:
  Read file contents without universal newline translation by either reading raw bytes or specifying `newline=""`:
  ```python
  # Option A: Read raw bytes and decode
  text = self.plugins_ini.read_bytes().decode("utf-8", errors="replace")

  # Option B: Open with newline=""
  with open(self.plugins_ini, "r", encoding="utf-8", errors="replace", newline="") as f:
      text = f.read()
  ```
  Apply this change across all reading methods in `amxx_adapter.py` (`set_plugin_status`, `set_cvar`, `set_competitive_settings`, `list_custom_plugins`, `list_all_plugins`, `get_cvar`).

### [Major] Finding 2: Test Suite Coverage Gap for AMXX File Roundtrips
- **What**: `tests/test_amxx.py` tests standalone oracle functions (`independent_safe_restore`, `independent_toggle_plugin`) and only checks `hasattr` on `AmxxAdapter` and `model_adapter`.
- **Where**: `tests/test_amxx.py` lines 193-232, `tests/test_backups.py` lines 134-150.
- **Why**: Allows file roundtrip bugs (such as line ending conversion or permissions issues) in the actual adapters to pass without verification.
- **Suggestion**: Add a test in `tests/test_amxx.py` that writes a CRLF file to a temporary directory, runs `adapter.set_plugin_status()`, and asserts `b'\r\n' in target.read_bytes()` and `b'\n' not in target.read_bytes().replace(b'\r\n', b'')`.

---

## 4. Verified Claims & Positive Observations

- **Safety Backups & Header Verification**:
  - `model_adapter.verify_goldsrc_mdl_header()` verified against valid IDST v10, truncated headers, corrupt magic (`NOPE`), and invalid versions (`ver 11`).
  - `restore_model_backup()` verified to restore exact original bytes, preserve `.bak` files idempotently, and safely reject corrupted `.bak` files without clobbering active models.
  - `restore_all_backups()` verified to batch restore all discovered backups.
- **Palette Preview Engine**:
  - In-memory HSV color math verified for saturation (0.0 producing grayscale R==G==B), contrast around mid-gray 128, and brightness.
  - Transparent key color index 255 is strictly preserved on masked textures (`flags & 0x40`).
  - `TexturePreviewCache` verified to avoid disk I/O on slider adjustments.
- **Headless Decoupling**:
  - Zero imports of `tkinter` or `customtkinter` across all modules in `tools/cs16_mod_hub/core/`.
- **Zero Emoji Compliance**:
  - Zero emojis found across `tools/cs16_mod_hub/` and `tests/`.

---

## 5. Caveats

- Testing of external skill scripts (`adjust_vibrance.py`, `inject_gloves.py`, etc.) relies on synthetic `.mdl` models because live game model files are kept untouched to preserve user game integrity.

---

## 6. Conclusion

The core backend adapters in `tools/cs16_mod_hub/core/` are well-engineered, perform genuine binary and color math computations, and meet safety backup and headless decoupling requirements. However, due to Python's universal newline translation in `Path.read_text()`, `amxx_adapter.py` silently strips Windows CRLF line endings from `plugins.ini` and rewrites them as Unix LF.

**Verdict**: **REQUEST_CHANGES**  
Worker M1 must update `amxx_adapter.py` to preserve raw line endings during read operations and ensure CRLF preservation is tested and verified.

---

## 7. Verification Method

To independently reproduce the finding and verify the fix:
1. Run the independent reproduction script:
   ```powershell
   python .agents/teamwork/reviewer_m1_2/verify_amxx_crlf.py
   ```
   - Before fix: Exits with code 1 and outputs `FAIL: Line endings corrupted! CRLF was converted to LF.`
   - After fix: Exits with code 0 and outputs `PASS: CRLF preserved!`
2. Execute the test suite:
   ```powershell
   python tests/run_all_tests.py
   ```
