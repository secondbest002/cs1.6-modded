#!/usr/bin/env python3
"""
adjust_vibrance.py - Adjust color saturation, contrast, and brightness on CS 1.6 GoldSrc model palettes.
Modifies only the 768-byte palette table directly: 0% geometry distortion, 0% re-quantization artifacts.
"""

import argparse
import colorsys
import os
import shutil
import struct
import sys
import pickle

def parse_args():
    parser = argparse.ArgumentParser(description="Adjust color vibrance, saturation, and contrast on CS 1.6 model palettes.")
    parser.add_argument("-w", "--weapon", required=True, help="Weapon name or path (e.g., ak47, deagle, v_ak47.mdl)")
    parser.add_argument("-t", "--target", default="weapon", choices=['weapon', 'gloves', 'all'],
                        help="Target texture group: weapon (weapon body), gloves (gloves & arms), all (entire model). Default: weapon")
    parser.add_argument("-p", "--preset", choices=['vivid', 'punchy', 'soft', 'grayscale'],
                        help="Color preset: vivid (Sat+35%%, Cont+15%%), punchy (Sat+55%%, Cont+25%%), soft (Muted), grayscale (Monochrome)")
    parser.add_argument("--sat", type=float, default=None, help="Custom saturation multiplier (e.g., 1.3 for +30%%)")
    parser.add_argument("--contrast", type=float, default=None, help="Custom contrast multiplier (e.g., 1.2 for +20%%)")
    parser.add_argument("--brightness", type=float, default=None, help="Custom brightness multiplier (e.g., 1.1 for +10%%)")
    parser.add_argument("--reset", action="store_true", help="Reset targeted palettes back to original factory colors")
    parser.add_argument("-d", "--dir", default="cstrike_hd/models", help="Directory where models are located (default: cstrike_hd/models)")
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

def is_glove(tname):
    return any(k in tname.lower() for k in ['sport', 'glove', 'hand', 'arm', 'sleeve'])

def is_weapon(tname):
    lower = tname.lower()
    excluded = ['sport', 'glove', 'hand', 'arm', 'sleeve', 'sticker', 'stattrak', 'decal']
    return not any(ex in lower for ex in excluded)

def matches_target(tname, target_group):
    if target_group == 'all':
        return True
    if target_group == 'gloves':
        return is_glove(tname)
    if target_group == 'weapon':
        return is_weapon(tname)
    return False

def adjust_rgb(r, g, b, sat_mult, cont_mult, bright_mult):
    # 1. Convert RGB (0..1) to HSV
    r_n, g_n, b_n = r / 255.0, g / 255.0, b / 255.0
    h, s, v = colorsys.rgb_to_hsv(r_n, g_n, b_n)

    # 2. Adjust Saturation
    s = min(max(s * sat_mult, 0.0), 1.0)

    # 3. Adjust Brightness
    v = min(max(v * bright_mult, 0.0), 1.0)

    # Convert back to RGB (0..255)
    r_adj, g_adj, b_adj = colorsys.hsv_to_rgb(h, s, v)
    r_out, g_out, b_out = r_adj * 255.0, g_adj * 255.0, b_adj * 255.0

    # 4. Adjust Contrast around mid-gray (128)
    r_out = (r_out - 128.0) * cont_mult + 128.0
    g_out = (g_out - 128.0) * cont_mult + 128.0
    b_out = (b_out - 128.0) * cont_mult + 128.0

    return (
        int(min(max(round(r_out), 0), 255)),
        int(min(max(round(g_out), 0), 255)),
        int(min(max(round(b_out), 0), 255))
    )

