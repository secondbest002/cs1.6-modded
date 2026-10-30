import os
from pathlib import Path

root = Path(r"D:\Games\Counter-Strike\Counter-Strike 1.6 Original")

print("--- Searching in cstrike/models ---")
for p in (root / "cstrike" / "models").rglob("*m4a*"):
    print(p.relative_to(root))

print("\n--- Searching in cstrike_hd/models (if exists) ---")
hd_dir = root / "cstrike_hd" / "models"
if hd_dir.exists():
    for p in hd_dir.rglob("*m4a*"):
        print(p.relative_to(root))

print("\n--- Listing cstrike/models/custom_skins ---")
custom_dir = root / "cstrike" / "models" / "custom_skins"
if custom_dir.exists():
    for p in custom_dir.rglob("*"):
        if p.is_file():
            print(p.relative_to(root))
else:
    print("custom_skins directory does not exist under cstrike/models!")
    # Check if custom_skins exists anywhere
    for p in (root / "cstrike").rglob("*custom*"):
        print("Found custom path:", p.relative_to(root))
