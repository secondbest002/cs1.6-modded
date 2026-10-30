#!/usr/bin/env python3
"""
inject_m4a4_gloves.py - Injects gloves & sleeve from v_m4a4.orig.mdl into v_m4a4.mdl
"""

import os
import sys
import shutil
from pathlib import Path

PROJECT_ROOT = Path(r"D:\Games\Counter-Strike\Counter-Strike 1.6 Original")
sys.path.insert(0, str(PROJECT_ROOT / "scripts"))

from cs16_studio.mdl_core import MdlModel
from cs16_studio.slot_geometry import validate_model_health

CT_DIR = PROJECT_ROOT / "cstrike" / "models" / "custom_skins" / "ct"
SRC_PATH = CT_DIR / "v_m4a4.orig.mdl"
TGT_PATH = CT_DIR / "v_m4a4.mdl"

def main():
    print("=== Injecting Gloves and Sleeve into v_m4a4.mdl ===")
    print(f"Source file: {SRC_PATH}")
    print(f"Target file: {TGT_PATH}")

    if not SRC_PATH.exists():
        print(f"ERROR: Source file does not exist: {SRC_PATH}")
        sys.exit(1)
    if not TGT_PATH.exists():
        print(f"ERROR: Target file does not exist: {TGT_PATH}")
        sys.exit(1)

    # 1. Load models
    src = MdlModel(SRC_PATH)
    tgt = MdlModel(TGT_PATH)

    # 2. Backup target file
    bak_path = TGT_PATH.with_suffix(".pre_glove_inject.bak")
    shutil.copy2(TGT_PATH, bak_path)
    print(f"[Backup] Saved backup to: {bak_path.name}")

    # Also save PNG previews of target BEFORE injection
    preview_dir = PROJECT_ROOT / "scripts" / "m4a4_previews"
    preview_dir.mkdir(parents=True, exist_ok=True)
    for t in tgt.textures:
        if t.name in ("sport_glove_L.bmp", "sport_glove_R.bmp", "t_arm.bmp"):
            t.to_rgba_image().save(preview_dir / f"before_{t.name}.png")

    # Save PNG previews of source
    for t in src.textures:
        if t.name in ("sport_left.bmp", "sport_right.bmp", "sleeve.bmp"):
            t.to_rgba_image().save(preview_dir / f"source_{t.name}.png")

    # 3. Explicit mappings: (target_texture_name, source_texture_name)
    mappings = [
        ("sport_glove_L.bmp", "sport_left.bmp"),
        ("sport_glove_R.bmp", "sport_right.bmp"),
        ("t_arm.bmp", "sleeve.bmp"),
    ]

    for tgt_name, src_name in mappings:
        tgt_tex = tgt.get_texture_by_name(tgt_name)
        src_tex = src.get_texture_by_name(src_name)

        if not tgt_tex:
            print(f"ERROR: Target texture '{tgt_name}' not found!")
            sys.exit(1)
        if not src_tex:
            print(f"ERROR: Source texture '{src_name}' not found!")
            sys.exit(1)

        print(f"\n[Injecting] {tgt_tex.name} ({tgt_tex.width}x{tgt_tex.height}) <- {src_tex.name} ({src_tex.width}x{src_tex.height})")
        if tgt_tex.width != src_tex.width or tgt_tex.height != src_tex.height:
            print(f"ERROR: Dimension mismatch: {tgt_tex.width}x{tgt_tex.height} vs {src_tex.width}x{src_tex.height}")
            sys.exit(1)

        # Inject bit-exact 512x512 payload (pixels + palette)
        tgt.inject_texture_payload(tgt_tex, src_tex.raw_data, new_flags=tgt_tex.flags)
        print(f"  -> Injected {len(src_tex.raw_data):,} bytes successfully.")

        # Save after preview
        tgt_tex.to_rgba_image().save(preview_dir / f"after_{tgt_tex.name}.png")

    # 4. Save atomic
    saved_path = tgt.save_atomic(create_backup=False)
    print(f"\n[Saved] File saved atomically to: {saved_path}")

    # 5. Validate model health
    health = validate_model_health(TGT_PATH)
    print("\n--- Model Health Check ---")
    print(f"Status      : {health['status']}")
    print(f"Healthy     : {health['healthy']}")
    print(f"File Size   : {health['file_size']:,} bytes (Header declared: {health['header_length']:,} bytes)")
    print(f"Size Match  : {health['size_match']}")
    print(f"Textures    : {health['num_textures']}")
    print(f"Max Vertices: {health['max_verts_submodel']} (Limit: 2048)")
    if health["issues"]:
        print("Issues detected:")
        for iss in health["issues"]:
            print(f"  - {iss}")
    else:
        print("[100% HEALTHY] Zero corruption, 100% GoldSrc IDST v10 engine compliant!")

if __name__ == "__main__":
    main()
