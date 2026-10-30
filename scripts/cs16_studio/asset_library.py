"""
asset_library.py - Built-in Sticker & Skin Asset Library Manager & Procedural Generator.
Provides instant access to iconic tournament/pro stickers and custom skins without manual file browsing.
"""

import base64
import io
import json
import math
import os
from pathlib import Path
import re
from typing import Dict, List, Optional, Tuple, Union
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter


STICKER_DEFINITIONS = [
    {
        "filename": "titan_holo.png",
        "name": "Titan Holo",
        "category": "Katowice 2014 Holo",
        "badge_color": (0, 162, 232),
        "accent_color": (0, 220, 255),
    },
    {
        "filename": "ibuypower_holo.png",
        "name": "iBUYPOWER Holo",
        "category": "Katowice 2014 Holo",
        "badge_color": (220, 20, 40),
        "accent_color": (255, 100, 20),
    },
    {
        "filename": "navi_holo.png",
        "name": "Natus Vincere Holo",
        "category": "Tournament Holo",
        "badge_color": (255, 215, 0),
        "accent_color": (255, 240, 50),
    },
    {
        "filename": "crown_foil.png",
        "name": "Crown (Foil)",
        "category": "Foil Collection",
        "badge_color": (245, 190, 30),
        "accent_color": (255, 230, 120),
    },
    {
        "filename": "howling_dawn.png",
        "name": "Howling Dawn",
        "category": "Contraband Decal",
        "badge_color": (210, 40, 30),
        "accent_color": (255, 120, 40),
    },
    {
        "filename": "cloud9_holo.png",
        "name": "Cloud9 Holo",
        "category": "Tournament Holo",
        "badge_color": (0, 174, 239),
        "accent_color": (120, 220, 255),
    },
    {
        "filename": "dignitas_holo.png",
        "name": "Team Dignitas Holo",
        "category": "Katowice 2014 Holo",
        "badge_color": (245, 210, 20),
        "accent_color": (180, 240, 40),
    },
    {
        "filename": "virtus_pro_holo.png",
        "name": "Virtus.Pro Holo",
        "category": "Katowice 2014 Holo",
        "badge_color": (255, 102, 0),
        "accent_color": (255, 160, 50),
    },
]


def _create_holo_gradient(size: int = 512) -> Image.Image:
    """Creates a subtle prismatic rainbow holographic glow."""
    cx, cy = size // 2, size // 2
    y, x = np.ogrid[:size, :size]
    dx = x - cx
    dy = y - cy
    dist = np.sqrt(dx * dx + dy * dy)
    angle = (np.arctan2(dy, dx) + np.pi) / (2 * np.pi)

    r = ((np.sin(angle * 6.28) * 0.5 + 0.5) * 200 + 55).astype(np.uint8)
    g = ((np.sin(angle * 6.28 + 2.09) * 0.5 + 0.5) * 200 + 55).astype(np.uint8)
    b = ((np.sin(angle * 6.28 + 4.18) * 0.5 + 0.5) * 200 + 55).astype(np.uint8)

    max_r = size * 0.48
    alpha = np.clip((1.0 - (dist / max_r)) * 60, 0, 60).astype(np.uint8)
    alpha[dist >= max_r] = 0

    arr = np.dstack([r, g, b, alpha])
    return Image.fromarray(arr, mode="RGBA")


