# Handoff Report: Specification & Test Strategy for `common.py` and `model_adapter.py`

**Working Directory**: `d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\explorer_m1_1`  
**Target Milestone**: M1 (Backend Core Adapters & Safety Engine)  
**Target Components**:
- `tools/cs16_mod_hub/core/common.py`
- `tools/cs16_mod_hub/core/model_adapter.py`
- `tests/test_adapters.py` & `tests/test_backups.py`

---

## 1. Observation

### 1.1 Script Analysis & CLI Arguments
We conducted a static analysis of the three underlying skill scripts located in `.agents/skills/`:

1. **`transfer_weapon_skin.py`** (`.agents/skills/cs16-skin-transfer/scripts/transfer_weapon_skin.py` - 200 lines):
   - **CLI Parameters**:
     - `-t, --target` (required, str): Target weapon or model path (e.g., `ak47`, `v_ak47.mdl`).
     - `-s, --source` (required, str): Source donor weapon or model path (e.g., `v_ak47_usethis.mdl`).
     - `-d, --dir` (default: `'cstrike_hd/models'`, str): Base directory for resolving models.
     - `--sync-pw` (flag, bool): Synchronizes skin transfer into corresponding `p_{core}.mdl` and `w_{core}.mdl`.
     - `--no-backup` (flag, bool): Skips creating `.bak` files.
   - **Error Behavior**: Calls `sys.exit(1)` with error messages printed to `sys.stderr` when paths cannot be resolved, headers are invalid, or size compatibility fails (lines 118, 139, 166).
   - **Success Behavior**: Exits with code 0 and prints `"Skin transfer complete!"` (line 196).

2. **`inject_gloves.py`** (`.agents/skills/cs16-glove-injector/scripts/inject_gloves.py` - 161 lines):
   - **CLI Parameters**:
     - `-t, --target` (required, str): Target viewmodel path or weapon name (e.g., `deagle` or `v_deagle.mdl`).
     - `-s, --source` (default: `'awp'`, str): Source viewmodel path or weapon name containing gloves.
     - `-d, --dir` (default: `'cstrike_hd/models'`, str): Base directory for resolving models.
     - `--no-backup` (flag, bool): Skips creating `.bak` files.
   - **Error Behavior**: Calls `sys.exit(1)` with messages on `sys.stderr` if files are missing, no matching glove/arm textures are identified, or texture sizes mismatch (lines 87, 125, 137).
   - **Success Behavior**: Exits with code 0 and prints `"Done! Updated target model: ..."` (line 157).

3. **`bake_and_inject_pw.py`** (`.agents/skills/cs16-pw-injector/scripts/bake_and_inject_pw.py` - 198 lines):
   - **CLI Parameters**:
     - `-w, --weapon` (optional, str): Weapon base name (e.g., `ak47`, `deagle`).
     - `--v-model` (optional, str): Explicit path to viewmodel (`v_*.mdl`).
     - `--p-model` (optional, str): Explicit path to player model (`p_*.mdl`).
     - `--w-model` (optional, str): Explicit path to world model (`w_*.mdl`).
     - `-d, --dir` (default: `'cstrike_hd/models'`, str): Base directory.
     - `--no-backup` (flag, bool): Skips creating `.bak` files.
   - **Error Behavior**: Calls `sys.exit(1)` on resolution errors (line 169) or raises `ValueError` if weapon textures are missing.
   - **Success Behavior**: Exits with code 0 and prints `"Done! P & W model injection complete."` (line 194).

### 1.2 Binary Header Specification
- **GoldSrc StudioModel Header**:
  - Offset 0..3: Magic bytes `b'IDST'` (ASCII "IDST").
  - Offset 4..7: 32-bit little-endian integer version `10` (`<I`).
  - Offset 180..183: `numtextures` (int32).
  - Offset 184..187: `textureindex` (int32 offset).
- Each texture entry is 80 bytes (`<64sIIII`: name[64], flags, width, height, data_offset).
- Palettes are 768 bytes (256 RGB triples) immediately following texture pixel indices (`width * height`).

