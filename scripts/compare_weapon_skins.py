from pathlib import Path
from PIL import Image
import sys

root = Path(r"D:\Games\Counter-Strike\Counter-Strike 1.6 Original")
sys.path.insert(0, str(root / "scripts"))
from cs16_studio.mdl_core import MdlModel

orig = MdlModel(root / "cstrike" / "models" / "custom_skins" / "ct" / "v_m4a4.orig.mdl")
target = MdlModel(root / "cstrike" / "models" / "custom_skins" / "ct" / "v_m4a4.mdl")

orig_skin = orig.get_texture_by_name("rif_m4a1.bmp")
tgt_skin = target.get_texture_by_name("rif_m4a1.bmp")

preview_dir = root / "scripts" / "m4a4_previews"
preview_dir.mkdir(parents=True, exist_ok=True)

if orig_skin:
    orig_skin.to_rgba_image().save(preview_dir / "orig_rif_m4a1.png")
    print("Saved orig_rif_m4a1.png")
if tgt_skin:
    tgt_skin.to_rgba_image().save(preview_dir / "target_rif_m4a1.png")
    print("Saved target_rif_m4a1.png")

print(f"Orig rif_m4a1 raw bytes len: {len(orig_skin.raw_data) if orig_skin else 0}")
print(f"Target rif_m4a1 raw bytes len: {len(tgt_skin.raw_data) if tgt_skin else 0}")
print(f"Are they identical? {orig_skin.raw_data == tgt_skin.raw_data if orig_skin and tgt_skin else False}")