def generate_titan_holo(size: int = 512) -> Image.Image:
    """Generates Katowice 2014 Titan Holo sticker badge."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Outer holographic glow
    holo = _create_holo_gradient(size)
    img.alpha_composite(holo)
    draw = ImageDraw.Draw(img)

    # Hexagonal / Diamond Shield
    cx, cy = size // 2, size // 2 - 15
    r = int(size * 0.40)
    points = []
    for i in range(6):
        angle = math.radians(60 * i - 30)
        points.append((cx + r * math.cos(angle), cy + r * math.sin(angle)))

    # Outer border
    draw.polygon(points, fill=(10, 25, 45, 230), outline=(0, 210, 255, 255), width=8)

    # Inner facets
    r_in = int(r * 0.88)
    inner_pts = []
    for i in range(6):
        angle = math.radians(60 * i - 30)
        inner_pts.append((cx + r_in * math.cos(angle), cy + r_in * math.sin(angle)))
    draw.polygon(inner_pts, fill=(15, 40, 75, 245), outline=(0, 160, 230, 200), width=3)

    # Stylized Bold 'T' Logo
    # Top bar
    bar_w = int(size * 0.46)
    bar_h = int(size * 0.11)
    bx = cx - bar_w // 2
    by = cy - int(size * 0.22)
    draw.polygon(
        [
            (bx + 15, by),
            (bx + bar_w - 15, by),
            (bx + bar_w, by + bar_h),
            (bx, by + bar_h),
        ],
        fill=(0, 230, 255, 255),
        outline=(255, 255, 255, 240),
    )

    # Stem with facet
    stem_w = int(size * 0.18)
    stem_h = int(size * 0.36)
    sx = cx - stem_w // 2
    sy = by + bar_h
    # Left facet
    draw.polygon(
        [(cx - stem_w // 2, sy), (cx, sy), (cx, sy + stem_h), (cx - stem_w // 4, sy + stem_h)],
        fill=(0, 180, 230, 255),
    )
    # Right facet
    draw.polygon(
        [(cx, sy), (cx + stem_w // 2, sy), (cx + stem_w // 4, sy + stem_h), (cx, sy + stem_h)],
        fill=(80, 240, 255, 255),
    )

    # Label Banner
    lbl_w = int(size * 0.62)
    lbl_h = int(size * 0.14)
    lx = cx - lbl_w // 2
    ly = size - lbl_h - 25
    draw.rounded_rectangle([lx, ly, lx + lbl_w, ly + lbl_h], radius=10, fill=(5, 15, 30, 245), outline=(0, 210, 255, 255), width=3)
    # Text
    draw.text((cx, ly + lbl_h // 2), "TITAN", fill=(255, 255, 255, 255), anchor="mm")

    return img


def generate_ibuypower_holo(size: int = 512) -> Image.Image:
    """Generates Katowice 2014 iBUYPOWER Holo sticker badge."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Holo background
    holo = _create_holo_gradient(size)
    img.alpha_composite(holo)
    draw = ImageDraw.Draw(img)

    cx, cy = size // 2, size // 2 - 20
    r = int(size * 0.40)

    # Shield background
    shield_pts = [
        (cx - r, cy - int(r * 0.7)),
        (cx + r, cy - int(r * 0.7)),
        (cx + int(r * 0.8), cy + int(r * 0.3)),
        (cx, cy + r),
        (cx - int(r * 0.8), cy + int(r * 0.3)),
    ]
    draw.polygon(shield_pts, fill=(25, 10, 10, 240), outline=(220, 20, 40, 255), width=8)

    # Roaring Tiger / Cougar Silhouette (bold flame head)
    head_pts = [
        (cx - 100, cy - 80),
        (cx - 40, cy - 110),
        (cx + 20, cy - 90),
        (cx + 90, cy - 100),
        (cx + 120, cy - 40),
        (cx + 80, cy + 10),
        (cx + 110, cy + 50),
        (cx + 40, cy + 80),
        (cx, cy + 100),
        (cx - 50, cy + 80),
        (cx - 30, cy + 40),
        (cx - 80, cy + 20),
        (cx - 110, cy - 20),
    ]
    draw.polygon(head_pts, fill=(220, 20, 40, 255), outline=(255, 120, 30, 255), width=4)

    # Sharp Fangs
    draw.polygon([(cx - 20, cy + 25), (cx - 5, cy + 65), (cx + 5, cy + 25)], fill=(255, 255, 255, 255))
    draw.polygon([(cx + 20, cy + 25), (cx + 35, cy + 65), (cx + 45, cy + 25)], fill=(255, 255, 255, 255))

    # Glowing eye
    draw.ellipse([cx - 40, cy - 40, cx - 15, cy - 20], fill=(255, 230, 0, 255))

    # Label Banner
    lbl_w = int(size * 0.76)
    lbl_h = int(size * 0.14)
    lx = cx - lbl_w // 2
    ly = size - lbl_h - 20
    draw.rounded_rectangle([lx, ly, lx + lbl_w, ly + lbl_h], radius=10, fill=(35, 5, 5, 245), outline=(255, 30, 50, 255), width=4)
    draw.text((cx, ly + lbl_h // 2), "iBUYPOWER", fill=(255, 255, 255, 255), anchor="mm")

    return img


def generate_navi_holo(size: int = 512) -> Image.Image:
    """Generates Natus Vincere Holo sticker badge."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    holo = _create_holo_gradient(size)
    img.alpha_composite(holo)
    draw = ImageDraw.Draw(img)

    cx, cy = size // 2, size // 2
    r = int(size * 0.42)

    # Hex shield
    pts = []
    for i in range(6):
        a = math.radians(60 * i)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    draw.polygon(pts, fill=(15, 15, 15, 240), outline=(255, 215, 0, 255), width=8)

    # NAVI Angular Emblem
    # Bold slanted polygons forming NAVI
    y_top = cy - 80
    y_bot = cy + 50

    # N
    draw.polygon([(cx - 150, y_bot), (cx - 150, y_top), (cx - 110, y_top), (cx - 70, y_bot - 40), (cx - 70, y_top), (cx - 40, y_top), (cx - 40, y_bot), (cx - 80, y_bot), (cx - 120, y_top + 40), (cx - 120, y_bot)], fill=(255, 215, 0, 255))
    # A
    draw.polygon([(cx - 25, y_bot), (cx + 10, y_top), (cx + 40, y_top), (cx + 75, y_bot), (cx + 45, y_bot), (cx + 25, y_bot - 35), (cx - 5, y_bot - 35), (cx - 15, y_bot)], fill=(255, 235, 50, 255))
    # VI
    draw.polygon([(cx + 90, y_top), (cx + 120, y_top), (cx + 140, y_bot), (cx + 115, y_bot)], fill=(255, 215, 0, 255))
    draw.polygon([(cx + 145, y_top), (cx + 170, y_top), (cx + 170, y_bot), (cx + 145, y_bot)], fill=(255, 215, 0, 255))

    # Banner
    lbl_w = int(size * 0.60)
    lbl_h = int(size * 0.12)
    lx = cx - lbl_w // 2
    ly = size - lbl_h - 30
    draw.rounded_rectangle([lx, ly, lx + lbl_w, ly + lbl_h], radius=8, fill=(20, 20, 20, 240), outline=(255, 215, 0, 255), width=3)
    draw.text((cx, ly + lbl_h // 2), "NATUS VINCERE", fill=(255, 235, 50, 255), anchor="mm")

    return img


def generate_crown_foil(size: int = 512) -> Image.Image:
    """Generates Crown (Foil) sticker badge."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    cx, cy = size // 2, size // 2

    # Circular royal seal backing
    r = int(size * 0.44)
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(20, 15, 5, 240), outline=(245, 190, 30, 255), width=8)

    # Laurel Wreath ring
    r_wreath = int(r * 0.88)
    draw.ellipse([cx - r_wreath, cy - r_wreath, cx + r_wreath, cy + r_wreath], outline=(255, 220, 80, 180), width=4)

    # 5-pointed Royal Crown
    cw_pts = [
        (cx - 150, cy + 40),   # Bottom-left
        (cx - 160, cy - 60),   # Point 1 (left)
        (cx - 90, cy - 10),    # Dip 1
        (cx - 70, cy - 100),   # Point 2
        (cx, cy - 20),         # Dip center
        (cx, cy - 130),        # Point 3 (Center top jewel)
        (cx, cy - 20),
        (cx + 70, cy - 100),   # Point 4
        (cx + 90, cy - 10),    # Dip 2
        (cx + 160, cy - 60),   # Point 5 (right)
        (cx + 150, cy + 40),   # Bottom-right
    ]
    draw.polygon(cw_pts, fill=(245, 190, 30, 255), outline=(255, 240, 140, 255), width=4)

    # Jewels on crown spires
    jewel_pts = [(cx - 160, cy - 60), (cx - 70, cy - 100), (cx, cy - 130), (cx + 70, cy - 100), (cx + 160, cy - 60)]
    for jx, jy in jewel_pts:
        draw.ellipse([jx - 12, jy - 12, jx + 12, jy + 12], fill=(255, 255, 255, 255), outline=(245, 190, 30, 255), width=2)

    # Center Skull emblem on crown base
    draw.ellipse([cx - 45, cy - 15, cx + 45, cy + 45], fill=(240, 240, 240, 255), outline=(100, 80, 20, 255), width=2)
    draw.rectangle([cx - 25, cy + 30, cx + 25, cy + 60], fill=(240, 240, 240, 255))
    # Eye sockets
    draw.ellipse([cx - 30, cy + 5, cx - 10, cy + 25], fill=(20, 15, 5, 255))
    draw.ellipse([cx + 10, cy + 5, cx + 30, cy + 25], fill=(20, 15, 5, 255))

    # Bottom Banner
    lbl_w = int(size * 0.58)
    lbl_h = int(size * 0.12)
    lx = cx - lbl_w // 2
    ly = size - lbl_h - 35
    draw.rounded_rectangle([lx, ly, lx + lbl_w, ly + lbl_h], radius=8, fill=(30, 20, 5, 245), outline=(255, 215, 0, 255), width=3)
    draw.text((cx, ly + lbl_h // 2), "CROWN (FOIL)", fill=(255, 235, 120, 255), anchor="mm")

    return img


def generate_howling_dawn(size: int = 512) -> Image.Image:
    """Generates Howling Dawn sticker badge."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    cx, cy = size // 2, size // 2

    # Circular fiery blood badge
    r = int(size * 0.44)
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(25, 8, 8, 240), outline=(220, 40, 20, 255), width=8)

    # Glowing red moon
    mr = int(r * 0.65)
    draw.ellipse([cx - mr + 30, cy - mr - 20, cx + mr + 30, cy + mr - 20], fill=(200, 30, 20, 180))

    # Howling Wolf Head Silhouette
    wolf_pts = [
        (cx - 130, cy + 130),
        (cx - 110, cy + 60),
        (cx - 70, cy + 10),
        (cx - 30, cy - 40),
        (cx + 30, cy - 140),   # Snout pointing up howling
        (cx + 50, cy - 135),
        (cx + 40, cy - 115),   # Lower jaw
        (cx + 10, cy - 65),
        (cx + 30, cy - 45),
        (cx + 80, cy - 20),    # Ear top
        (cx + 60, cy + 20),
        (cx + 110, cy + 60),
        (cx + 130, cy + 130),
    ]
    draw.polygon(wolf_pts, fill=(240, 70, 30, 255), outline=(255, 180, 50, 255), width=4)

    # Glowing wolf eye
    draw.ellipse([cx + 10, cy - 45, cx + 25, cy - 35], fill=(255, 255, 200, 255))

    # Banner
    lbl_w = int(size * 0.68)
    lbl_h = int(size * 0.12)
    lx = cx - lbl_w // 2
    ly = size - lbl_h - 35
    draw.rounded_rectangle([lx, ly, lx + lbl_w, ly + lbl_h], radius=8, fill=(35, 5, 5, 245), outline=(220, 40, 20, 255), width=3)
    draw.text((cx, ly + lbl_h // 2), "HOWLING DAWN", fill=(255, 200, 180, 255), anchor="mm")

    return img


def generate_cloud9_holo(size: int = 512) -> Image.Image:
    """Generates Cloud9 Holo sticker badge."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    holo = _create_holo_gradient(size)
    img.alpha_composite(holo)
    draw = ImageDraw.Draw(img)

    cx, cy = size // 2, size // 2 - 20
    r = int(size * 0.42)

    # Circular shield
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(8, 20, 35, 240), outline=(0, 174, 239, 255), width=8)

    # Cloud9 Interlocking '9' Circles
    c_blue = (0, 174, 239, 255)
    c_white = (255, 255, 255, 255)

    cr = 45
    # 3 interconnected circles representing Cloud 9
    circle_centers = [
        (cx - 55, cy - 20),
        (cx + 55, cy - 20),
        (cx, cy + 60),
    ]
    for ccx, ccy in circle_centers:
        draw.ellipse([ccx - cr, ccy - cr, ccx + cr, ccy + cr], outline=c_blue, width=22)
        draw.ellipse([ccx - cr - 4, ccy - cr - 4, ccx + cr + 4, ccy + cr + 4], outline=c_white, width=3)

    # Banner
    lbl_w = int(size * 0.62)
    lbl_h = int(size * 0.12)
    lx = cx - lbl_w // 2
    ly = size - lbl_h - 35
    draw.rounded_rectangle([lx, ly, lx + lbl_w, ly + lbl_h], radius=8, fill=(5, 18, 30, 245), outline=(0, 174, 239, 255), width=3)
    draw.text((cx, ly + lbl_h // 2), "CLOUD9 HOLO", fill=(255, 255, 255, 255), anchor="mm")

    return img


def generate_dignitas_holo(size: int = 512) -> Image.Image:
    """Generates Team Dignitas Holo sticker badge."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    holo = _create_holo_gradient(size)
    img.alpha_composite(holo)
    draw = ImageDraw.Draw(img)

    cx, cy = size // 2, size // 2 - 20
    r = int(size * 0.42)

    # Outer shield
    pts = []
    for i in range(6):
        a = math.radians(60 * i + 30)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    draw.polygon(pts, fill=(20, 20, 10, 240), outline=(245, 210, 20, 255), width=8)

    # Dignitas Alien Head Emblem
    head_pts = [
        (cx - 90, cy - 80),
        (cx + 90, cy - 80),
        (cx + 120, cy),
        (cx + 50, cy + 90),
        (cx - 50, cy + 90),
        (cx - 120, cy),
    ]
    draw.polygon(head_pts, fill=(245, 210, 20, 255), outline=(255, 255, 255, 255), width=5)

    # Large Creepy Hollow Glowing Alien Eyes
    draw.ellipse([cx - 75, cy - 40, cx - 15, cy + 30], fill=(20, 20, 10, 255), outline=(180, 240, 40, 255), width=4)
    draw.ellipse([cx + 15, cy - 40, cx + 75, cy + 30], fill=(20, 20, 10, 255), outline=(180, 240, 40, 255), width=4)

    # Green-yellow holo pupils
    draw.ellipse([cx - 50, cy - 15, cx - 35, cy], fill=(180, 240, 40, 255))
    draw.ellipse([cx + 35, cy - 15, cx + 50, cy], fill=(180, 240, 40, 255))

    # Banner
    lbl_w = int(size * 0.64)
    lbl_h = int(size * 0.12)
    lx = cx - lbl_w // 2
    ly = size - lbl_h - 35
    draw.rounded_rectangle([lx, ly, lx + lbl_w, ly + lbl_h], radius=8, fill=(25, 20, 5, 245), outline=(245, 210, 20, 255), width=3)
    draw.text((cx, ly + lbl_h // 2), "TEAM DIGNITAS", fill=(255, 240, 50, 255), anchor="mm")

    return img


def generate_virtus_pro_holo(size: int = 512) -> Image.Image:
    """Generates Virtus.Pro Holo sticker badge."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    holo = _create_holo_gradient(size)
    img.alpha_composite(holo)
    draw = ImageDraw.Draw(img)

    cx, cy = size // 2, size // 2 - 20
    r = int(size * 0.42)

    # Hex shield
    pts = []
    for i in range(6):
        a = math.radians(60 * i)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    draw.polygon(pts, fill=(18, 18, 20, 240), outline=(255, 102, 0, 255), width=8)

    # Roaring Polar Bear Head
    bear_pts = [
        (cx - 100, cy + 80),
        (cx - 110, cy - 10),
        (cx - 60, cy - 90),    # Left ear
        (cx - 20, cy - 50),
        (cx + 30, cy - 80),    # Right ear
        (cx + 80, cy - 40),
        (cx + 120, cy + 20),   # Snout
        (cx + 90, cy + 80),    # Lower jaw
        (cx + 50, cy + 40),
        (cx + 10, cy + 70),
    ]
    draw.polygon(bear_pts, fill=(245, 245, 250, 255), outline=(255, 102, 0, 255), width=5)

    # Open roaring mouth (orange and black)
    draw.polygon([(cx + 60, cy + 10), (cx + 110, cy + 25), (cx + 80, cy + 65)], fill=(255, 102, 0, 255))
    # Sharp teeth
    draw.polygon([(cx + 70, cy + 15), (cx + 85, cy + 30), (cx + 95, cy + 18)], fill=(255, 255, 255, 255))

    # Fierce eye
    draw.polygon([(cx + 10, cy - 25), (cx + 35, cy - 15), (cx + 15, cy - 10)], fill=(255, 102, 0, 255))

    # Banner
    lbl_w = int(size * 0.64)
    lbl_h = int(size * 0.12)
    lx = cx - lbl_w // 2
    ly = size - lbl_h - 35
    draw.rounded_rectangle([lx, ly, lx + lbl_w, ly + lbl_h], radius=8, fill=(25, 15, 5, 245), outline=(255, 102, 0, 255), width=3)
    draw.text((cx, ly + lbl_h // 2), "VIRTUS.PRO", fill=(255, 255, 255, 255), anchor="mm")

    return img


GENERATORS = {
    "titan_holo.png": generate_titan_holo,
    "ibuypower_holo.png": generate_ibuypower_holo,
    "navi_holo.png": generate_navi_holo,
    "crown_foil.png": generate_crown_foil,
    "howling_dawn.png": generate_howling_dawn,
    "cloud9_holo.png": generate_cloud9_holo,
    "dignitas_holo.png": generate_dignitas_holo,
    "virtus_pro_holo.png": generate_virtus_pro_holo,
}


def ensure_builtin_assets(
    workspace_root: Union[str, Path] = ".",
    force_restore: bool = False,
) -> None:
    """Ensures that assets/stickers, assets/my_stickers, assets/my_skins directories and files exist.
    On first run, creates assets/.initialized so user deletions are not resurrected.
    If force_restore is True, all default tournament stickers are regenerated.
    """
    root = Path(workspace_root).resolve()
    assets_dir = root / "assets"
    stickers_dir = assets_dir / "stickers"
    my_stickers_dir = assets_dir / "my_stickers"
    my_skins_dir = assets_dir / "my_skins"
    marker_file = assets_dir / ".initialized"

    stickers_dir.mkdir(parents=True, exist_ok=True)
    my_stickers_dir.mkdir(parents=True, exist_ok=True)
    my_skins_dir.mkdir(parents=True, exist_ok=True)

    # If already initialized and not forced, respect user deletions
    if marker_file.is_file() and not force_restore:
        return

    for filename, gen_fn in GENERATORS.items():
        dest = stickers_dir / filename
        if force_restore or not dest.exists():
            img = gen_fn(512)
            img.save(dest, format="PNG")

    try:
        marker_file.write_text("cs16_studio_library_initialized=true\n", encoding="utf-8")
    except Exception:
        pass


def _load_user_stickers_meta(folder: Path) -> dict:
    meta_file = folder / ".meta.json"
    if meta_file.is_file():
        try:
            with open(meta_file, "r", encoding="utf-8") as fp:
                return json.load(fp)
        except Exception:
            return {}
    return {}


def _save_user_stickers_meta(folder: Path, meta: dict) -> None:
    meta_file = folder / ".meta.json"
    try:
        with open(meta_file, "w", encoding="utf-8") as fp:
            json.dump(meta, fp, indent=2)
    except Exception:
        pass


def get_library_stickers(workspace_root: Union[str, Path] = ".") -> List[dict]:
    """Scans and returns all available stickers from built-in and user folders."""
    root = Path(workspace_root).resolve()
    ensure_builtin_assets(root)

    stickers = []
    seen_keys = set()

    # Search folders in priority order
    scan_folders = [
        (root / "assets" / "stickers", "Tournament Holo"),
        (root / "assets" / "my_stickers", "Custom / User"),
    ]

    for folder, default_cat in scan_folders:
        if not folder.is_dir():
            continue
        user_meta = _load_user_stickers_meta(folder)
        for f in sorted(folder.glob("*.*")):
            if f.suffix.lower() in (".png", ".webp", ".bmp", ".jpg", ".jpeg"):
                stem = f.stem
                key = (folder.name, stem)
                if key in seen_keys:
                    continue
                seen_keys.add(key)

                # Determine category & display name
                display_name = stem.replace("_", " ").title()
                cat = default_cat
                for meta in STICKER_DEFINITIONS:
                    if meta["filename"].lower() == f.name.lower():
                        display_name = meta["name"]
                        cat = meta["category"]
                        break

                is_custom = (folder.name == "my_stickers")
                if f.name in user_meta:
                    m = user_meta[f.name]
                    if isinstance(m, dict):
                        display_name = m.get("name", display_name)
                        cat = m.get("category", cat)

                # Generate fast base64 thumbnail (128x128)
                try:
                    with Image.open(f) as img:
                        thumb = img.convert("RGBA").resize((128, 128), Image.Resampling.BILINEAR)
                        buf = io.BytesIO()
                        thumb.save(buf, format="PNG")
                        thumb_b64 = base64.b64encode(buf.getvalue()).decode("ascii")
                        thumb_uri = f"data:image/png;base64,{thumb_b64}"
                except Exception:
                    thumb_uri = ""

                try:
                    rel_path = f.relative_to(root).as_posix()
                except ValueError:
                    rel_path = str(f)

                stickers.append({
                    "name": display_name,
                    "filename": f.name,
                    "category": cat,
                    "path": rel_path,
                    "thumbnail": thumb_uri,
                    "preview": thumb_uri,
                    "is_custom": is_custom,
                })

    return stickers


def get_library_skins(workspace_root: Union[str, Path] = ".") -> List[dict]:
    """Scans and returns all available weapon skins in assets/my_skins and assets/skins."""
    root = Path(workspace_root).resolve()
    skins = []
    seen = set()

    scan_folders = [
        root / "assets" / "my_skins",
        root / "assets" / "skins",
    ]

    for folder in scan_folders:
        if not folder.is_dir():
            continue
        for f in sorted(folder.glob("*.*")):
            if f.suffix.lower() in (".png", ".webp", ".bmp", ".jpg", ".jpeg"):
                if f.name in seen:
                    continue
                seen.add(f.name)
                display_name = f.stem.replace("_", " ").title()

                try:
                    with Image.open(f) as img:
                        w, h = img.size
                        thumb = img.convert("RGBA").resize((128, 128), Image.Resampling.BILINEAR)
                        buf = io.BytesIO()
                        thumb.save(buf, format="PNG")
                        thumb_b64 = base64.b64encode(buf.getvalue()).decode("ascii")
                        thumb_uri = f"data:image/png;base64,{thumb_b64}"
                except Exception:
                    w, h = 0, 0
                    thumb_uri = ""

                try:
                    rel_path = f.relative_to(root).as_posix()
                except ValueError:
                    rel_path = str(f)

                skins.append({
                    "name": display_name,
                    "filename": f.name,
                    "width": w,
                    "height": h,
                    "category": "Custom Weapon Skins",
                    "path": rel_path,
                    "thumbnail": thumb_uri,
                    "preview": thumb_uri,
                    "is_custom": (folder.name == "my_skins"),
                })

    return skins

def save_custom_sticker(
    name: str,
    image_bytes: bytes,
    category: str = "Custom / User",
    auto_alpha: bool = False,
    workspace_root: Union[str, Path] = ".",
) -> dict:
    """Saves a custom sticker image to assets/my_stickers/ with optional auto-alpha background removal."""
    root = Path(workspace_root).resolve()
    my_stickers = root / "assets" / "my_stickers"
    my_stickers.mkdir(parents=True, exist_ok=True)

    clean_name = name.strip()
    if not clean_name:
        clean_name = "custom_sticker"

    safe_base = re.sub(r"[^a-zA-Z0-9_\-]", "_", clean_name.lower())
    safe_base = re.sub(r"_+", "_", safe_base).strip("_")
    if not safe_base:
        safe_base = "custom_sticker"

    filename = f"{safe_base}.png"
    target_path = my_stickers / filename

    # Avoid accidental collision with custom or built-in stickers by indexing if needed
    builtin_stickers = root / "assets" / "stickers"
    counter = 1
    while target_path.exists() or (builtin_stickers / filename).exists():
        filename = f"{safe_base}_{counter}.png"
        target_path = my_stickers / filename
        counter += 1

    img = Image.open(io.BytesIO(image_bytes)).convert("RGBA")

    if auto_alpha:
        arr = np.array(img)
        r, g, b, a = arr[:, :, 0], arr[:, :, 1], arr[:, :, 2], arr[:, :, 3]
        corner_coords = [(0, 0), (0, -1), (-1, 0), (-1, -1)]
        corner_alphas = [arr[cy, cx, 3] for cy, cx in corner_coords]
        # Only perform auto-alpha if corners are substantially opaque (not already transparent)
        if np.mean(corner_alphas) > 128:
            corners_rgb = [arr[cy, cx, :3] for cy, cx in corner_coords]
            avg_corner = np.mean(corners_rgb, axis=0)
            if np.mean(avg_corner) < 50:
                # Black / dark background
                mask = (r < 35) & (g < 35) & (b < 35)
                arr[:, :, 3] = np.where(mask, 0, a)
            elif np.mean(avg_corner) > 215:
                # White / bright background
                mask = (r > 220) & (g > 220) & (b > 220)
                arr[:, :, 3] = np.where(mask, 0, a)
            img = Image.fromarray(arr, mode="RGBA")

    img.save(target_path, format="PNG")

    # Generate smart tags
    smart_tags = [category.lower()] if category else ["custom", "sticker"]
    if "foil" in clean_name.lower():
        smart_tags.append("foil")
    if "holo" in clean_name.lower():
        smart_tags.append("holo")
    smart_tags = list(dict.fromkeys(smart_tags))

    # Update metadata
    meta = _load_user_stickers_meta(my_stickers)
    meta[target_path.name] = {
        "name": clean_name,
        "category": category or "Custom / User",
        "tags": smart_tags,
    }
    _save_user_stickers_meta(my_stickers, meta)

    # Generate thumbnail
    thumb = img.resize((128, 128), Image.Resampling.BILINEAR)
    buf = io.BytesIO()
    thumb.save(buf, format="PNG")
    thumb_b64 = base64.b64encode(buf.getvalue()).decode("ascii")
    thumb_uri = f"data:image/png;base64,{thumb_b64}"

    try:
        rel_path = target_path.relative_to(root).as_posix()
    except ValueError:
        rel_path = str(target_path)

    return {
        "success": True,
        "name": clean_name,
        "filename": target_path.name,
        "category": category or "Custom / User",
        "tags": smart_tags,
        "path": rel_path,
        "thumbnail": thumb_uri,
        "preview": thumb_uri,
        "is_custom": True,
    }


def edit_custom_sticker(
    filename: str,
    new_name: Optional[str] = None,
    new_category: Optional[str] = None,
    workspace_root: Union[str, Path] = ".",
) -> dict:
    """Updates metadata and display name for a sticker in assets/my_stickers/ or assets/stickers/."""
    root = Path(workspace_root).resolve()
    my_stickers = root / "assets" / "my_stickers"
    builtin_stickers = root / "assets" / "stickers"
    clean_fn = Path(filename).name

    target_folder = None
    if (my_stickers / clean_fn).is_file():
        target_folder = my_stickers
    elif (builtin_stickers / clean_fn).is_file():
        target_folder = builtin_stickers
    else:
        raise FileNotFoundError(f"Sticker '{clean_fn}' not found in library.")

    meta = _load_user_stickers_meta(target_folder)
    default_cat = "Custom / User" if target_folder == my_stickers else "Tournament Holo"
    for item in STICKER_DEFINITIONS:
        if item["filename"].lower() == clean_fn.lower():
            default_cat = item["category"]
            break

    current = meta.get(clean_fn, {
        "name": (target_folder / clean_fn).stem.replace("_", " ").title(),
        "category": default_cat,
    })

    if new_name is not None and new_name.strip():
        current["name"] = new_name.strip()
    if new_category is not None and new_category.strip():
        current["category"] = new_category.strip()

    meta[clean_fn] = current
    _save_user_stickers_meta(target_folder, meta)

    return {
        "success": True,
        "filename": clean_fn,
        "name": current["name"],
        "category": current["category"],
    }


def delete_custom_sticker(
    filename: str,
    workspace_root: Union[str, Path] = ".",
    allow_builtin: bool = False,
) -> dict:
    """Deletes a custom sticker or built-in sticker (if allow_builtin=True)."""
    root = Path(workspace_root).resolve()
    clean_fn = Path(filename).name

    my_stickers = root / "assets" / "my_stickers"
    builtin_stickers = root / "assets" / "stickers"

    is_custom = (my_stickers / clean_fn).is_file()
    is_builtin = (builtin_stickers / clean_fn).is_file()

    if not is_custom and not is_builtin:
        raise FileNotFoundError(f"Sticker '{clean_fn}' not found.")

    if is_builtin and not is_custom and not allow_builtin:
        raise ValueError("Cannot delete built-in library stickers. Only custom stickers can be deleted.")

    if is_custom:
        target_path = my_stickers / clean_fn
        target_path.unlink()
        meta = _load_user_stickers_meta(my_stickers)
        if clean_fn in meta:
            del meta[clean_fn]
            _save_user_stickers_meta(my_stickers, meta)
    elif is_builtin and allow_builtin:
        target_path = builtin_stickers / clean_fn
        target_path.unlink()
        meta = _load_user_stickers_meta(builtin_stickers)
        if clean_fn in meta:
            del meta[clean_fn]
            _save_user_stickers_meta(builtin_stickers, meta)

    return {
        "success": True,
        "message": f"Sticker '{clean_fn}' deleted successfully.",
        "filename": clean_fn,
    }


def restore_default_stickers(workspace_root: Union[str, Path] = ".") -> dict:
    """Restores all default tournament & foil stickers into assets/stickers/."""
    ensure_builtin_assets(workspace_root, force_restore=True)
    return {
        "success": True,
        "message": f"Successfully restored {len(GENERATORS)} default tournament stickers.",
        "count": len(GENERATORS),
    }
