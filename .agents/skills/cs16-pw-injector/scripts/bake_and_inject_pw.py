#!/usr/bin/env python3
"""
bake_and_inject_pw.py - Bake viewmodel (v_*.mdl) skin textures & decals and inject into p_*.mdl and w_*.mdl.
GoldSrc Engine StudioModel format compatible.
"""

import argparse
import os
import shutil
import struct
import sys
import numpy as np
from PIL import Image

def parse_args():
    parser = argparse.ArgumentParser(description="Bake v_model skins/decals and inject into p_ and w_ models.")
    parser.add_argument("-w", "--weapon", help="Weapon base name (e.g., deagle, ak47, usp)")
    parser.add_argument("--v-model", help="Path to viewmodel (v_*.mdl)")
    parser.add_argument("--p-model", help="Path to player model (p_*.mdl)")
    parser.add_argument("--w-model", help="Path to world model (w_*.mdl)")
    parser.add_argument("-d", "--dir", default="cstrike_hd/models", help="Directory where models are located (default: cstrike_hd/models)")
    parser.add_argument("--no-backup", action="store_true", help="Do not create .bak backup files before modifying")
    return parser.parse_args()

def resolve_models(args):
    dir_path = args.dir
    v_path = args.v_model
    p_path = args.p_model
    w_path = args.w_model

    if args.weapon:
        wep = args.weapon.lower()
        if wep.startswith("v_") or wep.startswith("p_") or wep.startswith("w_"):
            wep = wep[2:]
        if wep.endswith(".mdl"):
            wep = wep[:-4]
            
        if not v_path:
            v_path = os.path.join(dir_path, f"v_{wep}.mdl")
        if not p_path:
            p_path = os.path.join(dir_path, f"p_{wep}.mdl")
        if not w_path:
            w_path = os.path.join(dir_path, f"w_{wep}.mdl")

    if not v_path or not os.path.isfile(v_path):
        raise FileNotFoundError(f"View model not found: {v_path}")

    return os.path.abspath(v_path), p_path, w_path

def read_model_textures(data):
    if len(data) < 200:
        raise ValueError("Model data too short")
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
            'index': i,
            'name': tname_str,
            'flags': flags,
            'w': w,
            'h': h,
            'offset': idx,
            'size': size,
            'pixels': data[idx:idx + w * h],
            'palette': data[idx + w * h:idx + size]
        })
    return textures

def bake_weapon_texture(v_textures, target_tex_name):
    # Find matching base texture in v_model
    base_tex = None
    for t in v_textures:
        if t['name'].lower() == target_tex_name.lower():
            base_tex = t
            break

    if not base_tex:
        # Fallback: search for non-glove, non-decal texture
        for t in v_textures:
            tname = t['name'].lower()
            if not any(k in tname for k in ['sport', 'glove', 'hand', 'arm', 'decal']):
                base_tex = t
                break

    if not base_tex:
        raise ValueError(f"Could not find a base weapon texture matching '{target_tex_name}' in viewmodel")

    w, h = base_tex['w'], base_tex['h']
    img_base = Image.frombytes('P', (w, h), base_tex['pixels'])
    img_base.putpalette(base_tex['palette'])
    composite = img_base.convert('RGBA')

    # Look for decals to overlay
    for t in v_textures:
        tname = t['name'].lower()
        is_decal = 'decal' in tname or (t['flags'] & 0x40) != 0
        if is_decal and t['w'] == w and t['h'] == h:
            dec_img = Image.frombytes('P', (w, h), t['pixels'])
            dec_img.putpalette(t['palette'])
            dec_rgba = np.array(dec_img.convert('RGBA'))
            
            # GoldSrc masked texture transparency: palette index 255 is transparent
            pixels_arr = np.frombuffer(t['pixels'], dtype=np.uint8).reshape((h, w))
            dec_rgba[pixels_arr == 255, 3] = 0
            
            dec_layer = Image.fromarray(dec_rgba)
            composite = Image.alpha_composite(composite, dec_layer)
            print(f"Baking decal layer: {t['name']}")

    final_rgb = composite.convert('RGB')
    quantized = final_rgb.quantize(colors=256, method=Image.Resampling.LANCZOS)
    
    pal = bytearray(quantized.getpalette()[:768])
    if len(pal) < 768:
        pal.extend(b'\x00' * (768 - len(pal)))
    pixels = quantized.tobytes()

    return bytes(pixels) + bytes(pal), base_tex['name']

def inject_into_model(mdl_path, target_tex_name, payload, no_backup):
    if not os.path.isfile(mdl_path):
        print(f"Skipping {mdl_path} (file does not exist)")
        return

    if not no_backup:
        bak_path = mdl_path + ".bak"
        if not os.path.exists(bak_path):
            shutil.copy2(mdl_path, bak_path)
            print(f"Created backup: {bak_path}")

    with open(mdl_path, 'rb') as f:
        data = bytearray(f.read())

    textures = read_model_textures(data)
    replaced = False
    for t in textures:
        # Match by name or if there's only 1 texture in p/w model
        if len(textures) == 1 or t['name'].lower() == target_tex_name.lower():
            if len(payload) != t['size']:
                print(f"Warning: Size mismatch for {t['name']} in {mdl_path} ({len(payload)} vs {t['size']}). Skipping.", file=sys.stderr)
                return
            idx = t['offset']
            data[idx:idx + t['size']] = payload
            replaced = True
            print(f"[{os.path.basename(mdl_path)}] Replaced texture '{t['name']}' at offset {idx}")
            break

    if replaced:
        with open(mdl_path, 'wb') as f:
            f.write(data)
        print(f"Saved: {mdl_path}")
    else:
        print(f"Warning: Could not match texture in {mdl_path}", file=sys.stderr)

def main():
    args = parse_args()
    try:
        v_path, p_path, w_path = resolve_models(args)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

    print(f"Reading View Model: {v_path}")
    with open(v_path, 'rb') as f:
        v_bytes = f.read()

    v_textures = read_model_textures(v_bytes)
    
    # Determine target texture name from p_model if available
    target_tex_name = "pist_deagle.bmp"
    if p_path and os.path.isfile(p_path):
        with open(p_path, 'rb') as f:
            p_bytes = f.read()
        p_tex = read_model_textures(p_bytes)
        if p_tex:
            target_tex_name = p_tex[0]['name']

    payload, matched_name = bake_weapon_texture(v_textures, target_tex_name)
    print(f"Baked composite texture from: '{matched_name}' ({len(payload)} bytes)")

    if p_path:
        inject_into_model(p_path, matched_name, payload, args.no_backup)
    if w_path:
        inject_into_model(w_path, matched_name, payload, args.no_backup)

    print("\nDone! P & W model injection complete.")

if __name__ == '__main__':
    main()
