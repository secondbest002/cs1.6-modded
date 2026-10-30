"""
stattrak_customizer.py - StatTrak LED Digital Counter Customizer.
Allows customizing LED digit color (Orange, Neon Cyan, Ruby Red, Emerald Green, Violet)
and digit display values for Counter-Strike 1.6 StatTrak modules.
"""

from typing import Dict, Optional, Tuple, Union
import numpy as np
from PIL import Image, ImageDraw

from .image_pipeline import load_image, quantize_goldsrc

LED_COLORS: Dict[str, Tuple[int, int, int]] = {
    "orange": (255, 120, 10),     # Classic CS:GO Amber
    "cyan": (0, 235, 255),        # Neon Cyan
    "red": (255, 35, 45),         # Ruby Red
    "green": (25, 255, 110),      # Emerald Green
    "violet": (195, 60, 255),     # Cyber Violet
}

# 7-Segment digit patterns: a, b, c, d, e, f, g
#   -- a --
#  |       |
#  f       b
#  |       |
#   -- g --
#  |       |
#  e       c
#  |       |
#   -- d --
SEGMENTS = {
    "0": (1, 1, 1, 1, 1, 1, 0),
    "1": (0, 1, 1, 0, 0, 0, 0),
    "2": (1, 1, 0, 1, 1, 0, 1),
    "3": (1, 1, 1, 1, 0, 0, 1),
    "4": (0, 1, 1, 0, 0, 1, 1),
    "5": (1, 0, 1, 1, 0, 1, 1),
    "6": (1, 0, 1, 1, 1, 1, 1),
    "7": (1, 1, 1, 0, 0, 0, 0),
    "8": (1, 1, 1, 1, 1, 1, 1),
    "9": (1, 1, 1, 1, 0, 1, 1),
    " ": (0, 0, 0, 0, 0, 0, 0),
}


def recolor_digit_texture(
    source_image: Union[str, bytes, Image.Image],
    color_name: str = "orange",
) -> Image.Image:
    """
    Recolors an existing StatTrak digit texture (e.g. stat_digit.bmp) to a new LED glow color.
    Uses luminance-based color remapping with bright hot cores and soft glow falloff.
    """
    img = load_image(source_image).convert("RGBA")
    arr = np.array(img, dtype=np.float32)

    target_rgb = np.array(LED_COLORS.get(color_name.lower(), LED_COLORS["orange"]), dtype=np.float32)

    # Calculate luminance of original pixels
    r, g, b = arr[:, :, 0], arr[:, :, 1], arr[:, :, 2]
    lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0

    # Remap active LED pixels (lum > 0.05)
    active_mask = lum > 0.05

    out_arr = arr.copy()

    # Low-lum background: dark tinted LED glass
    out_arr[~active_mask, 0] = np.clip(target_rgb[0] * 0.05, 0, 20)
    out_arr[~active_mask, 1] = np.clip(target_rgb[1] * 0.05, 0, 20)
    out_arr[~active_mask, 2] = np.clip(target_rgb[2] * 0.05, 0, 20)

    # High lum: blend towards pure white hot core
    high_lum = np.clip((lum - 0.5) / 0.5, 0.0, 1.0)
    core_rgb = target_rgb * (1.0 - high_lum[:, :, None]) + np.array([255.0, 255.0, 255.0]) * high_lum[:, :, None]

    # Mid/low glow
    glow_factor = np.clip(lum / 0.5, 0.0, 1.0)[:, :, None]
    final_rgb = core_rgb * glow_factor

    out_arr[active_mask, :3] = np.clip(final_rgb[active_mask], 0, 255)
    out_arr[:, :, 3] = 255.0

    return Image.fromarray(out_arr.astype(np.uint8), mode="RGBA")


def render_7segment_display(
    width: int = 32,
    height: int = 47,
    number_str: str = "1337",
    color_name: str = "orange",
) -> Image.Image:
    """
    Renders custom 7-segment digital LED numbers onto the exact texture dimensions.
    """
    img = Image.new("RGBA", (width, height), (12, 14, 18, 255))
    draw = ImageDraw.Draw(img)

    target_color = LED_COLORS.get(color_name.lower(), LED_COLORS["orange"])
    dim_color = tuple(int(c * 0.15) for c in target_color)

    # Display up to 6 digits, padded with leading zeros or spaces
    clean_str = str(number_str).strip().rjust(6, "0")[-6:]
    num_digits = len(clean_str)

    margin_x = 2
    margin_y = 4
    avail_w = width - margin_x * 2
    avail_h = height - margin_y * 2

    digit_w = max(3, (avail_w - (num_digits - 1)) // num_digits)
    digit_h = max(6, avail_h)

    for i, ch in enumerate(clean_str):
        dx = margin_x + i * (digit_w + 1)
        dy = margin_y
        segs = SEGMENTS.get(ch, SEGMENTS[" "])

        # seg a (top horizontal)
        c_a = target_color if segs[0] else dim_color
        draw.line([(dx + 1, dy), (dx + digit_w - 2, dy)], fill=c_a)

        # seg b (top right vertical)
        c_b = target_color if segs[1] else dim_color
        draw.line([(dx + digit_w - 1, dy + 1), (dx + digit_w - 1, dy + digit_h // 2 - 1)], fill=c_b)

        # seg c (bottom right vertical)
        c_c = target_color if segs[2] else dim_color
        draw.line([(dx + digit_w - 1, dy + digit_h // 2 + 1), (dx + digit_w - 1, dy + digit_h - 2)], fill=c_c)

        # seg d (bottom horizontal)
        c_d = target_color if segs[3] else dim_color
        draw.line([(dx + 1, dy + digit_h - 1), (dx + digit_w - 2, dy + digit_h - 1)], fill=c_d)

        # seg e (bottom left vertical)
        c_e = target_color if segs[4] else dim_color
        draw.line([(dx, dy + digit_h // 2 + 1), (dx, dy + digit_h - 2)], fill=c_e)

        # seg f (top left vertical)
        c_f = target_color if segs[5] else dim_color
        draw.line([(dx, dy + 1), (dx, dy + digit_h // 2 - 1)], fill=c_f)

        # seg g (middle horizontal)
        c_g = target_color if segs[6] else dim_color
        draw.line([(dx + 1, dy + digit_h // 2), (dx + digit_w - 2, dy + digit_h // 2)], fill=c_g)

    return img


def customize_stattrak_texture(
    source_image: Union[str, bytes, Image.Image],
    color_name: str = "orange",
    custom_number: Optional[Union[str, int]] = None,
) -> Tuple[bytes, Image.Image]:
    """
    Produces GoldSrc quantized payload for StatTrak digit texture.
    If custom_number is given, renders new LED digits; otherwise recolors existing digits.
    Returns:
        (goldsrc_payload_bytes, preview_image)
    """
    img = load_image(source_image)
    w, h = img.width, img.height

    if custom_number is not None and str(custom_number).strip():
        rendered = render_7segment_display(w, h, number_str=str(custom_number), color_name=color_name)
    else:
        rendered = recolor_digit_texture(img, color_name=color_name)

    pix_bytes, pal_bytes = quantize_goldsrc(rendered, is_masked=False)
    payload = pix_bytes + pal_bytes
    return payload, rendered