### 1.3 Filesystem Asset & Backup Inventory
- **Model Directories**:
  - `cstrike/models/`: 31 active `v_*.mdl` files, 31 `p_*.mdl`, 32 `w_*.mdl`.
  - `cstrike/models/custom_skins/ct/`: 31 custom CT viewmodels, 31 `.bak` files.
  - `cstrike/models/custom_skins/t/`: 30 custom T viewmodels, 3 `.bak` files.
  - `cstrike_hd/models/`: 29 viewmodels, 10 `.bak` files.
  - `CSGO Weapon Pack - Update #4/cstrike/models/`: 29 `v_*.mdl` files, 29 in `alt/` folder.
- **Backup Inventory**:
  - 45 total `.bak` files currently exist in the game installation.
  - 43 are `.mdl.bak` files; 2 are non-model backups (`cstrike/liblist.gam.bak` and `cstrike/sound/.../knife_deploy.wav.bak`).
  - Model backup scanning must strictly distinguish `.mdl.bak` from non-model `.bak` files.

---

## 2. Logic Chain

1. **Subprocess Isolation Requirement**:
   - *Premise*: All three underlying skill scripts invoke `sys.exit(1)` upon encounters with invalid paths, missing textures, or dimension mismatches.
   - *Inference*: Importing and invoking these scripts directly in the CustomTkinter GUI thread would terminate the entire GUI process unexpectedly.
   - *Conclusion*: Process isolation via `subprocess.Popen` in `common.py` is mandatory.

2. **Real-time GUI Console Streaming**:
   - *Premise*: The GUI contains a live streaming log console (`log_console.py`).
   - *Premise*: Standard Python child processes buffer stdout and stderr when not connected to a TTY terminal.
   - *Premise*: Reading stdout in a single blocking loop while stderr fills up can cause pipe buffer deadlocks on Windows.
   - *Conclusion*: `common.py` must:
     a) Launch Python with `-u` and set `PYTHONUNBUFFERED="1"` and `PYTHONIOENCODING="utf-8"`.
     b) Use dual reader threads (`t_stdout` and `t_stderr`) to concurrently drain pipes and invoke `log_callback(line)`.
     c) Set `creationflags=subprocess.CREATE_NO_WINDOW` on Windows to suppress flashing black command prompt windows.

3. **Backup Safety and Non-Destructive Operation**:
   - *Premise*: The existing scripts never overwrite an existing `.bak` file (`if not os.path.exists(bak_path): shutil.copy2(...)`).
   - *Premise*: Users might have corrupt or partial `.bak` files.
   - *Conclusion*: `restore_model_backup` and `restore_all_backups` must:
     a) Validate the 8-byte GoldSrc header (`magic == b'IDST' and ver == 10`) before copying `.bak` over active `.mdl`.
     b) Never delete the `.bak` file during restore, preserving safety rollbacks indefinitely.
     c) Filter out non-model backups (like `.gam.bak` or `.wav.bak`).

---

## 3. Caveats

1. **Subprocess Concurrency**:
   - CustomTkinter UI widgets are not strictly thread-safe. If `log_callback` directly mutates CTk widgets from background reader threads, the UI layer must dispatch via `widget.after()` or a thread-safe queue. The callback contract in `common.py` is documented as string-line consumer.
2. **Path Case-Sensitivity**:
   - Although Windows NTFS is case-insensitive, CS 1.6 engine paths in memory and AMX Mod X are case-sensitive. All adapter functions must maintain consistent lowercased model names (`v_*.mdl`).
3. **No Modification to Skills**:
   - As per project constraints, files in `.agents/skills/` remain completely untouched. All parameter mapping and error handling are encapsulated inside `model_adapter.py`.

---

## 4. Conclusion & Implementation Specifications

### 4.1 Specification: `tools/cs16_mod_hub/core/common.py`

