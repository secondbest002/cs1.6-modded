# Handoff Report: Backend Skills Scripts Survey & Adapter Architecture

## 1. Observation

### 1.1 Investigated Target Scripts & Skill Documents
We directly inspected and verified all 5 backend skill scripts and documentation in `.agents/skills/`:
1. `.agents/skills/cs16-color-vibrance/scripts/adjust_vibrance.py` (241 lines, 8,873 bytes)
2. `.agents/skills/cs16-glove-injector/scripts/inject_gloves.py` (161 lines, 5,809 bytes)
3. `.agents/skills/cs16-sticker-fx/scripts/toggle_sticker_fx.py` (164 lines, 6,573 bytes)
4. `.agents/skills/cs16-skin-transfer/scripts/transfer_weapon_skin.py` (200 lines, 7,676 bytes)
5. `.agents/skills/cs16-pw-injector/scripts/bake_and_inject_pw.py` (198 lines, 7,173 bytes)
6. AMXX Configuration: `cstrike/addons/amxmodx/configs/plugins.ini` (52 lines, 2,269 bytes)
7. Competitive Configuration: `cstrike/addons/amxmodx/configs/csgo_competitive.cfg` (89 lines, 3,626 bytes)

### 1.2 Python Runtime Environment
Direct execution test via `run_command` verified:
- **Python**: 3.14.3 (tags/v3.14.3:323c59a, Feb 3 2026, 16:04:56) [MSC v.1944 64 bit (AMD64)]
- **Pillow (PIL)**: 12.2.0
- **numpy**: 2.4.6
- **customtkinter**: `ModuleNotFoundError: No module named 'customtkinter'`
  - Verifies Requirement R4: launcher batch script `CS16_Mod_Manager.bat` must include auto-installation check for `customtkinter` (e.g., `pip install customtkinter`).

### 1.3 Detailed Code Observations per Script

#### Script 1: `adjust_vibrance.py`
- **Location**: `.agents/skills/cs16-color-vibrance/scripts/adjust_vibrance.py`
- **Imports**: `argparse`, `colorsys`, `os`, `shutil`, `struct`, `sys`, `pickle` (line 7-13).
- **CLI Options**:
  - `-w, --weapon` (required, str): Weapon name or path (e.g. `ak47`, `v_ak47.mdl`).
  - `-t, --target` (default: `'weapon'`, choices: `['weapon', 'gloves', 'all']`): Group to adjust.
  - `-p, --preset` (choices: `['vivid', 'punchy', 'soft', 'grayscale']`): Built-in presets.
    - Vivid: Saturation x1.35 (+35%), Contrast x1.15 (+15%), Brightness x1.0 (lines 120-122).
    - Punchy: Saturation x1.55 (+55%), Contrast x1.25 (+25%), Brightness x1.0 (lines 123-125).
    - Soft: Saturation x0.85 (-15%), Contrast x0.95 (-5%), Brightness x1.0 (lines 126-128).
    - Grayscale: Saturation x0.0, Contrast x1.0, Brightness x1.0 (lines 129-130).
  - `--sat` (float): Custom saturation multiplier (e.g. 1.3).
  - `--contrast` (float): Custom contrast multiplier (e.g. 1.2).
  - `--brightness` (float): Custom brightness multiplier (e.g. 1.1).
  - `--reset` (bool flag): Resets targeted palettes to original factory state (lines 194-201).
  - `-d, --dir` (default: `'cstrike_hd/models'`, str): Model directory.
  - `--no-backup` (bool flag): Disables `.bak` creation.
- **Binary & Format Details**:
  - Header: checks magic `b'IDST'`, version `10` at offset 0 (`<4sI`, lines 144-146).
  - Textures count and offset: read from offset 180 (`<II`, line 148).
  - Texture entry: 80 bytes each (`<64sIIII`, line 163).
  - Palette offset: `idx + w * h`, size is 768 bytes (256 RGB triples).
  - Masked textures (`flags & 0x40`): color index 255 is kept untouched (lines 208, 215-219) to preserve transparency.
- **Backup Mechanism**:
  - `.bak` file: `bak_path = mdl_path + ".bak"`. Guarded by `if not os.path.exists(bak_path): shutil.copy2(mdl_path, bak_path)` (lines 177-180).
  - Factory palette cache: `pal_backup_file = mdl_path + ".original_palettes.dat"` saved via `pickle.dump(original_palettes, bf)` on first run (lines 139-175).