def main():
    args = parse_args()
    try:
        mdl_path = resolve_model_path(args.weapon, args.dir)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

    print(f"Target Model: {mdl_path}")
    print(f"Target Group: {args.target.upper()}")

    # Determine adjustment multipliers
    sat_mult = 1.0
    cont_mult = 1.0
    bright_mult = 1.0

    if args.preset == 'vivid':
        sat_mult = 1.35
        cont_mult = 1.15
    elif args.preset == 'punchy':
        sat_mult = 1.55
        cont_mult = 1.25
    elif args.preset == 'soft':
        sat_mult = 0.85
        cont_mult = 0.95
    elif args.preset == 'grayscale':
        sat_mult = 0.0

    if args.sat is not None:
        sat_mult = args.sat
    if args.contrast is not None:
        cont_mult = args.contrast
    if args.brightness is not None:
        bright_mult = args.brightness

    pal_backup_file = mdl_path + ".original_palettes.dat"

    with open(mdl_path, 'rb') as f:
        data = bytearray(f.read())

    magic, ver = struct.unpack_from('<4sI', data, 0)
    if magic != b'IDST' or ver != 10:
        raise ValueError(f"Invalid GoldSrc MDL header (magic={magic}, ver={ver})")

    numtextures, textureindex = struct.unpack_from('<II', data, 180)
    original_palettes = {}

    # Load existing palette backup if exists
    if os.path.exists(pal_backup_file):
        try:
            with open(pal_backup_file, 'rb') as bf:
                original_palettes = pickle.load(bf)
        except Exception:
            pass

    # Save initial original palettes
    needs_save = False
    for i in range(numtextures):
        offset = textureindex + i * 80
        tname, flags, w, h, idx = struct.unpack_from('<64sIIII', data, offset)
        tname_str = tname.split(b'\x00')[0].decode('latin1', errors='ignore')
        pal_offset = idx + w * h
        current_pal = bytes(data[pal_offset:pal_offset + 768])
        if tname_str not in original_palettes:
            original_palettes[tname_str] = current_pal
            needs_save = True

    if needs_save:
        with open(pal_backup_file, 'wb') as bf:
            pickle.dump(original_palettes, bf)
        print(f"Cached initial factory palettes: {pal_backup_file}")

    if not args.no_backup:
        bak_path = mdl_path + ".bak"
        if not os.path.exists(bak_path):
            shutil.copy2(mdl_path, bak_path)
            print(f"Created file backup: {bak_path}")

    # Process textures
    modified_count = 0
    for i in range(numtextures):
        offset = textureindex + i * 80
        tname, flags, w, h, idx = struct.unpack_from('<64sIIII', data, offset)
        tname_str = tname.split(b'\x00')[0].decode('latin1', errors='ignore')

        if not matches_target(tname_str, args.target):
            continue

        pal_offset = idx + w * h

        if args.reset:
            # Restore original factory palette
            orig_pal = original_palettes.get(tname_str)
            if orig_pal:
                data[pal_offset:pal_offset + 768] = orig_pal
                print(f"[{tname_str}] Reset to factory original palette")
                modified_count += 1
            continue

        # Always apply adjustments starting from the pristine original palette
        base_pal = original_palettes.get(tname_str, bytes(data[pal_offset:pal_offset + 768]))
        new_pal = bytearray(768)

        # In GoldSrc, if texture is masked (0x40), keep color 255 pure for transparency
        is_masked = (flags & 0x40) != 0

        for c in range(256):
            r = base_pal[c * 3]
            g = base_pal[c * 3 + 1]
            b = base_pal[c * 3 + 2]

            if is_masked and c == 255:
                # Keep transparent key color unchanged
                new_pal[c * 3] = r
                new_pal[c * 3 + 1] = g
                new_pal[c * 3 + 2] = b
            else:
                r_n, g_n, b_n = adjust_rgb(r, g, b, sat_mult, cont_mult, bright_mult)
                new_pal[c * 3] = r_n
                new_pal[c * 3 + 1] = g_n
                new_pal[c * 3 + 2] = b_n

        data[pal_offset:pal_offset + 768] = new_pal
        print(f"[{tname_str}] Applied Sat x{sat_mult:.2f}, Contrast x{cont_mult:.2f}, Brightness x{bright_mult:.2f}")
        modified_count += 1

    if modified_count == 0:
        print("No matching textures were found for the selected target group.", file=sys.stderr)
        sys.exit(1)

    with open(mdl_path, 'wb') as f:
        f.write(data)

    print(f"\nDone! Successfully updated {modified_count} texture palette(s) in {mdl_path}.")

if __name__ == '__main__':
    main()
