#!/usr/bin/env python3
"""
toggle_sticker_fx.py - Dynamically toggle sticker visual effects (Chrome/Foil, Matte, Glow, or Hide)
on CS 1.6 GoldSrc weapon models (v_*.mdl).
"""

import argparse
import os
import shutil
import struct
import sys
import numpy as np

def parse_args():
    parser = argparse.ArgumentParser(description="Toggle sticker visual rendering effects on CS 1.6 viewmodels.")
    parser.add_argument("-w", "--weapon", required=True, help="Weapon name or path (e.g., ak47, v_ak47.mdl)")
    parser.add_argument("-m", "--mode", required=True, choices=['foil', 'chrome', 'matte', 'glow', 'hide', 'restore'],
                        help="Visual effect: foil/chrome (reflective shine), matte (flat decal), glow (additive), hide (invisible), restore (original)")
    parser.add_argument("-d", "--dir", default="cstrike_hd/models", help="Directory where models are located (default: cstrike_hd/models)")
    parser.add_argument("--sticker-id", default="all", help="Target specific sticker (1, 2, 3, 4) or 'all' (default: all)")
    parser.add_argument("--no-backup", action="store_true", help="Do not create .bak backup file")
    return parser.parse_args()

def resolve_model_path(path_or_name, default_dir="cstrike_hd/models", prefix="v_"):
    norm = os.path.normpath(path_or_name)
    if os.path.isfile(norm):
        return os.path.abspath(norm)

    base = os.path.basename(norm)
    if not any(base.startswith(p) for p in ["v_", "p_", "w_"]):
        base = prefix + base
    if not base.endswith(".mdl"):
        base = base + ".mdl"

    search_dirs = [
        default_dir,
        os.path.join("cstrike", "models", "custom_skins", "t"),
        os.path.join("cstrike", "models", "custom_skins", "ct"),
        os.path.join("cstrike", "models"),
        os.path.join("cstrike_hd", "models"),
    ]

    for d in search_dirs:
        candidate = os.path.join(d, base)
        if os.path.isfile(candidate):
            return os.path.abspath(candidate)

    for root, dirs, files in os.walk("."):
        for f in files:
            if f.lower() == base.lower():
                return os.path.abspath(os.path.join(root, f))

    raise FileNotFoundError(f"Model file '{path_or_name}' not found.")

def main():
    args = parse_args()
    try:
        mdl_path = resolve_model_path(args.weapon, args.dir)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

    print(f"Target Model: {mdl_path}")
    print(f"Applying Mode: {args.mode.upper()}")

    if not args.no_backup:
        bak_path = mdl_path + ".bak"
        if not os.path.exists(bak_path):
            shutil.copy2(mdl_path, bak_path)
            print(f"Created backup: {bak_path}")

    with open(mdl_path, 'rb') as f:
        data = bytearray(f.read())

    magic, ver = struct.unpack_from('<4sI', data, 0)
    if magic != b'IDST' or ver != 10:
        raise ValueError(f"Invalid GoldSrc MDL header (magic={magic}, ver={ver})")

    numtextures, textureindex = struct.unpack_from('<II', data, 180)
    matched_stickers = []

    for i in range(numtextures):
        offset = textureindex + i * 80
        tname, flags, w, h, idx = struct.unpack_from('<64sIIII', data, offset)
        tname_str = tname.split(b'\x00')[0].decode('latin1', errors='ignore')
        
        if 'sticker' in tname_str.lower() or 'decal' in tname_str.lower():
            if args.sticker_id != 'all':
                if args.sticker_id not in tname_str:
                    continue
            matched_stickers.append({
                'name': tname_str,
                'offset': offset,
                'flags': flags,
                'w': w,
                'h': h,
                'idx': idx,
                'size': w * h + 768
            })

    if not matched_stickers:
        print(f"No stickers matching criteria found in {mdl_path}.", file=sys.stderr)
        sys.exit(1)

    print(f"Found {len(matched_stickers)} sticker(s): {[s['name'] for s in matched_stickers]}")

    backup_dir = os.path.join(os.path.dirname(mdl_path), ".sticker_backups")
    os.makedirs(backup_dir, exist_ok=True)
    base_file_key = os.path.basename(mdl_path)

    for s in matched_stickers:
        current_flags = s['flags']
        flag_offset = s['offset'] + 64 # in mstudiotexture_t: name is 64s, then flags is I
        pixel_start = s['idx']
        pixel_end = pixel_start + (s['w'] * s['h'])
        raw_backup_path = os.path.join(backup_dir, f"{base_file_key}_{s['name']}.raw")

        if args.mode in ['foil', 'chrome']:
            # STUDIO_NF_CHROME (0x02) | STUDIO_NF_MASKED (0x40) = 0x42
            new_flags = 0x42
            struct.pack_into('<I', data, flag_offset, new_flags)
            print(f"[{s['name']}] Flags set to 0x{new_flags:02X} (Chrome / Foil Reflective)")

        elif args.mode == 'matte':
            # Standard masked decal: 0x40
            new_flags = 0x40
            struct.pack_into('<I', data, flag_offset, new_flags)
            print(f"[{s['name']}] Flags set to 0x{new_flags:02X} (Matte Decal)")

        elif args.mode == 'glow':
            # STUDIO_NF_ADDITIVE (0x20) | STUDIO_NF_MASKED (0x40) = 0x60
            new_flags = 0x60
            struct.pack_into('<I', data, flag_offset, new_flags)
            print(f"[{s['name']}] Flags set to 0x{new_flags:02X} (Additive Glow)")

        elif args.mode == 'hide':
            # Save original raw pixels if not already saved
            if not os.path.exists(raw_backup_path):
                with open(raw_backup_path, 'wb') as bf:
                    bf.write(data[pixel_start:pixel_end])
                print(f"[{s['name']}] Backed up original sticker pixels")
            # Fill with index 255 (GoldSrc transparent color)
            data[pixel_start:pixel_end] = b'\xFF' * (s['w'] * s['h'])
            # Ensure masked flag is on
            struct.pack_into('<I', data, flag_offset, 0x40)
            print(f"[{s['name']}] Sticker hidden (transparent cutout)")

        elif args.mode == 'restore':
            if os.path.exists(raw_backup_path):
                with open(raw_backup_path, 'rb') as bf:
                    restored_pixels = bf.read()
                data[pixel_start:pixel_end] = restored_pixels
                print(f"[{s['name']}] Restored original sticker pixels")
            struct.pack_into('<I', data, flag_offset, 0x40)
            print(f"[{s['name']}] Flags set to default Matte (0x40)")

    with open(mdl_path, 'wb') as f:
        f.write(data)

    print(f"\nAll done! Updated {mdl_path} successfully.")

if __name__ == '__main__':
    main()