- **Exit & Logging**:
  - Uses `print()` to stdout/stderr. Calls `sys.exit(1)` on failure (lines 110, 232).

#### Script 2: `inject_gloves.py`
- **Location**: `.agents/skills/cs16-glove-injector/scripts/inject_gloves.py`
- **Imports**: `argparse`, `os`, `shutil`, `struct`, `sys` (lines 7-11).
- **CLI Options**:
  - `-t, --target` (required, str): Target model path or weapon name.
  - `-s, --source` (default: `'awp'`, str): Source model path or weapon name.
  - `-d, --dir` (default: `'cstrike_hd/models'`, str).
  - `--no-backup` (bool flag).
- **Matching & Injection**:
  - `classify_role(tname)` (lines 67-77): detects `left_glove`, `right_glove`, and `arm`.
  - Phase 1: Exact name matching for glove/arm keywords (`'sport'`, `'glove'`, `'hand'`, `'arm'`, `'sleeve'`, lines 102-106).
  - Phase 2: Role fallback matching (`left_glove` -> `left_glove`, etc., lines 109-120).
  - Size check: validates `s_info['size'] == t_info['size']` (lines 128-133).
  - In-place byte copy: `tgt_bytes[tgt_offset:tgt_offset + t_info['size']] = s_info['data']` (lines 149-152).
- **Backup Mechanism**:
  - Guarded `.bak` creation: `if not os.path.exists(bak_path): shutil.copy2(target_path, bak_path)` (lines 140-147).
- **Exit & Logging**:
  - Calls `sys.exit(1)` on missing files, no matches, or size mismatches (lines 87, 125, 137).

#### Script 3: `toggle_sticker_fx.py`
- **Location**: `.agents/skills/cs16-sticker-fx/scripts/toggle_sticker_fx.py`
- **Imports**: `argparse`, `os`, `shutil`, `struct`, `sys`, `numpy as np` (lines 7-12). Note: numpy is imported but unused.
- **CLI Options**:
  - `-w, --weapon` (required, str): Weapon name or path.
  - `-m, --mode` (required, choices: `['foil', 'chrome', 'matte', 'glow', 'hide', 'restore']`).
  - `-d, --dir` (default: `'cstrike_hd/models'`, str).
  - `--sticker-id` (default: `'all'`, str): Substring filter for sticker name or `'all'`.
  - `--no-backup` (bool flag).
- **Rendering Modes & Flag Encodings**:
  - `foil` / `chrome`: sets flag `<I` at `offset + 64` to `0x42` (STUDIO_NF_CHROME `0x02` | STUDIO_NF_MASKED `0x40`) (lines 118-123).
  - `matte`: sets flag to `0x40` (STUDIO_NF_MASKED) (lines 124-128).
  - `glow`: sets flag to `0x60` (STUDIO_NF_ADDITIVE `0x20` | STUDIO_NF_MASKED `0x40`) (lines 130-135).
  - `hide`: saves original pixels to `<dir>/.sticker_backups/<base_file_key>_<sticker_name>.raw`, fills pixel slice with `b'\xFF'` (transparent index in masked textures), sets flags to `0x40` (lines 136-147).
  - `restore`: reads `.raw` backup, restores original pixels, sets flags to `0x40` (lines 148-156).
- **Backup Mechanism**:
  - Guarded `.bak` creation: `if not os.path.exists(bak_path): shutil.copy2(mdl_path, bak_path)` (lines 66-71).
  - Raw pixel backups stored in `.sticker_backups/`.
- **Exit & Logging**:
  - Calls `sys.exit(1)` on error (lines 61, 103).

#### Script 4: `transfer_weapon_skin.py`
- **Location**: `.agents/skills/cs16-skin-transfer/scripts/transfer_weapon_skin.py`
- **Imports**: `argparse`, `os`, `shutil`, `struct`, `sys` (lines 8-12).
- **CLI Options**:
  - `-t, --target` (required, str): Active weapon/model path.
  - `-s, --source` (required, str): Donor model path (e.g. `v_ak47_usethis.mdl`).
  - `-d, --dir` (default: `'cstrike_hd/models'`, str).
  - `--sync-pw` (bool flag): Also injects skin into matching `p_*.mdl` and `w_*.mdl`.
  - `--no-backup` (bool flag).