```python
"""
tools/cs16_mod_hub/core/common.py
Core execution utilities, project root resolution, and subprocess streaming runner.
"""

from dataclasses import dataclass
import os
from pathlib import Path
import subprocess
import sys
import threading
from typing import Callable, List, Optional, Union

@dataclass
class AdapterResult:
    """Standardized execution result returned by all Mod Hub adapters."""
    success: bool
    message: str
    stdout: str = ""
    stderr: str = ""
    returncode: int = 0

    def __bool__(self) -> bool:
        """Allow direct boolean evaluation: if result: ..."""
        return self.success

    @property
    def output(self) -> str:
        """Return primary output text (stdout if populated, else stderr)."""
        return self.stdout if self.stdout.strip() else self.stderr


def get_project_root() -> Path:
    """
    Resolves the Counter-Strike 1.6 game root directory.
    Hierarchy:
      tools/cs16_mod_hub/core/common.py -> parents[3] == Project Root
    Supports CS16_PROJECT_ROOT environment override and upward directory search.
    """
    env_override = os.environ.get("CS16_PROJECT_ROOT")
    if env_override:
        p = Path(env_override).resolve()
        if p.is_dir():
            return p

    # Standard relative location from tools/cs16_mod_hub/core/common.py
    try:
        candidate = Path(__file__).resolve().parents[3]
        if (candidate / "cstrike").is_dir():
            return candidate
    except IndexError:
        pass

    # Fallback: search upward for 'cstrike' marker directory
    curr = Path(__file__).resolve().parent
    for parent in [curr] + list(curr.parents):
        if (parent / "cstrike").is_dir():
            return parent

    return Path.cwd().resolve()


def run_script_streaming(
    script_rel_path: Union[str, Path],
    args: List[str],
    log_callback: Optional[Callable[[str], None]] = None,
    cwd: Optional[Union[str, Path]] = None,
    timeout: Optional[float] = 60.0
) -> AdapterResult:
    """
    Executes a Python script in a separate process, capturing stdout and stderr
    concurrently via dual reader threads, streaming lines to log_callback in real time.

    Args:
        script_rel_path: Script path relative to project root (e.g. '.agents/skills/...').
        args: Command-line arguments to pass to the script.
        log_callback: Optional callable receiving each line of output as str.
        cwd: Optional working directory (defaults to get_project_root()).
        timeout: Process timeout in seconds (default 60s).

    Returns:
        AdapterResult containing success status, summary message, stdout, stderr, returncode.
    """
    root = get_project_root()
    work_dir = Path(cwd).resolve() if cwd else root
    script_path = (root / script_rel_path).resolve()

    if not script_path.is_file():
        err_msg = f"Target script not found: {script_path}"
        if log_callback:
            log_callback(f"[ERROR] {err_msg}")
        return AdapterResult(
            success=False,
            message=err_msg,
            stdout="",
            stderr=err_msg,
            returncode=-1
        )

    # Windows GUI no-window flag
    creationflags = 0
    if sys.platform == "win32":
        creationflags = getattr(subprocess, "CREATE_NO_WINDOW", 0x08000000)

    # Ensure unbuffered execution and UTF-8 encoding
    env = os.environ.copy()
    env["PYTHONUNBUFFERED"] = "1"
    env["PYTHONIOENCODING"] = "utf-8"

    cmd = [sys.executable, "-u", str(script_path)] + [str(a) for a in args]

    stdout_lines: List[str] = []
    stderr_lines: List[str] = []

    try:
        proc = subprocess.Popen(
            cmd,
            cwd=str(work_dir),
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
            bufsize=1,
            creationflags=creationflags
        )

        def _drain_stream(stream, accumulator: List[str]):
            try:
                for line in iter(stream.readline, ""):
                    accumulator.append(line)
                    if log_callback:
                        log_callback(line.rstrip("\r\n"))
            finally:
                stream.close()

        t_out = threading.Thread(target=_drain_stream, args=(proc.stdout, stdout_lines), daemon=True)
        t_err = threading.Thread(target=_drain_stream, args=(proc.stderr, stderr_lines), daemon=True)
        t_out.start()
        t_err.start()

        proc.wait(timeout=timeout)
        t_out.join(timeout=2.0)
        t_err.join(timeout=2.0)

        full_stdout = "".join(stdout_lines)
        full_stderr = "".join(stderr_lines)
        success = (proc.returncode == 0)

        if success:
            # Extract last non-empty line as concise summary if available
            out_stripped = [l.strip() for l in stdout_lines if l.strip()]
            message = out_stripped[-1] if out_stripped else "Operation completed successfully."
        else:
            err_stripped = [l.strip() for l in stderr_lines if l.strip()]
            out_stripped = [l.strip() for l in stdout_lines if l.strip()]
            if err_stripped:
                message = err_stripped[-1]
            elif out_stripped:
                message = out_stripped[-1]
            else:
                message = f"Process exited with error code {proc.returncode}."

        return AdapterResult(
            success=success,
            message=message,
            stdout=full_stdout,
            stderr=full_stderr,
            returncode=proc.returncode
        )

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
            returncode=-1
        )
    except Exception as exc:
        msg = f"Subprocess launch exception: {exc}"
        if log_callback:
            log_callback(f"[ERROR] {msg}")
        return AdapterResult(
            success=False,
            message=msg,
            stdout="".join(stdout_lines),
            stderr=str(exc),
            returncode=-1
        )
```

