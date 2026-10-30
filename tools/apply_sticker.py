#!/usr/bin/env python3
"""
apply_sticker.py - CS2 Sticker Studio & Scaler Engine for Counter-Strike 1.6 Models.

Features:
- Transparent PNG sticker scaling (1.0x - 2.0x multiplier) using Lanczos antialiased resampling.
- Mode A (2D Texture Baking): Composites the scaled sticker directly onto the 512x512
  weapon body texture at preset locations (wood, body, mag, scope, stock) or custom X,Y.
- Mode B (3D Sticker Submesh): Injects the scaled sticker directly into dedicated sticker
  submeshes (sticker_1..sticker_4) with Foil/Chrome shine (0x42), Matte (0x40), or Glow (0x60).
"""

import argparse
import os
import shutil
import struct
import sys
from PIL import Image
import numpy as np

# Standard preset positions (X, Y) on a 512x512 weapon texture canvas
PRESET_POSITIONS = {
    'ak47': {
        'wood': (180, 240),
        'body': (280, 230),
        'mag': (310, 360),
        'stock': (40, 260)
    },
    'm4a1': {
        'body': (250, 220),
        'mag': (260, 340),
        'barrel': (390, 180),
        'stock': (90, 230)
    },
    'm4a4': {
        'body': (250, 220),
        'mag': (260, 340),
        'barrel': (390, 180),
        'stock': (90, 230)
    },
    'awp': {
        'scope': (250, 100),
        'body': (240, 260),
        'stock': (80, 280),
        'front': (380, 240)
    },
    'deagle': {
        'slide': (230, 180),
        'grip': (160, 320),
        'front': (340, 180)
    },
    'usp': {
        'slide': (220, 180),
        'grip': (150, 320),
        'silencer': (360, 180)
    },
    'glock18': {
        'slide': (230, 180),
        'grip': (160, 320)
    }
}

def parse_args():
    parser = argparse.ArgumentParser(
        description="Scale transparent PNG stickers and apply to CS 1.6 weapon models."
    )
    parser.add_argument("-w", "--weapon", required=True,
                        help="Weapon name (ak47, m4a1, awp, deagle) or model path (v_*.mdl)")
    parser.add_argument("-s", "--sticker", required=True,
                        help="Path to transparent PNG sticker file")
    parser.add_argument("--scale", type=float, default=1.0,
                        help="Scale factor multiplier (e.g. 1.0, 1.25, 1.5, 2.0; default: 1.0)")
    parser.add_argument("-m", "--mode", choices=['bake', 'submesh'], default='bake',
                        help="Mode: 'bake' (composites on weapon texture) or 'submesh' (injects into 3D sticker submesh)")
    parser.add_argument("--slot", default="body",
                        help="Placement slot: preset name (wood, body, mag, scope, stock) or submesh index (1, 2, 3, 4)")
    parser.add_argument("--pos", default=None,
                        help="Custom X,Y pixel coordinates on canvas (e.g. --pos 250,220)")
    parser.add_argument("--fx", choices=['foil', 'chrome', 'matte', 'glow'], default='foil',
                        help="Visual finish for submesh mode: foil/chrome (0x42), matte (0x40), glow (0x60)")
    parser.add_argument("-o", "--output", default=None,
                        help="Output model path (if omitted, modifies model in place)")
    parser.add_argument("--no-backup", action="store_true",
                        help="Do not create a .bak backup file")
    parser.add_argument("--alpha-thresh", type=int, default=128,
                        help="Alpha cutoff threshold for submesh mode (0-255, default: 128)")
    return parser.parse_args()