- **Texture Transfer Mechanics**:
  - Filters textures with `is_weapon_texture(tname)` (excludes gloves, arms, sleeves, stickers, StatTrak, decals, lines 76-79).
  - Matches textures by name and size, falling back to first size-compatible match (lines 144-163).
  - Injects raw texture bytes: `tgt_bytes[matched_tgt['offset']:matched_tgt['offset'] + matched_tgt['size']] = matched_src['data']` (line 177).
  - Leaves animations, skeleton bones, sequence events, gloves, and stickers 100% untouched.
  - If `--sync-pw`: derives weapon root name (`wep_core = base_name[2:-4]`) and calls `replace_texture_in_file` on `p_{wep_core}.mdl` and `w_{wep_core}.mdl` (lines 183-195).
- **Backup Mechanism**:
  - Viewmodel: `if not os.path.exists(bak_path): shutil.copy2(tgt_path, bak_path)` (lines 171-176).
  - `p_` and `w_` models: guarded `.bak` creation in `replace_texture_in_file` (lines 84-88).

#### Script 5: `bake_and_inject_pw.py`
- **Location**: `.agents/skills/cs16-pw-injector/scripts/bake_and_inject_pw.py`
- **Imports**: `argparse`, `os`, `shutil`, `struct`, `sys`, `numpy as np`, `from PIL import Image` (lines 7-13).
- **CLI Options**:
  - `-w, --weapon` (str): Weapon base name (e.g. `deagle`, `ak47`).
  - `--v-model`, `--p-model`, `--w-model` (str): Explicit model paths.
  - `-d, --dir` (default: `'cstrike_hd/models'`, str).
  - `--no-backup` (bool flag).
- **Baking & Quantization Logic**:
  - Extracts base weapon texture from viewmodel (`v_*.mdl`).
  - Converts to PIL RGBA image: `Image.frombytes('P', (w, h), base_tex['pixels'])` + `putpalette` -> `convert('RGBA')` (lines 97-99).
  - Searches for decals/stickers: overlay decals with matching dimensions where `'decal' in tname or (t['flags'] & 0x40) != 0` (lines 101-116).
  - Converts transparent color (index 255) to alpha=0 using numpy array mask: `dec_rgba[pixels_arr == 255, 3] = 0` (lines 111-112).
  - Alpha-composites layers: `composite = Image.alpha_composite(composite, dec_layer)` (line 115).
  - Quantizes back to GoldSrc 256-color palette: `quantized = final_rgb.quantize(colors=256, method=Image.Resampling.LANCZOS)` (line 119).
  - Packs into GoldSrc raw format: `bytes(pixels) + bytes(pal)` (line 126).
  - Injects into `p_*.mdl` and `w_*.mdl` (lines 189-192).
- **Backup Mechanism**:
  - Guarded `.bak` creation on each target model (lines 133-138).

---

## 2. Logic Chain

1. **Isolation Necessity**:
   - *Observation*: Every backend script calls `sys.exit(1)` when any error condition is met (e.g. model not found, size mismatch, missing textures).
   - *Deduction*: Calling `main()` directly from within CustomTkinter's main loop would terminate the entire GUI application abruptly on any error.
   - *Inference*: Adapters in `tools/cs16_mod_hub/core/` must either:
     a) Invoke the scripts via `subprocess.Popen` / `subprocess.run` (providing 100% process isolation, capturing stdout/stderr line-by-line for live terminal logging, and preventing GUI termination), OR
     b) Re-implement or cleanly wrap core helper functions with Python exception handling, reserving CLI execution for operations that write to disk.

2. **No Code Modification Constraint**:
   - *Observation*: The user instructions state: *"wrap and orchestrate the existing verified scripts from .agents/skills/ without code breakage"*.
   - *Deduction*: We must NOT modify any file inside `.agents/skills/`.
   - *Inference*: Adapters in `tools/cs16_mod_hub/core/` will act as a client layer over `.agents/skills/`, executing them using Python subprocess calls and dynamic path discovery.

