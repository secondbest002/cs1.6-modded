import sys
import shutil
from pathlib import Path

root = Path(r"D:\Games\Counter-Strike\Counter-Strike 1.6 Original")
sys.path.insert(0, str(root / "scripts"))
from cs16_studio.mdl_core import MdlModel
from cs16_studio.slot_geometry import validate_model_health

ct_dir = root / "cstrike" / "models" / "custom_skins" / "ct"
orig_path = ct_dir / "v_m4a4.orig.mdl"
target_path = ct_dir / "v_m4a4.mdl"
test_path = ct_dir / "v_m4a4_howl_ct_arms.mdl"

# Load models
orig = MdlModel(orig_path)
target = MdlModel(target_path)

# Find Howl texture in target
howl_tex = target.get_texture_by_name("rif_m4a1.bmp")
# Find weapon texture in orig
orig_weapon_tex = orig.get_texture_by_name("rif_m4a1.bmp")

print(f"Howl payload size: {len(howl_tex.raw_data)}")
print(f"Orig weapon payload size: {len(orig_weapon_tex.raw_data)}")

# Inject Howl texture into orig
orig.inject_texture_payload(orig_weapon_tex, howl_tex.raw_data, new_flags=orig_weapon_tex.flags)

# Save to test file
orig.save_atomic(test_path, create_backup=False)
print(f"Saved test model to: {test_path.name}")

# Validate health
health = validate_model_health(test_path)
print(f"Health: {health['healthy']}, Status: {health['status']}")
print(f"Textures in test model:")
for t in orig.textures:
    print(f"  [{t.index}] {t.name:<22} {t.width}x{t.height}")