---

### 4.2 Specification: `tools/cs16_mod_hub/core/model_adapter.py`

```python
"""
tools/cs16_mod_hub/core/model_adapter.py
Model skin transfer, glove injection, player/world synchronization,
model discovery, and non-destructive GoldSrc backup management.
"""

from datetime import datetime
import os
from pathlib import Path
import shutil
import struct
from typing import Callable, Dict, List, Optional, Union

from .common import AdapterResult, get_project_root, run_script_streaming

# Relative script paths inside repository
SKIN_TRANSFER_SCRIPT = ".agents/skills/cs16-skin-transfer/scripts/transfer_weapon_skin.py"
GLOVE_INJECTOR_SCRIPT = ".agents/skills/cs16-glove-injector/scripts/inject_gloves.py"
PW_INJECTOR_SCRIPT = ".agents/skills/cs16-pw-injector/scripts/bake_and_inject_pw.py"

# Default search directories for models and donor packs
DEFAULT_DONOR_DIRS = [
    "CSGO Weapon Pack - Update #4/cstrike/models",
    "CSGO Weapon Pack - Update #4/cstrike/models/alt",
    "cstrike/models/custom_skins/ct",
    "cstrike/models/custom_skins/t",
    "cstrike/models/csgo_skins/ct",
    "cstrike/models/csgo_skins/t",
    "cstrike_hd/models",
]

DEFAULT_BACKUP_DIRS = [
    "cstrike/models",
    "cstrike_hd/models",
]


def verify_goldsrc_mdl_header(file_path: Union[str, Path]) -> bool:
    """
    Inspects binary header of a file. Returns True if magic is b'IDST' and version is 10.
    """
    path = Path(file_path)
    if not path.is_file() or path.stat().st_size < 8:
        return False
    try:
        with open(path, "rb") as f:
            magic, ver = struct.unpack("<4sI", f.read(8))
            return magic == b"IDST" and ver == 10
    except Exception:
        return False


def transfer_skin(
    source: str,
    target: str,
    dir_path: str = "cstrike/models",
    sync_pw: bool = False,
    no_backup: bool = False,
    log_callback: Optional[Callable[[str], None]] = None
) -> AdapterResult:
    """
    Wraps transfer_weapon_skin.py to transfer weapon body skin from donor to target model,
    preserving animations, gloves, StatTrak, and stickers.
    """
    if not source or not target:
        return AdapterResult(False, "Both source and target models must be specified.", returncode=-1)

    args = [
        "-s", str(source),
        "-t", str(target),
        "-d", str(dir_path)
    ]
    if sync_pw:
        args.append("--sync-pw")
    if no_backup:
        args.append("--no-backup")

    return run_script_streaming(SKIN_TRANSFER_SCRIPT, args, log_callback=log_callback)


def inject_gloves(
    target: str,
    source: str = "awp",
    dir_path: str = "cstrike/models",
    no_backup: bool = False,
    log_callback: Optional[Callable[[str], None]] = None
) -> AdapterResult:
    """
    Wraps inject_gloves.py to inject glove/arm textures from donor model into target viewmodel.
    """
    if not target:
        return AdapterResult(False, "Target viewmodel must be specified.", returncode=-1)

    args = [
        "-t", str(target),
        "-s", str(source),
        "-d", str(dir_path)
    ]
    if no_backup:
        args.append("--no-backup")

    return run_script_streaming(GLOVE_INJECTOR_SCRIPT, args, log_callback=log_callback)


def inject_pw(
    weapon: Optional[str] = None,
    v_model: Optional[str] = None,
    p_model: Optional[str] = None,
    w_model: Optional[str] = None,
    dir_path: str = "cstrike/models",
    no_backup: bool = False,
    log_callback: Optional[Callable[[str], None]] = None
) -> AdapterResult:
    """
    Wraps bake_and_inject_pw.py to bake decals and inject skins into player (p_) and world (w_) models.
    """
    if not weapon and not v_model:
        return AdapterResult(
            False,
            "Either 'weapon' or 'v_model' must be provided for P/W injection.",
            returncode=-1
        )

    args = ["-d", str(dir_path)]
    if weapon:
        args.extend(["-w", str(weapon)])
    if v_model:
        args.extend(["--v-model", str(v_model)])
    if p_model:
        args.extend(["--p-model", str(p_model)])
    if w_model:
        args.extend(["--w-model", str(w_model)])
    if no_backup:
        args.append("--no-backup")

    return run_script_streaming(PW_INJECTOR_SCRIPT, args, log_callback=log_callback)


def list_viewmodels(dir_path: str = "cstrike/models") -> List[str]:
    """
    Lists active weapon viewmodels (v_*.mdl) in the given directory.
    Returns sorted list of filenames (e.g. ['v_ak47.mdl', 'v_m4a1.mdl']).
    """
    root = get_project_root()
    p = Path(dir_path)
    target_dir = p if p.is_absolute() else (root / p)

    if not target_dir.is_dir():
        return []

    models: List[str] = []
    for entry in target_dir.iterdir():
        if entry.is_file():
            name_lower = entry.name.lower()
            if name_lower.startswith("v_") and name_lower.endswith(".mdl") and not name_lower.endswith(".bak"):
                models.append(entry.name)

    return sorted(models)


def list_donor_models(search_dirs: Optional[List[str]] = None) -> List[str]:
    """
    Scans donor collections and custom skin folders for available donor viewmodels.
    Returns sorted list of paths relative to project root with forward slashes.
    """
    root = get_project_root()
    dirs_to_search = search_dirs if search_dirs is not None else DEFAULT_DONOR_DIRS

    discovered: List[str] = []
    for sdir in dirs_to_search:
        p = Path(sdir)
        abs_dir = p if p.is_absolute() else (root / p)
        if not abs_dir.is_dir():
            continue

        for entry in abs_dir.iterdir():
            if entry.is_file():
                name_lower = entry.name.lower()
                if name_lower.startswith("v_") and name_lower.endswith(".mdl") and not name_lower.endswith(".bak"):
                    try:
                        rel = entry.relative_to(root).as_posix()
                    except ValueError:
                        rel = entry.as_posix()
                    discovered.append(rel)

    return sorted(list(dict.fromkeys(discovered)))


def list_backups(search_dirs: Optional[List[str]] = None) -> List[dict]:
    """
    Recursively scans model directories for .mdl.bak backup files, verifies their
    GoldSrc IDST header, and returns structured metadata dictionaries.
    """
    root = get_project_root()
    dirs = search_dirs if search_dirs is not None else DEFAULT_BACKUP_DIRS

    results: List[dict] = []
    seen_paths = set()

    for sdir in dirs:
        p = Path(sdir)
        abs_dir = p if p.is_absolute() else (root / p)
        if not abs_dir.is_dir():
            continue

        for bak_file in abs_dir.rglob("*.bak"):
            # Exclude non-model files (such as .gam.bak or .wav.bak)
            stem_name = bak_file.name[:-4]  # strip .bak
            if not stem_name.lower().endswith(".mdl"):
                continue

            abs_bak_str = str(bak_file.resolve())
            if abs_bak_str in seen_paths:
                continue
            seen_paths.add(abs_bak_str)

            target_file = bak_file.with_name(stem_name)
            has_target = target_file.is_file()

            try:
                rel_backup = bak_file.relative_to(root).as_posix()
            except ValueError:
                rel_backup = bak_file.as_posix()

            try:
                rel_target = target_file.relative_to(root).as_posix()
            except ValueError:
                rel_target = target_file.as_posix()

            bak_stat = bak_file.stat()
            bak_size = bak_stat.st_size
            tgt_size = target_file.stat().st_size if has_target else None

            is_valid_idst = verify_goldsrc_mdl_header(bak_file)
            is_modified = has_target and (bak_size != tgt_size)
            mtime_iso = datetime.fromtimestamp(bak_stat.st_mtime).strftime("%Y-%m-%d %H:%M:%S")

            results.append({
                "backup_path": abs_bak_str,
                "relative_backup": rel_backup,
                "target_path": str(target_file.resolve()),
                "relative_target": rel_target,
                "model_name": target_file.name,
                "backup_size": bak_size,
                "target_size": tgt_size,
                "has_target": has_target,
                "is_modified": is_modified,
                "is_valid_idst": is_valid_idst,
                "backup_mtime": mtime_iso
            })

    return sorted(results, key=lambda x: x["relative_backup"])


def restore_model_backup(model_name_or_path: str) -> AdapterResult:
    """
    Restores an active model from its .bak backup after verifying the GoldSrc IDST header.
    Does NOT delete the .bak file to ensure idempotent rollback safety.
    """
    root = get_project_root()
    p = Path(model_name_or_path)

    # Determine candidate backup and target paths
    bak_path: Optional[Path] = None
    target_path: Optional[Path] = None

    if p.is_absolute():
        if p.name.lower().endswith(".bak"):
            bak_path = p
            target_path = p.with_name(p.name[:-4])
        else:
            target_path = p
            bak_path = p.with_name(p.name + ".bak")
    else:
        # Check direct relative path from root
        cand = (root / p).resolve()
        if cand.name.lower().endswith(".bak") and cand.is_file():
            bak_path = cand
            target_path = cand.with_name(cand.name[:-4])
        elif cand.is_file():
            target_path = cand
            bak_path = cand.with_name(cand.name + ".bak")
        else:
            # Search in known backup directories
            norm_name = p.name
            if not norm_name.lower().endswith(".bak"):
                if not norm_name.lower().endswith(".mdl"):
                    norm_name = f"v_{norm_name}.mdl"
                bak_name = norm_name + ".bak"
            else:
                bak_name = norm_name

            for sdir in DEFAULT_BACKUP_DIRS:
                abs_sdir = root / sdir
                found = list(abs_sdir.rglob(bak_name))
                if found:
                    bak_path = found[0]
                    target_path = bak_path.with_name(bak_path.name[:-4])
                    break

    if not bak_path or not bak_path.is_file():
        return AdapterResult(
            success=False,
            message=f"Backup file not found for: {model_name_or_path}",
            returncode=-1
        )

    # Validate GoldSrc IDST header before restoring
    if not verify_goldsrc_mdl_header(bak_path):
        return AdapterResult(
            success=False,
            message=f"Restoration aborted: Invalid GoldSrc MDL header in backup ({bak_path.name}).",
            returncode=-1
        )

    try:
        shutil.copy2(str(bak_path), str(target_path))
        return AdapterResult(
            success=True,
            message=f"Successfully restored '{target_path.name}' from backup.",
            stdout=f"Restored: {bak_path.name} -> {target_path.name}",
            returncode=0
        )
    except Exception as exc:
        return AdapterResult(
            success=False,
            message=f"Failed to restore model backup: {exc}",
            stderr=str(exc),
            returncode=-1
        )


def restore_all_backups() -> AdapterResult:
    """
    Batch restores all valid discovered model backups.
    """
    backups = list_backups()
    if not backups:
        return AdapterResult(True, "No backup files found to restore.")

    restored_count = 0
    failed_items: List[str] = []

    for b in backups:
        res = restore_model_backup(b["backup_path"])
        if res.success:
            restored_count += 1
        else:
            failed_items.append(f"{b['model_name']}: {res.message}")

    if failed_items:
        summary_err = "\n".join(failed_items)
        return AdapterResult(
            success=False,
            message=f"Restored {restored_count} model(s), but {len(failed_items)} failed.",
            stderr=summary_err,
            returncode=-1
        )

    return AdapterResult(
        success=True,
        message=f"Successfully restored all {restored_count} model backup(s).",
        stdout=f"Restored count: {restored_count}",
        returncode=0
    )
```