3. **Live Palette Preview Requirements**:
   - *Observation*: Requirement R2 and Acceptance Criteria demand a *"real-time live BMP preview thumbnail using Pillow before and after applying vibrance adjustments"* in the Color & Vibrance Tuner tab.
   - *Observation*: The backend script `adjust_vibrance.py` modifies the MDL file directly on disk, which would be too slow, risky, and would clutter backups if executed on every slider tick.
   - *Deduction*: Sliders need an instant, non-destructive, in-memory preview.
   - *Inference*: We need `palette_preview.py` in `tools/cs16_mod_hub/core/` that directly reads the GoldSrc MDL binary header, extracts the active texture's pixel buffer and 768-byte palette, applies the HSV transformation in-memory via Pillow (`Image.putpalette(...)`), and returns a `PIL.Image` / `CTkImage` in under 2ms.

4. **Safety & Backup Strategy**:
   - *Observation*: All 5 scripts use `if not os.path.exists(bak_path): shutil.copy2(target, bak_path)`.
   - *Deduction*: The `.bak` files preserve the original, pristine state of the model before any modification took place.
   - *Inference*: The "Backup & Safety Center" tab can safely restore models simply by enumerating all `.bak` files in `cstrike_hd/models/` and `cstrike/models/`, copying `.bak` over `.mdl`, and cleaning up `.original_palettes.dat` and `.sticker_backups/` if desired.

5. **AMXX Configuration Preservation**:
   - *Observation*: `plugins.ini` contains section comments, disabled plugins starting with `;`, and inline comments (e.g. `team_weapon_skins.amxx ; Per-team weapon skin switcher`).
   - *Observation*: `csgo_competitive.cfg` contains CVARs formatted as `<cvar_name> <value> // <comments>`.
   - *Deduction*: The parser must never rewrite or reformat the file destructively; it must toggle the leading `;` on targeted plugin filenames while preserving whitespace and comments.

---

## 3. Proposed Core Adapter Architecture (`tools/cs16_mod_hub/core/`)

To fulfill all requirements cleanly and modularly, the following core adapters should be constructed in `tools/cs16_mod_hub/core/`:

```
tools/cs16_mod_hub/
├── __init__.py
├── main.py                     # CustomTkinter GUI entry point
├── assets/                     # Icons, glyphs, palettes
└── core/
    ├── __init__.py
    ├── common.py               # Path resolver, AdapterResult dataclass, subprocess streaming runner
    ├── model_adapter.py        # Skin transfer, glove injection, P/W injection, backup discovery/restore
    ├── vibrance_adapter.py     # Vibrance presets, sliders runner, palette reset
    ├── sticker_adapter.py      # Sticker effect toggling (Foil, Matte, Glow, Hide, Restore)
    ├── palette_preview.py      # Non-destructive in-memory texture extractor & live Pillow preview
    └── amxx_adapter.py         # plugins.ini parser/toggler & csgo_competitive.cfg editor
```

### 3.1 Common Architecture & Base Runner (`common.py`)

```python
from dataclasses import dataclass
from pathlib import Path
import subprocess
import sys
from typing import Callable, List, Optional

@dataclass
class AdapterResult:
    success: bool
    message: str
    stdout: str = ""
    stderr: str = ""
    returncode: int = 0

def get_project_root() -> Path:
    # Resolves root directory: d:\Games\Counter-Strike\Counter-Strike 1.6 Original
    return Path(__file__).resolve().parents[3]

def run_script_streaming(
    script_relative_path: str,
    args: List[str],
    log_callback: Optional[Callable[[str], None]] = None
) -> AdapterResult:
    root = get_project_root()
    script_path = root / script_relative_path
    if not script_path.is_file():
        return AdapterResult(False, f"Script not found: {script_path}", returncode=-1)

    cmd = [sys.executable, str(script_path)] + args
    stdout_lines = []
    stderr_lines = []

    try:
        proc = subprocess.Popen(
            cmd,
            cwd=str(root),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
            universal_newlines=True
        )
        if proc.stdout:
            for line in proc.stdout:
                stdout_lines.append(line)
                if log_callback:
                    log_callback(line.rstrip('\r\n'))
        _, stderr_text = proc.communicate()
        if stderr_text:
            stderr_lines.append(stderr_text)
            if log_callback:
                log_callback(stderr_text.rstrip('\r\n'))

        success = (proc.returncode == 0)
        full_stdout = "".join(stdout_lines)
        full_stderr = "".join(stderr_lines)
        msg = "Operation completed successfully." if success else "Operation failed with errors."
        return AdapterResult(success, msg, full_stdout, full_stderr, proc.returncode)
    except Exception as e:
        return AdapterResult(False, str(e), returncode=-1)
```

