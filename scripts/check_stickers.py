from pathlib import Path
import sys

root = Path(r"D:\Games\Counter-Strike\Counter-Strike 1.6 Original")
sys.path.insert(0, str(root / "scripts"))
from cs16_studio.mdl_core import MdlModel

target = MdlModel(root / "cstrike" / "models" / "custom_skins" / "ct" / "v_m4a4.mdl")
orig = MdlModel(root / "cstrike" / "models" / "custom_skins" / "ct" / "v_m4a4.orig.mdl")

preview_dir = root / "scripts" / "m4a4_previews"

print("Target Stickers:")
for t in target.get_stickers():
    t.to_rgba_image().save(preview_dir / f"target_{t.name}.png")
    print(f"  {t.name} ({t.width}x{t.height})")

print("Orig Stickers:")
for t in orig.get_stickers():
    t.to_rgba_image().save(preview_dir / f"orig_{t.name}.png")
    print(f"  {t.name} ({t.width}x{t.height})")