def resolve_model_path(path_or_name):
    if os.path.isfile(path_or_name):
        return os.path.abspath(path_or_name)

    base = os.path.basename(path_or_name).lower()
    if not base.startswith("v_"):
        base = "v_" + base
    if not base.endswith(".mdl"):
        base = base + ".mdl"

    candidates = [
        os.path.join("cstrike", "models", "custom_skins", "ct", base),
        os.path.join("cstrike", "models", "custom_skins", "t", base),
        os.path.join("cstrike", "models", "inventory", "ct", base),
        os.path.join("cstrike", "models", "inventory", "t", base),
        os.path.join("cstrike", "models", "csgo_skins", "ct", base),
        os.path.join("cstrike", "models", "csgo_skins", "t", base),
        os.path.join("cstrike", "models", base),
    ]

    for c in candidates:
        if os.path.isfile(c):
            return os.path.abspath(c)

    for root, _, files in os.walk(os.path.join("cstrike", "models")):
        for f in files:
            if f.lower() == base:
                return os.path.abspath(os.path.join(root, f))

    raise FileNotFoundError(f"Model file '{path_or_name}' not found.")

def read_mdl_textures(data):
    magic, ver = struct.unpack_from('<4sI', data, 0)
    if magic != b'IDST' or ver != 10:
        raise ValueError(f"Invalid GoldSrc StudioModel (magic={magic}, ver={ver})")

    numtextures, textureindex = struct.unpack_from('<II', data, 180)
    textures = []
    for i in range(numtextures):
        offset = textureindex + i * 80
        tname, flags, w, h, idx = struct.unpack_from('<64sIIII', data, offset)
        tname_str = tname.split(b'\x00')[0].decode('latin1', errors='ignore')
        size = w * h + 768
        textures.append({
            'index': i,
            'header_offset': offset,
            'name': tname_str,
            'flags': flags,
            'w': w,
            'h': h,
            'data_offset': idx,
            'size': size,
            'data': data[idx:idx + size]
        })
    return textures

def is_weapon_body_texture(tname):
    lower = tname.lower()
    excluded = ['sleeve', 'arm', 'bare_arm', 'sport', 'glove', 'hand', 'finger', 'sticker', 'stattrak', 'stat_']
    return not any(ex in lower for ex in excluded)

def is_sticker_texture(tname):
    lower = tname.lower()
    return 'sticker' in lower or (lower.endswith('.bmp') and lower[:-4].isdigit())

def prepare_scaled_sticker(sticker_path, target_base_size, scale):
    """
    Loads sticker PNG, computes scaled size based on scale multiplier,
    and returns RGBA Image.
    """
    if not os.path.isfile(sticker_path):
        raise FileNotFoundError(f"Sticker file not found: {sticker_path}")

    img = Image.open(sticker_path).convert('RGBA')

    # Desired base dimensions (e.g. 128x128 scaled by multiplier)
    aspect = img.height / float(img.width) if img.width > 0 else 1.0
    final_w = int(target_base_size * scale)
    final_h = int(final_w * aspect)

    print(f"  Scaling sticker '{os.path.basename(sticker_path)}': {img.width}x{img.height} -> {final_w}x{final_h} ({scale:.2f}x scale)")
    scaled_sticker = img.resize((final_w, final_h), Image.Resampling.LANCZOS)
    return scaled_sticker

