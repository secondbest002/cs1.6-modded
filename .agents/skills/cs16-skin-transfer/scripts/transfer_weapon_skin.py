#!/usr/bin/env python3
"""
transfer_weapon_skin.py - Transfer weapon body skin from a donor/collection model (v_*_usethis.mdl)
to an active viewmodel while strictly preserving custom animations, gloves, stickers, and StatTrak.
Optionally synchronizes with p_ and w_ models.
"""

import argparse
import os
import shutil
import struct
import sys

def parse_args():
    parser = argparse.ArgumentParser(description="Transfer weapon skin between CS 1.6 models preserving animations, gloves, and stickers.")
    parser.add_argument("-t", "--target", required=True, help="Target weapon or model path (e.g., ak47, v_ak47.mdl)")
    parser.add_argument("-s", "--source", required=True, help="Source/donor weapon or model path (e.g., v_ak47_usethis.mdl)")
    parser.add_argument("-d", "--dir", default="cstrike_hd/models", help="Directory where models are located (default: cstrike_hd/models)")
    parser.add_argument("--sync-pw", action="store_true", help="Also sync the new skin into p_ and w_ models")
    parser.add_argument("--no-backup", action="store_true", help="Do not create .bak backup files")
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

def read_textures(data):
    magic, ver = struct.unpack_from('<4sI', data, 0)
    if magic != b'IDST' or ver != 10:
        raise ValueError(f"Invalid GoldSrc MDL header (magic={magic}, ver={ver})")
    numtextures, textureindex = struct.unpack_from('<II', data, 180)
    textures = []
    for i in range(numtextures):
        offset = textureindex + i * 80
        tname, flags, w, h, idx = struct.unpack_from('<64sIIII', data, offset)
        tname_str = tname.split(b'\x00')[0].decode('latin1', errors='ignore')
        size = w * h + 768
        textures.append({
            'name': tname_str,
            'flags': flags,
            'w': w,
            'h': h,
            'offset': idx,
            'size': size,
            'data': data[idx:idx + size]
        })
    return textures

def is_weapon_texture(tname):
    lower = tname.lower()
    excluded = ['sport', 'glove', 'hand', 'arm', 'sleeve', 'sticker', 'stattrak', 'decal']
    return not any(ex in lower for ex in excluded)

def replace_texture_in_file(mdl_path, target_tex_name, new_data, no_backup):
    if not os.path.isfile(mdl_path):
        return False
    if not no_backup:
        bak_path = mdl_path + ".bak"
        if not os.path.exists(bak_path):
            shutil.copy2(mdl_path, bak_path)
            print(f"Created backup: {bak_path}")

    with open(mdl_path, 'rb') as f:
        data = bytearray(f.read())

    textures = read_textures(data)
    replaced = False
    for t in textures:
        if t['name'].lower() == target_tex_name.lower():
            if len(new_data) != t['size']:
                print(f"Size mismatch in {mdl_path} for {t['name']}: {len(new_data)} vs {t['size']}", file=sys.stderr)
                return False
            data[t['offset']:t['offset'] + t['size']] = new_data
            replaced = True
            print(f"[{os.path.basename(mdl_path)}] Replaced '{t['name']}' at offset {t['offset']}")
            break

    if replaced:
        with open(mdl_path, 'wb') as f:
            f.write(data)
        print(f"Saved: {mdl_path}")
    return replaced

def main():
    args = parse_args()
    try:
        src_path = resolve_model_path(args.source, args.dir, prefix="v_")
        tgt_path = resolve_model_path(args.target, args.dir, prefix="v_")
    except Exception as e:
        print(f"Error resolving paths: {e}", file=sys.stderr)
        sys.exit(1)

    print(f"Source Model : {src_path}")
    print(f"Target Model : {tgt_path}")

    with open(src_path, 'rb') as f:
        src_bytes = f.read()
    with open(tgt_path, 'rb') as f:
        tgt_bytes = bytearray(f.read())

    src_textures = read_textures(src_bytes)
    tgt_textures = read_textures(tgt_bytes)

    # Find candidate weapon body textures
    tgt_weapon_tex = [t for t in tgt_textures if is_weapon_texture(t['name'])]
    src_weapon_tex = [t for t in src_textures if is_weapon_texture(t['name'])]

    if not tgt_weapon_tex or not src_weapon_tex:
        print("Error: Could not identify weapon body texture.", file=sys.stderr)
        print("Target textures:", [t['name'] for t in tgt_textures])
        print("Source textures:", [t['name'] for t in src_textures])
        sys.exit(1)

    # Match by name first, or pick the first candidate
    matched_src = None
    matched_tgt = None
    for t_tgt in tgt_weapon_tex:
        for t_src in src_weapon_tex:
            if t_tgt['name'].lower() == t_src['name'].lower() and t_tgt['size'] == t_src['size']:
                matched_tgt = t_tgt
                matched_src = t_src
                break
        if matched_tgt:
            break

    if not matched_tgt:
        # Fallback to first compatible size
        for t_tgt in tgt_weapon_tex:
            for t_src in src_weapon_tex:
                if t_tgt['size'] == t_src['size']:
                    matched_tgt = t_tgt
                    matched_src = t_src
                    break
            if matched_tgt:
                break

    if not matched_tgt:
        print("Error: No size-compatible weapon texture found between source and target.", file=sys.stderr)
        sys.exit(1)

    print(f"\nTransferring weapon texture: '{matched_src['name']}' -> '{matched_tgt['name']}' ({matched_src['w']}x{matched_src['h']})")
    print("Preserving gloves, arm, stickers, StatTrak, and custom recoil animations untouched.")

    if not args.no_backup:
        bak_path = tgt_path + ".bak"
        if not os.path.exists(bak_path):
            shutil.copy2(tgt_path, bak_path)
            print(f"Created backup: {bak_path}")

    tgt_bytes[matched_tgt['offset']:matched_tgt['offset'] + matched_tgt['size']] = matched_src['data']
    with open(tgt_path, 'wb') as f:
        f.write(tgt_bytes)
    print(f"Successfully updated target viewmodel: {tgt_path}")

    # Synchronize p_ and w_ models if requested
    if args.sync_pw:
        base_name = os.path.basename(tgt_path)
        if base_name.startswith("v_"):
            wep_core = base_name[2:-4]
            dir_name = os.path.dirname(tgt_path)
            p_path = os.path.join(dir_name, f"p_{wep_core}.mdl")
            w_path = os.path.join(dir_name, f"w_{wep_core}.mdl")

            if os.path.isfile(p_path):
                replace_texture_in_file(p_path, matched_tgt['name'], matched_src['data'], args.no_backup)
            if os.path.isfile(w_path):
                replace_texture_in_file(w_path, matched_tgt['name'], matched_src['data'], args.no_backup)

    print("\nSkin transfer complete!")

if __name__ == '__main__':
    main()