---

### 4.3 Test Strategy & Verification Specifications

The test suite will be located in `tests/` and can be executed via standard `python -m unittest discover tests`.

#### 4.3.1 `tests/test_adapters.py` (Tier 1 Adapter Unit Tests)

```python
"""
tests/test_adapters.py
Unit tests for tools.cs16_mod_hub.core.common and model_adapter.
"""

import os
from pathlib import Path
import sys
import unittest
from unittest.mock import MagicMock, patch

# Add repository root to sys.path
REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.cs16_mod_hub.core.common import AdapterResult, get_project_root, run_script_streaming
from tools.cs16_mod_hub.core.model_adapter import (
    transfer_skin,
    inject_gloves,
    inject_pw,
    list_viewmodels,
    list_donor_models,
    verify_goldsrc_mdl_header
)


class TestCommonAdapter(unittest.TestCase):
    def test_get_project_root(self):
        root = get_project_root()
        self.assertTrue((root / "cstrike").is_dir(), f"Expected cstrike in {root}")

    def test_adapter_result_bool_and_properties(self):
        res_ok = AdapterResult(True, "OK", stdout="Output line")
        self.assertTrue(bool(res_ok))
        self.assertEqual(res_ok.output, "Output line")

        res_err = AdapterResult(False, "Failed", stderr="Error line", returncode=1)
        self.assertFalse(bool(res_err))
        self.assertEqual(res_err.output, "Error line")

    def test_run_script_streaming_missing_script(self):
        res = run_script_streaming("nonexistent_script_path.py", [])
        self.assertFalse(res.success)
        self.assertIn("not found", res.message)


class TestModelAdapter(unittest.TestCase):
    def test_list_viewmodels_cstrike(self):
        models = list_viewmodels("cstrike/models")
        self.assertIsInstance(models, list)
        self.assertIn("v_ak47.mdl", models)
        self.assertIn("v_m4a1.mdl", models)
        self.assertIn("v_awp.mdl", models)
        for m in models:
            self.assertTrue(m.startswith("v_"))
            self.assertTrue(m.endswith(".mdl"))

    def test_list_viewmodels_missing_dir(self):
        models = list_viewmodels("nonexistent_dir_12345")
        self.assertEqual(models, [])

    def test_list_donor_models(self):
        donors = list_donor_models()
        self.assertIsInstance(donors, list)
        self.assertGreater(len(donors), 0)
        # Should contain forward slashes and v_*.mdl
        for d in donors:
            self.assertIn("v_", d)
            self.assertTrue(d.endswith(".mdl"))

    @patch("tools.cs16_mod_hub.core.model_adapter.run_script_streaming")
    def test_transfer_skin_args(self, mock_run):
        mock_run.return_value = AdapterResult(True, "Success")
        res = transfer_skin("source.mdl", "target.mdl", dir_path="cstrike/models", sync_pw=True, no_backup=True)
        self.assertTrue(res.success)
        mock_run.assert_called_once()
        args = mock_run.call_args[0][1]
        self.assertIn("-s", args)
        self.assertIn("source.mdl", args)
        self.assertIn("-t", args)
        self.assertIn("target.mdl", args)
        self.assertIn("--sync-pw", args)
        self.assertIn("--no-backup", args)

    @patch("tools.cs16_mod_hub.core.model_adapter.run_script_streaming")
    def test_inject_gloves_args(self, mock_run):
        mock_run.return_value = AdapterResult(True, "Success")
        res = inject_gloves("v_deagle.mdl", source="v_awp.mdl")
        self.assertTrue(res.success)
        mock_run.assert_called_once()
        args = mock_run.call_args[0][1]
        self.assertIn("-t", args)
        self.assertIn("v_deagle.mdl", args)
        self.assertIn("-s", args)
        self.assertIn("v_awp.mdl", args)

    def test_inject_pw_validation(self):
        res = inject_pw()
        self.assertFalse(res.success)
        self.assertIn("Either 'weapon' or 'v_model' must be provided", res.message)


if __name__ == "__main__":
    unittest.main()
```