### 3.2 `model_adapter.py` Specification
- **Responsibilities**:
  - Model Skin Transfer: wraps `.agents/skills/cs16-skin-transfer/scripts/transfer_weapon_skin.py`.
  - Glove Injection: wraps `.agents/skills/cs16-glove-injector/scripts/inject_gloves.py`.
  - P/W Sync & Decal Baking: wraps `.agents/skills/cs16-pw-injector/scripts/bake_and_inject_pw.py`.
  - Backup Management: enumerates `.bak` files, executes one-click restore.
  - Weapon Scanner: enumerates installed viewmodels (`v_*.mdl`) and donor models (`v_*_usethis*.mdl`).
- **Key Method Signatures**:
  ```python
  def transfer_skin(source: str, target: str, dir_path: str = "cstrike_hd/models", sync_pw: bool = False, no_backup: bool = False, log_callback: Optional[Callable[[str], None]] = None) -> AdapterResult
  def inject_gloves(target: str, source: str = "awp", dir_path: str = "cstrike_hd/models", no_backup: bool = False, log_callback: Optional[Callable[[str], None]] = None) -> AdapterResult
  def inject_pw(weapon: Optional[str] = None, v_model: Optional[str] = None, p_model: Optional[str] = None, w_model: Optional[str] = None, dir_path: str = "cstrike_hd/models", no_backup: bool = False, log_callback: Optional[Callable[[str], None]] = None) -> AdapterResult
  def list_viewmodels(dir_path: str = "cstrike_hd/models") -> List[str]
  def list_donor_models(search_dirs: Optional[List[str]] = None) -> List[str]
  def list_backups(dir_path: str = "cstrike_hd/models") -> List[dict]
  def restore_model_backup(model_name_or_path: str) -> AdapterResult
  ```

### 3.3 `vibrance_adapter.py` Specification
- **Responsibilities**:
  - Wraps `.agents/skills/cs16-color-vibrance/scripts/adjust_vibrance.py`.
  - Maps UI presets (`'vivid'`, `'punchy'`, `'soft'`, `'grayscale'`) and custom slider values.
  - Supports `--reset` to restore original factory palette from `.original_palettes.dat`.
- **Key Method Signatures**:
  ```python
  def apply_vibrance(weapon: str, target: str = "weapon", preset: Optional[str] = None, sat: Optional[float] = None, contrast: Optional[float] = None, brightness: Optional[float] = None, reset: bool = False, dir_path: str = "cstrike_hd/models", no_backup: bool = False, log_callback: Optional[Callable[[str], None]] = None) -> AdapterResult
  def reset_vibrance(weapon: str, target: str = "weapon", dir_path: str = "cstrike_hd/models", log_callback: Optional[Callable[[str], None]] = None) -> AdapterResult
  ```

### 3.4 `sticker_adapter.py` Specification
- **Responsibilities**:
  - Wraps `.agents/skills/cs16-sticker-fx/scripts/toggle_sticker_fx.py`.
  - Translates user intent into visual effect modes: `foil` (0x42), `matte` (0x40), `glow` (0x60), `hide`, `restore`.
  - Inspects model textures to find all sticker slots (`sticker1`, `sticker2`, `sticker3`, `sticker4`, `decal`) to populate the UI dropdown.
- **Key Method Signatures**:
  ```python
  def set_sticker_fx(weapon: str, mode: str, sticker_id: str = "all", dir_path: str = "cstrike_hd/models", no_backup: bool = False, log_callback: Optional[Callable[[str], None]] = None) -> AdapterResult
  def scan_model_stickers(mdl_path_or_name: str, dir_path: str = "cstrike_hd/models") -> List[dict]
  ```

### 3.5 `palette_preview.py` Specification
- **Responsibilities**:
  - Direct GoldSrc MDL texture extraction into memory without touching disk or altering files.
  - Instant Pillow preview image generation for the Color & Vibrance Tuner tab.
  - High-performance HSV recalculation for all 256 colors (< 2ms) for buttery smooth 60 FPS slider dragging.
- **Key Method Signatures**:
  ```python
  def extract_preview_texture(mdl_path: str, target_group: str = "weapon") -> tuple[Image.Image, bytes, str, bool]
  # Returns: (base_PIL_Image, original_768_bytes_palette, texture_name, is_masked)
  def compute_adjusted_preview(base_img: Image.Image, base_palette: bytes, sat: float, contrast: float, brightness: float, is_masked: bool = False, target_size: tuple[int, int] = (256, 256)) -> Image.Image
  ```

