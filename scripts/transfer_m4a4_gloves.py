#!/usr/bin/env python3
"""
transfer_m4a4_gloves.py - Inspects and transfers glove & sleeve textures
from v_m4a4_orig.mdl into v_m4a4.mdl in cstrike/models/custom_skins/ct/
"""

import os
import sys
import shutil
from pathlib import Path
from PIL import Image

PROJECT_ROOT = Path(r"D:\Games\Counter-Strike\Counter-Strike 1.6 Original")
sys.path.insert(0, str(PROJECT_ROOT / "scripts"))

from cs16_studio.mdl_core import MdlModel, MdlTexture
from cs16_studio.glove_transfer import classify_glove_role
from cs16_studio.image_pipeline import quantize_goldsrc

CT_DIR = PROJECT_ROOT / "cstrike" / "models" / "custom_skins" / "ct"
SRC_PATH = CT_DIR / "v_m4a4_orig.mdl"
TGT_PATH = CT_DIR / "v_m4a4.mdl"

def main():
    print("=== M4A4 Glove & Sleeve Injector ===")
    print(f"Source (with gloves): {SRC_PATH}")
    print(f"Target (to inject)  : {TGT_PATH}")

    if not SRC_PATH.exists():
        print(f"ERROR: Source file not found: {SRC_PATH}")
        sys.exit(1)
    if not TGT_PATH.exists():
        print(f"ERROR: Target file not found: {TGT_PATH}")
        sys.exit(1)

    src_model = MdlModel(SRC_PATH)
    tgt_model = MdlModel(TGT_PATH)

    print("\n--- Source Textures (v_m4a4_orig.mdl) ---")
    for t in src_model.textures:
        role = classify_glove_role(t.name)
        print(f"  [{t.index:2d}] {t.name:<26} {t.width}x{t.height:<6} role: {t.role} (glove_role: {role})")

    print("\n--- Target Textures (v_m4a4.mdl) ---")
    for t in tgt_model.textures:
        role = classify_glove_role(t.name)
        print(f"  [{t.index:2d}] {t.name:<26} {t.width}x{t.height:<6} role: {t.role} (glove_role: {role})")

    # Backup target model before doing anything
    bak_path = TGT_PATH.with_suffix(".mdl.bak")
    if not bak_path.exists():
        shutil.copy2(TGT_PATH, bak_path)
        print(f"\n[Backup] Created backup of target model: {bak_path.name}")
    else:
        print(f"\n[Backup] Existing backup verified: {bak_path.name}")

    # Find gloves and sleeves in source
    src_glove_map = {}
    for t in src_model.textures:
        grole = classify_glove_role(t.name)
        src_glove_map[t.name.lower()] = t
        if grole:
            src_glove_map[grole] = t

    # Match target textures
    injected = []
    for tgt_t in tgt_model.textures:
        tgt_grole = classify_glove_role(tgt_t.name)
        donor = None

        # 1. Exact name match
        if tgt_t.name.lower() in src_glove_map:
            donor = src_glove_map[tgt_t.name.lower()]
        # 2. Classified glove role match
        elif tgt_grole and tgt_grole in src_glove_map:
            donor = src_glove_map[tgt_grole]

        if donor:
            print(f"\n[Transfer] Match found: Target '{tgt_t.name}' ({tgt_t.width}x{tgt_t.height}) <- Source '{donor.name}' ({donor.width}x{donor.height})")
            if donor.width == tgt_t.width and donor.height == tgt_t.height:
                payload = donor.raw_data
                print("  -> Exact dimension match. Direct bitwise transfer.")
            else:
                print(f"  -> Dimension mismatch ({donor.width}x{donor.height} -> {tgt_t.width}x{tgt_t.height}). Resampling via Lanczos...")
                donor_rgba = donor.to_rgba_image()
                resized = donor_rgba.resize((tgt_t.width, tgt_t.height), Image.Resampling.LANCZOS)
                pix_bytes, pal_bytes = quantize_goldsrc(resized, is_masked=tgt_t.is_masked, defringe=tgt_t.is_masked)
                payload = pix_bytes + pal_bytes

            tgt_model.inject_texture_payload(tgt_t, payload, new_flags=tgt_t.flags)
            injected.append((tgt_t.name, donor.name))

    if not injected:
        print("\n[WARNING] No matching glove or sleeve textures found automatically between models!")
        print("Please review texture names above to configure manual mapping.")
        sys.exit(1)

    # Save target model atomically
    tgt_model.save_atomic(create_backup=True)
    print(f"\n[SUCCESS] Successfully injected {len(injected)} texture(s) into {TGT_PATH.name}:")
    for tname, dname in injected:
        print(f"  - {tname} (from {dname})")

if __name__ == "__main__":
    main()