#### 4.3.2 `tests/test_backups.py` (Tier 2 Non-Destructive Backup Tests)

```python
"""
tests/test_backups.py
Tests for backup enumeration, IDST header verification, and safe restoration.
"""

from pathlib import Path
import shutil
import struct
import sys
import tempfile
import unittest

REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.cs16_mod_hub.core.model_adapter import (
    list_backups,
    restore_model_backup,
    restore_all_backups,
    verify_goldsrc_mdl_header
)


class TestBackupManagement(unittest.TestCase):
    def test_verify_goldsrc_mdl_header_valid(self):
        # Check an existing model in the game
        model_path = REPO_ROOT / "cstrike" / "models" / "v_ak47.mdl"
        if model_path.is_file():
            self.assertTrue(verify_goldsrc_mdl_header(model_path))

    def test_verify_goldsrc_mdl_header_corrupt(self):
        with tempfile.NamedTemporaryFile(suffix=".mdl.bak", delete=False) as tf:
            tf.write(b"NOT_A_VALID_HEADER_DATA")
            tf_path = Path(tf.name)
        try:
            self.assertFalse(verify_goldsrc_mdl_header(tf_path))
        finally:
            if tf_path.is_file():
                tf_path.unlink()

    def test_list_backups_filters_non_models(self):
        backups = list_backups()
        self.assertIsInstance(backups, list)
        for b in backups:
            self.assertTrue(b["model_name"].lower().endswith(".mdl"))
            self.assertTrue(b["backup_path"].lower().endswith(".bak"))
            self.assertIn("is_valid_idst", b)
            self.assertIn("backup_size", b)

    def test_restore_model_backup_lifecycle(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            td = Path(tmpdir)
            target = td / "v_test.mdl"
            backup = td / "v_test.mdl.bak"

            # Create dummy GoldSrc file: IDST + version 10 + dummy padding
            dummy_header = b"IDST" + struct.pack("<I", 10) + (b"\x00" * 200)
            target.write_bytes(dummy_header + b"ACTIVE_CONTENT")
            backup.write_bytes(dummy_header + b"BACKUP_CONTENT")

            res = restore_model_backup(str(backup))
            self.assertTrue(res.success)
            self.assertEqual(target.read_bytes(), dummy_header + b"BACKUP_CONTENT")
            # Verify backup file is preserved
            self.assertTrue(backup.is_file())


if __name__ == "__main__":
    unittest.main()
```