### 3.6 `amxx_adapter.py` Specification
- **Responsibilities**:
  - Safe parsing and toggling of AMX Mod X plugins in `cstrike/addons/amxmodx/configs/plugins.ini`.
  - Parsing and updating CVAR values in `cstrike/addons/amxmodx/configs/csgo_competitive.cfg`.
  - Line-preserving modification: preserves empty lines, comments, and structure.
- **Target Plugins Supported**:
  1. `team_weapon_skins.amxx` (Per-team weapon skin switcher)
  2. `csgo_knife_sound_manager.amxx` (Dynamic knife sound engine)
  3. `csgo_m4_loadout.amxx` (M4A4 & M4A1-S Loadout Switcher)
  4. `csgo_usps_silencer.amxx` (USP-S Permanent Silencer Lock)
  5. `csgo_competitive.amxx` (CS:GO Competitive Match Mod)
  6. `csgo_ammo_refill.amxx` (CS:GO Auto Ammo & Round Refill)
  7. `bot_savage_ai.amxx` (Bot Savage & Predator AI Engine)
- **Competitive CVARs Supported**:
  - `amx_csgo_mode` (1 or 0)
  - `amx_csgo_maxrounds` (12 for MR12, 15 for MR15)
  - `amx_csgo_kniferound` (1 or 0)
  - `amx_csgo_warmup` (1 or 0)
  - `amx_csgo_timeouts` (int)
  - `amx_csgo_timeout_duration` (int)
  - `amx_csgo_ot_money` (int)
  - `amx_csgo_bot_autoready` (1 or 0)
  - `amx_csgo_lossbonus` (1 or 0)
  - `amx_csgo_hud_style` (1 or 0)
  - `amx_csgo_mvp_card` (1 or 0)
  - `amx_csgo_c4_timer` (1 or 0)
  - `amx_csgo_screenfade` (1 or 0)
  - `amx_csgo_dmg_card` (1 or 0)

---

## 4. Caveats
- No code in `.agents/skills/` was modified during this investigation.
- `customtkinter` is not currently installed in the global Python environment. The launcher batch script `CS16_Mod_Manager.bat` must perform `pip install customtkinter` prior to starting `main.py`.
- Windows PowerShell terminal profile outputs benign XML/Terminal-Icons warnings on process launch. Subprocess executions should ignore stderr warnings unless the process exit code is non-zero.

---

## 5. Conclusion
All 5 existing backend skill scripts are verified, stable, and ready to be wrapped without any modifications to their source code. The adapter architecture detailed above provides safe process isolation, streaming log capture for the GUI console, real-time in-memory palette preview with Pillow, non-destructive safety backups, and clean AMXX configuration editing.

---

## 6. Verification Method

To independently verify these findings:

1. **Verify script importability**:
   ```powershell
   python -c "import sys; sys.path.insert(0, '.agents/skills/cs16-color-vibrance/scripts'); import adjust_vibrance; sys.path.insert(0, '.agents/skills/cs16-glove-injector/scripts'); import inject_gloves; sys.path.insert(0, '.agents/skills/cs16-sticker-fx/scripts'); import toggle_sticker_fx; sys.path.insert(0, '.agents/skills/cs16-skin-transfer/scripts'); import transfer_weapon_skin; sys.path.insert(0, '.agents/skills/cs16-pw-injector/scripts'); import bake_and_inject_pw; print('ALL 5 SCRIPTS IMPORT CLEANLY')"
   ```

2. **Verify CLI help interfaces**:
   ```powershell
   python .agents/skills/cs16-color-vibrance/scripts/adjust_vibrance.py --help
   python .agents/skills/cs16-glove-injector/scripts/inject_gloves.py --help
   python .agents/skills/cs16-sticker-fx/scripts/toggle_sticker_fx.py --help
   python .agents/skills/cs16-skin-transfer/scripts/transfer_weapon_skin.py --help
   python .agents/skills/cs16-pw-injector/scripts/bake_and_inject_pw.py --help
   ```

3. **Verify files inspected**:
   - `cstrike/addons/amxmodx/configs/plugins.ini`
   - `cstrike/addons/amxmodx/configs/csgo_competitive.cfg`
