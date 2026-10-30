"""
Adversarial test script for palette_preview module.
"""
from pathlib import Path
import sys

proj_root = Path(__file__).resolve().parents[3]
if str(proj_root) not in sys.path:
    sys.path.insert(0, str(proj_root))

import tempfile
from PIL import Image
from tools.cs16_mod_hub.core import palette_preview
from tests.fixtures import generate_valid_mdl_bytes

with tempfile.TemporaryDirectory() as td:
    tdp = Path(td)
    mdl_path = tdp / "v_test.mdl"
    
    # Generate model with masked texture (flags 0x40)
    textures = [
        {"name": "weapon_skin.bmp", "flags": 0, "w": 32, "h": 32},
        {"name": "masked_scope.bmp", "flags": 0x40, "w": 32, "h": 32},
    ]
    mdl_path.write_bytes(generate_valid_mdl_bytes(textures))
    
    # 1. Test extraction prefer_weapon
    tname, flags, w, h, pixels, palette = palette_preview.extract_weapon_texture(str(mdl_path))
    assert tname == "weapon_skin.bmp", f"Expected weapon_skin.bmp, got {tname}"
    assert len(palette) == 768
    
    # 2. Test masked palette transformation
    adj_pal = palette_preview.transform_palette(palette, sat=1.5, contrast=1.2, brightness=1.1, is_masked=True)
    assert len(adj_pal) == 768
    # Masked index 255 must match original palette
    assert adj_pal[255*3 : 255*3 + 3] == palette[255*3 : 255*3 + 3], "Index 255 altered on masked palette!"
    
    # 3. Test generate_preview_images
    orig_thumb, adj_thumb, info = palette_preview.generate_preview_images(
        str(mdl_path), sat=1.35, contrast=1.15, brightness=1.0, thumb_size=(128, 128)
    )
    assert orig_thumb.size == (128, 128)
    assert adj_thumb.size == (128, 128)
    assert "weapon_skin.bmp" in info
    
    # 4. Test TexturePreviewCache
    cache = palette_preview.TexturePreviewCache()
    thumb1, info1 = cache.load(str(mdl_path))
    assert thumb1 is not None
    adj_cached = cache.compute_adjusted_thumbnail(sat=0.5, contrast=1.0, brightness=1.0)
    assert adj_cached.size == (256, 256)

print("ALL PALETTE PREVIEW ADVERSARIAL CHECKS PASSED!")
