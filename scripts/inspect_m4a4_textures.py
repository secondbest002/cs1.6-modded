import os
import sys
from pathlib import Path

root = Path(r"D:\Games\Counter-Strike\Counter-Strike 1.6 Original")
sys.path.insert(0, str(root / "scripts"))

from cs16_studio.mdl_core import MdlModel
from cs16_studio.glove_transfer import classify_glove_role

files_to_check = [
    root / "cstrike" / "models" / "custom_skins" / "ct" / "v_m4a4.mdl",
    root / "cstrike" / "models" / "custom_skins" / "ct" / "v_m4a4.orig.mdl",
    root / "cstrike" / "models" / "custom_skins" / "ct" / "v_m4a4.mdl.bak",
]

for p in files_to_check:
    print(f"\n==========================================")
    print(f"FILE: {p.name} (exists: {p.exists()}, size: {p.stat().st_size if p.exists() else 0:,} bytes)")
    if not p.exists():
        continue
    m = MdlModel(p)
    print(f"Textures count: {len(m.textures)}")
    for t in m.textures:
        grole = classify_glove_role(t.name)
        print(f"  [{t.index:2d}] {t.name:<26} {t.width}x{t.height:<6} flags: 0x{t.flags:04X} role: {t.role} (glove_role: {grole})")