---

## 5. Verification Method

### 5.1 Verification Commands
Once implemented by the developer agent, the following commands will independently verify Milestone M1:

1. **Verify Python syntax and imports**:
   ```powershell
   python -c "import tools.cs16_mod_hub.core.common as c; import tools.cs16_mod_hub.core.model_adapter as m; print('COMMON AND MODEL ADAPTER LOAD CLEANLY')"
   ```

2. **Verify GoldSrc header verification and model list**:
   ```powershell
   python -c "from tools.cs16_mod_hub.core.model_adapter import list_viewmodels, list_donor_models, list_backups; v = list_viewmodels(); d = list_donor_models(); b = list_backups(); print(f'Viewmodels: {len(v)}, Donors: {len(d)}, Backups: {len(b)}'); assert len(v) >= 29; assert len(d) >= 20; assert len(b) >= 10; print('MODEL SCANNING OK')"
   ```

3. **Run automated unit and backup test suite**:
   ```powershell
   python -m unittest tests/test_adapters.py
   python -m unittest tests/test_backups.py
   ```

### 5.2 Invalidation Conditions
This design specification would be invalidated if:
1. GoldSrc StudioModel format specification changes magic byte sequence from `b'IDST'` or version integer from `10`.
2. Existing scripts in `.agents/skills/` are refactored or removed.
3. Python runtime on host system drops standard library `threading` or `subprocess`.