def apply_mode_bake(mdl_data, textures, weapon_key, sticker_path, slot, custom_pos, scale):
    """
    Mode A: Composites the scaled sticker onto the weapon body texture.
    """
    weapon_tex = [t for t in textures if is_weapon_body_texture(t['name'])]
    if not weapon_tex:
        raise ValueError("Could not find weapon body texture to composite sticker onto.")

    target_tex = max(weapon_tex, key=lambda t: t['w'] * t['h'])
    tw, th = target_tex['w'], target_tex['h']
    print(f"\n[Mode: Bake] Target weapon texture: '{target_tex['name']}' ({tw}x{th})")

    # Extract base texture as RGBA
    pixels = mdl_data[target_tex['data_offset']:target_tex['data_offset'] + (tw * th)]
    palette = mdl_data[target_tex['data_offset'] + (tw * th):target_tex['data_offset'] + target_tex['size']]

    base_p = Image.frombytes('P', (tw, th), bytes(pixels))
    base_p.putpalette(bytes(palette))
    base_rgba = base_p.convert('RGBA')

    # Determine placement position
    pos_x, pos_y = 200, 200
    if custom_pos:
        try:
            parts = custom_pos.split(',')
            pos_x, pos_y = int(parts[0]), int(parts[1])
        except Exception:
            print(f"Warning: Could not parse --pos '{custom_pos}'. Falling back to default.")
    elif weapon_key in PRESET_POSITIONS and slot.lower() in PRESET_POSITIONS[weapon_key]:
        pos_x, pos_y = PRESET_POSITIONS[weapon_key][slot.lower()]
        print(f"  Using preset position '{slot}' for {weapon_key}: ({pos_x}, {pos_y})")
    else:
        print(f"  Slot '{slot}' not found in presets for {weapon_key}. Using center-left offset.")
        pos_x = int(tw * 0.4)
        pos_y = int(th * 0.45)

    # Base sticker dimension ~128px relative to 512x512
    base_size = int(tw * 0.25)
    sticker_img = prepare_scaled_sticker(sticker_path, base_size, scale)

    # Ensure sticker fits on canvas
    if pos_x + sticker_img.width > tw:
        pos_x = max(0, tw - sticker_img.width)
    if pos_y + sticker_img.height > th:
        pos_y = max(0, th - sticker_img.height)

    # Composite sticker
    composite = base_rgba.copy()
    composite.paste(sticker_img, (pos_x, pos_y), sticker_img)

    # Quantize to 256 colors
    rgb_img = composite.convert('RGB')
    q_img = rgb_img.quantize(colors=256, method=Image.Quantize.MEDIANCUT)

    raw_palette = list(q_img.getpalette() or [])
    while len(raw_palette) < 768:
        raw_palette.extend([0, 0, 0])
    raw_palette = raw_palette[:768]

    new_data = q_img.tobytes() + bytes(raw_palette)
    offset = target_tex['data_offset']
    mdl_data[offset:offset + target_tex['size']] = new_data
    print(f"  Composited scaled sticker at ({pos_x}, {pos_y}) into '{target_tex['name']}' successfully.")

