import ast
import os
import re
import unicodedata

def is_emoji(char):
    # Check unicode category and code point ranges for emojis
    cp = ord(char)
    # Standard emoji ranges
    if (0x1F300 <= cp <= 0x1FAD6) or (0x1F900 <= cp <= 0x1F9FF) or (0x2600 <= cp <= 0x27BF) or (0x1F600 <= cp <= 0x1F64F):
        # Whitelist allowed monochrome typography glyphs
        # ORIGINAL_REQUEST explicitly allows: ◆, ◈, ▸, ⚙, ✦, ⟲, ✓, ✕, ⇄, [+], [-]
        # ⚙ is U+2699, ✦ is U+2728 or U+2726, ✓ is U+2713, ✕ is U+2715
        if char in ['⚙', '✦', '✓', '✕']:
            return False
        return True
    return False

def check_emojis_in_file(filepath):
    violations = []
    with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
        for line_no, line in enumerate(f, 1):
            for col_no, ch in enumerate(line, 1):
                if is_emoji(ch):
                    violations.append((line_no, col_no, ch, line.strip()))
    return violations

def check_ast_facades(filepath):
    facades = []
    with open(filepath, 'r', encoding='utf-8') as f:
        try:
            tree = ast.parse(f.read(), filename=filepath)
        except Exception as e:
            return [(0, "SyntaxError", str(e))]

    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            # Ignore abstract or dunder if trivial
            body = [stmt for stmt in node.body if not (isinstance(stmt, ast.Expr) and isinstance(stmt.value, ast.Constant) and isinstance(stmt.value.value, str))] # strip docstrings
            if not body:
                facades.append((node.lineno, node.name, "Empty body (only docstring)"))
            elif len(body) == 1:
                stmt = body[0]
                if isinstance(stmt, ast.Pass):
                    facades.append((node.lineno, node.name, "Body is only 'pass'"))
                elif isinstance(stmt, ast.Raise) and isinstance(getattr(stmt, 'exc', None), ast.Call):
                    # Check NotImplementedError
                    exc_id = getattr(stmt.exc.func, 'id', '')
                    if exc_id == 'NotImplementedError':
                        facades.append((node.lineno, node.name, "Raises NotImplementedError"))
                elif isinstance(stmt, ast.Return) and isinstance(stmt.value, ast.Constant):
                    # Single return constant, e.g. return True / return 0
                    # Let's inspect function name and context
                    facades.append((node.lineno, node.name, f"Trivial return constant: {stmt.value.value}"))
    return facades

print("=== RUNNING AST & FACADE CHECKS ===")
hub_dir = "tools/cs16_mod_hub"
py_files = []
for root, _, files in os.walk(hub_dir):
    for f in files:
        if f.endswith(".py"):
            py_files.append(os.path.join(root, f))

total_facades = 0
for pf in sorted(py_files):
    issues = check_ast_facades(pf)
    if issues:
        print(f"File: {pf}")
        for lineno, name, reason in issues:
            print(f"  Line {lineno} [{name}]: {reason}")
            total_facades += 1

print(f"Total facade / stub warnings in {len(py_files)} files: {total_facades}")

print("\n=== RUNNING EMOJI CLEANLINESS SCAN ===")
emoji_scan_dirs = ["tools/cs16_mod_hub", "tests"]
all_scanned_files = []
for d in emoji_scan_dirs:
    for root, _, files in os.walk(d):
        for f in files:
            if f.endswith((".py", ".bat", ".ini", ".cfg", ".md")):
                all_scanned_files.append(os.path.join(root, f))
if os.path.exists("CS16_Mod_Manager.bat"):
    all_scanned_files.append("CS16_Mod_Manager.bat")

total_emojis = 0
for sf in sorted(all_scanned_files):
    ev = check_emojis_in_file(sf)
    if ev:
        print(f"Emoji violation in {sf}:")
        for lno, cno, ch, text in ev:
            print(f"  L{lno}:{cno} '{ch}' (U+{ord(ch):04X}) in: {text}")
            total_emojis += 1

print(f"Total emoji violations across {len(all_scanned_files)} files: {total_emojis}")
