#!/usr/bin/env python3
"""
inject_gloves.py - Transfer glove and arm textures between Counter-Strike 1.6 viewmodels (v_*.mdl).
GoldSrc Engine StudioModel format compatible.
"""

import argparse
import os
import shutil
import struct
import sys

def parse_args():
    parser = argparse.ArgumentParser(description="Transfer glove & arm textures between CS 1.6 viewmodels.")
    parser.add_argument("-t", "--target", required=True, help="Target viewmodel path or weapon name (e.g., deagle or v_deagle.mdl)")
    parser.add_argument("-s", "--source", default="awp", help="Source viewmodel path or weapon name with preferred gloves (default: awp)")
    parser.add_argument("-d", "--dir", default="cstrike_hd/models", help="Directory where models are located (default: cstrike_hd/models)")
    parser.add_argument("--no-backup", action="store_true", help="Do not create a .bak backup file before modifying")
    return parser.parse_args()

def resolve_model_path(path_or_name, default_dir):
    if os.path.isfile(path_or_name):
        return os.path.abspath(path_or_name)
    name = path_or_name
    if not name.startswith("v_"):
        name = "v_" + name
    if not name.endswith(".mdl"):
        name = name + ".mdl"
    
    candidate = os.path.join(default_dir, name)
    if os.path.isfile(candidate):
        return os.path.abspath(candidate)
    
    # Try cstrike/models as fallback
    fallback = os.path.join("cstrike", "models", name)
    if os.path.isfile(fallback):
        return os.path.abspath(fallback)
        
    raise FileNotFoundError(f"Could not find model file for '{path_or_name}'. Checked: '{candidate}', '{fallback}'")

def read_textures(data):
    if len(data) < 200:
        raise ValueError("Model data too short")
    magic, ver = struct.unpack_from('<4sI', data, 0)
    if magic != b'IDST' or ver != 10:
        raise ValueError(f"Invalid GoldSrc MDL header (magic={magic}, ver={ver})")
    
    numtextures, textureindex = struct.unpack_from('<II', data, 180)
    textures = {}
    for i in range(numtextures):
        offset = textureindex + i * 80
        tname, flags, w, h, idx = struct.unpack_from('<64sIIII', data, offset)
        tname_str = tname.split(b'\x00')[0].decode('latin1', errors='ignore')
        size = w * h + 768
        textures[tname_str] = {
            'index': i,
            'name': tname_str,
            'flags': flags,
            'w': w,
            'h': h,
            'offset': idx,
            'size': size,
            'data': data[idx:idx + size]
        }
    return textures

def classify_role(tname):
    lower = tname.lower()
    is_hand = any(k in lower for k in ['sport', 'glove', 'hand'])
    is_arm = any(k in lower for k in ['arm', 'sleeve'])
    if 'left' in lower and is_hand:
        return 'left_glove'
    if 'right' in lower and is_hand:
        return 'right_glove'
    if is_arm:
        return 'arm'
    return None

def main():
    args = parse_args()
    
    try:
        source_path = resolve_model_path(args.source, args.dir)
        target_path = resolve_model_path(args.target, args.dir)
    except FileNotFoundError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

    print(f"Source Model : {source_path}")
    print(f"Target Model : {target_path}")

    with open(source_path, 'rb') as f:
        src_bytes = f.read()
    with open(target_path, 'rb') as f:
        tgt_bytes = bytearray(f.read())

    src_textures = read_textures(src_bytes)
    tgt_textures = read_textures(tgt_bytes)

    # 1. First try exact name matching for gloves/arms
    pairs = [] # (src_info, tgt_info)
    glove_keywords = ['sport', 'glove', 'hand', 'arm', 'sleeve']
    for k in tgt_textures:
        if any(w in k.lower() for w in glove_keywords):
            if k in src_textures:
                pairs.append((src_textures[k], tgt_textures[k]))

    # 2. If no exact match or partial, match by role (left_glove, right_glove, arm)
    if not pairs:
        src_roles = {}
        for k, v in src_textures.items():
            r = classify_role(k)
            if r and r not in src_roles:
                src_roles[r] = v
        
        for k, v in tgt_textures.items():
            r = classify_role(k)
            if r and r in src_roles:
                pairs.append((src_roles[r], v))

    if not pairs:
        print("No matching glove/arm texture pairs found between source and target models.", file=sys.stderr)
        print("Target textures:", list(tgt_textures.keys()))
        print("Source textures:", list(src_textures.keys()))
        sys.exit(1)

    # Filter out size mismatches
    valid_pairs = []
    for s_info, t_info in pairs:
        if s_info['size'] == t_info['size']:
            valid_pairs.append((s_info, t_info))
        else:
            print(f"Warning: Size mismatch ('{s_info['name']}' {s_info['w']}x{s_info['h']} vs '{t_info['name']}' {t_info['w']}x{t_info['h']}). Skipping.")

    if not valid_pairs:
        print("Error: All glove/arm texture pairs had dimension/size mismatches.", file=sys.stderr)
        sys.exit(1)

    # Create backup
    if not args.no_backup:
        bak_path = target_path + ".bak"
        if not os.path.exists(bak_path):
            shutil.copy2(target_path, bak_path)
            print(f"Created backup: {bak_path}")
        else:
            print(f"Backup already exists: {bak_path}")

    # Transfer each texture
    for s_info, t_info in valid_pairs:
        tgt_offset = t_info['offset']
        tgt_bytes[tgt_offset:tgt_offset + t_info['size']] = s_info['data']
        print(f"Successfully transferred '{s_info['name']}' -> '{t_info['name']}' ({s_info['w']}x{s_info['h']})")

    with open(target_path, 'wb') as f:
        f.write(tgt_bytes)

    print(f"\nDone! Updated target model: {target_path}")

if __name__ == '__main__':
    main()
