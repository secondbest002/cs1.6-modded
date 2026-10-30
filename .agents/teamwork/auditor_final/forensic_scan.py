"""
forensic_scan.py - Independent verification script by Final Forensic Auditor.
Executes deep empirical checks across all repository work products.
"""

import os
import re
import sys
from pathlib import Path
import unicodedata

# 1. Allowed monochrome glyphs per Requirement R3
ALLOWED_MONOCHROME_GLYPHS = {"◆", "◈", "▸", "⚙", "✦", "⟲", "✓", "✕", "⇄"}

# Comprehensive regex for emojis
EMOJI_REGEX = re.compile(
    "["
    "\U0001F600-\U0001F64F"  # Emoticons
    "\U0001F300-\U0001F5FF"  # Misc Symbols and Pictographs
    "\U0001F680-\U0001F6FF"  # Transport and Map
    "\U0001F1E0-\U0001F1FF"  # Regional Indicator Symbols (flags)
    "\U0001F900-\U0001F9FF"  # Supplemental Symbols and Pictographs
    "\U0001FA70-\U0001FAFF"  # Symbols and Pictographs Extended-A
    "\U00002702-\U00002712"  # Dingbats
    "\U00002714-\U00002725"  # Dingbats (excluding ✓ and ✦)
    "\U00002727-\U000027BF"  # Dingbats remaining
    "\U00002600-\U00002698"  # Misc symbols (excluding ⚙)
    "\U0000269A-\U000026FF"  # Misc symbols remaining
    "]+",
    flags=re.UNICODE,
)

def scan_file_for_emojis(file_path: Path):
    try:
        content = file_path.read_text(encoding="utf-8", errors="replace")
    except Exception as e:
        return [f"Could not read {file_path}: {e}"]

    # Skip files that intentionally contain emoji detection regex patterns or test samples
    if file_path.name in ["test_emoji_cleanliness.py", "forensic_scan.py"]:
        return []

    violations = []
    for line_idx, line in enumerate(content.splitlines(), start=1):
        for m in EMOJI_REGEX.finditer(line):
            s = m.group(0)
            for c in s:
                if c not in ALLOWED_MONOCHROME_GLYPHS:
                    violations.append(
                        f"{file_path}:L{line_idx} char '{c}' (U+{ord(c):04X}, name: {unicodedata.name(c, 'UNKNOWN')})"
                    )
    return violations

def run_emoji_audit(root_dir: Path):
    print("=== CHECK 1: EMOJI AUDIT ===")
    extensions = {".py", ".bat", ".md", ".ini", ".cfg"}
    dirs_to_check = [
        root_dir / "tools",
        root_dir / "tests",
        root_dir / "CS16_Mod_Manager.bat",
    ]

    files_scanned = 0
    all_violations = []

    for item in dirs_to_check:
        if item.is_file():
            files_scanned += 1
            all_violations.extend(scan_file_for_emojis(item))
        elif item.is_dir():
            for p in item.rglob("*"):
                if p.is_file() and p.suffix.lower() in extensions:
                    files_scanned += 1
                    all_violations.extend(scan_file_for_emojis(p))

    print(f"Scanned {files_scanned} files across tools, tests, and launcher.")
    if all_violations:
        print(f"[FAIL] Found {len(all_violations)} emoji violations:")
        for v in all_violations:
            print(f"  {v}")
        return False
    else:
        print("[PASS] 0 emojis found. All files clean.")
        return True

def run_facade_and_hardcoding_audit(root_dir: Path):
    print("\n=== CHECK 2: FACADE & HARDCODING AUDIT ===")
    tools_dir = root_dir / "tools" / "cs16_mod_hub"
    py_files = list(tools_dir.rglob("*.py"))

    suspect_patterns = [
        r"return\s+True\s*#.*always",
        r"return\s+['\"]success['\"]\s*#.*dummy",
        r"return\s+None\s*#.*not implemented",
    ]

    violations = []
    for f in py_files:
        text = f.read_text(encoding="utf-8", errors="replace")
        for line_idx, line in enumerate(text.splitlines(), start=1):
            for pat in suspect_patterns:
                if re.search(pat, line, re.IGNORECASE):
                    violations.append(f"{f}:L{line_idx}: {line.strip()}")

    if violations:
        print(f"[FAIL] Found suspect dummy returns: {violations}")
        return False
    else:
        print(f"[PASS] Checked {len(py_files)} Python files in tools/cs16_mod_hub/. No dummy returns found.")
        return True

def run_backup_safety_check(root_dir: Path):
    print("\n=== CHECK 3: BACKUP SAFETY ENGINE VERIFICATION ===")
    from tools.cs16_mod_hub.core.model_adapter import (
        verify_goldsrc_mdl_header,
        list_backups,
        restore_model_backup,
    )
    import tempfile
    import struct

    # Test IDST validation
    with tempfile.NamedTemporaryFile("wb", suffix=".mdl", delete=False) as f:
        # Write valid IDST header (magic: b'IDST', version: 10)
        f.write(struct.pack("<4sI", b"IDST", 10))
        f.write(b"\x00" * 200)
        valid_path = Path(f.name)

    with tempfile.NamedTemporaryFile("wb", suffix=".mdl", delete=False) as f:
        # Write corrupt header
        f.write(b"CORRUPT!" + b"\x00" * 200)
        corrupt_path = Path(f.name)

    try:
        if not verify_goldsrc_mdl_header(valid_path):
            print("[FAIL] Valid IDST header not recognized.")
            return False
        if verify_goldsrc_mdl_header(corrupt_path):
            print("[FAIL] Corrupt header falsely accepted as valid.")
            return False

        # Test safe restore refuses corrupt backup
        target_path = corrupt_path.with_name("test_target.mdl")
        target_path.write_bytes(b"original")
        bak_path = corrupt_path.with_name("test_target.mdl.bak")
        bak_path.write_bytes(b"CORRUPT_BACKUP")

        res = restore_model_backup(str(target_path))
        if res.success:
            print("[FAIL] restore_model_backup did not reject corrupt header!")
            return False

        print("[PASS] IDST header verification and corrupt backup rejection verified.")
        return True
    finally:
        for p in [valid_path, corrupt_path, corrupt_path.with_name("test_target.mdl"), corrupt_path.with_name("test_target.mdl.bak")]:
            if p.exists():
                try:
                    p.unlink()
                except Exception:
                    pass

def main():
    root_dir = Path(__file__).resolve().parent.parent.parent.parent
    sys.path.insert(0, str(root_dir))

    check1 = run_emoji_audit(root_dir)
    check2 = run_facade_and_hardcoding_audit(root_dir)
    check3 = run_backup_safety_check(root_dir)

    all_passed = check1 and check2 and check3
    print("\n" + "=" * 50)
    if all_passed:
        print("FORENSIC SCAN VERDICT: ALL AUDIT CHECKS PASSED (CLEAN)")
        sys.exit(0)
    else:
        print("FORENSIC SCAN VERDICT: INTEGRITY VIOLATION DETECTED")
        sys.exit(1)

if __name__ == "__main__":
    main()