def apply_mode_submesh(mdl_data, textures, sticker_path, slot, scale, fx_mode, alpha_thresh):
    """
    Mode B: Injects the scaled sticker into a dedicated 3D sticker submesh.
    """
    sticker_textures = [t for t in textures if is_sticker_texture(t['name'])]
    if not sticker_textures:
        raise ValueError("No sticker submeshes found in this model! Use '--mode bake' instead.")

    print(f"\n[Mode: Submesh] Found {len(sticker_textures)} sticker submesh(es): {[t['name'] for t in sticker_textures]}")

    # Match target slot
    target_tex = None
    if slot.isdigit():
        idx = int(slot)
        for t in sticker_textures:
            if str(idx) in t['name']:
                target_tex = t
                break
    else:
        for t in sticker_textures:
            if slot.lower() in t['name'].lower():
                target_tex = t
                break

    if not target_tex:
        target_tex = sticker_textures[0]

    tw, th = target_tex['w'], target_tex['h']
    print(f"  Target submesh: '{target_tex['name']}' ({tw}x{th})")

    # Load and scale sticker to fit submesh preserving native aspect ratio
    sticker_img = Image.open(sticker_path).convert('RGBA')
    orig_w, orig_h = sticker_img.width, sticker_img.height
    aspect = orig_w / float(orig_h) if orig_h > 0 else 1.0

    # Base fit factor relative to submesh canvas (0.75 at scale 1.0)
    base_dim = int(min(tw, th) * 0.75 * scale)
    if aspect >= 1.0:
        target_w = max(16, base_dim)
        target_h = max(16, int(target_w / aspect))
    else:
        target_h = max(16, base_dim)
        target_w = max(16, int(target_h * aspect))

    # Align to multiples of 4 for clean GoldSrc rasterization
    target_w = max(16, (target_w // 4) * 4)
    target_h = max(16, (target_h // 4) * 4)

    print(f"  Scaling sticker for submesh: {orig_w}x{orig_h} -> {target_w}x{target_h} (scale={scale:.2f}x, aspect={aspect:.2f})")
    scaled_sticker = sticker_img.resize((target_w, target_h), Image.Resampling.LANCZOS)

    # Place centered on submesh canvas (tw x th) with transparent background
    canvas = Image.new('RGBA', (tw, th), (0, 0, 255, 0)) # Pure blue transparent
    off_x = (tw - target_w) // 2
    off_y = (th - target_h) // 2
    canvas.paste(scaled_sticker, (off_x, off_y), scaled_sticker)

    # Convert to GoldSrc 8-bit indexed with Blue Mask at Index 255
    alpha = np.array(canvas.split()[-1])
    rgb_img = canvas.convert('RGB')
    q_img = rgb_img.quantize(colors=255, method=Image.Quantize.MEDIANCUT)

    raw_palette = list(q_img.getpalette() or [])[:255 * 3]
    while len(raw_palette) < 255 * 3:
        raw_palette.extend([0, 0, 0])
    raw_palette.extend([0, 0, 255]) # Slot 255 is pure blue RGB(0,0,255)

    pixels = np.array(q_img)
    pixels[alpha < alpha_thresh] = 255 # Masked transparency

    result = Image.fromarray(pixels, mode='P')
    result.putpalette(raw_palette)

    new_data = result.tobytes() + bytes(raw_palette)
    offset = target_tex['data_offset']
    mdl_data[offset:offset + target_tex['size']] = new_data

    # Set rendering flags
    flag_offset = target_tex['header_offset'] + 64
    if fx_mode in ['foil', 'chrome']:
        new_flag = 0x42 # STUDIO_NF_CHROME | STUDIO_NF_MASKED
        struct.pack_into('<I', mdl_data, flag_offset, new_flag)
        print(f"  Applied Foil/Chrome effect: flags=0x{new_flag:02X}")
    elif fx_mode == 'matte':
        new_flag = 0x40 # STUDIO_NF_MASKED
        struct.pack_into('<I', mdl_data, flag_offset, new_flag)
        print(f"  Applied Matte decal effect: flags=0x{new_flag:02X}")
    elif fx_mode == 'glow':
        new_flag = 0x60 # STUDIO_NF_ADDITIVE | STUDIO_NF_MASKED
        struct.pack_into('<I', mdl_data, flag_offset, new_flag)
        print(f"  Applied Glow effect: flags=0x{new_flag:02X}")

    print(f"  Successfully injected sticker into submesh '{target_tex['name']}'")

def main():
    args = parse_args()
    mdl_path = resolve_model_path(args.weapon)
    output_path = args.output or mdl_path

    weapon_key = os.path.basename(mdl_path).lower().replace("v_", "").replace(".mdl", "")
    for k in PRESET_POSITIONS:
        if k in weapon_key:
            weapon_key = k
            break

    print(f"Target Model : {mdl_path}")
    print(f"Sticker File : {args.sticker}")
    print(f"Scale        : {args.scale:.2f}x")
    print(f"Mode         : {args.mode.upper()}")

    # Backup if modifying in place
    if not args.no_backup and output_path == mdl_path:
        bak_path = mdl_path + ".bak"
        if not os.path.exists(bak_path):
            shutil.copy2(mdl_path, bak_path)
            print(f"Created backup: {bak_path}")

    with open(mdl_path, 'rb') as f:
        mdl_data = bytearray(f.read())

    textures = read_mdl_textures(mdl_data)

    if args.mode == 'bake':
        apply_mode_bake(mdl_data, textures, weapon_key, args.sticker, args.slot, args.pos, args.scale)
    else:
        apply_mode_submesh(mdl_data, textures, args.sticker, args.slot, args.scale, args.fx, args.alpha_thresh)

    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
    with open(output_path, 'wb') as f:
        f.write(mdl_data)

    print(f"\n[Done] Saved updated model to: {output_path}")

if __name__ == '__main__':
    main()
