"""
tests/test_advancements.py - Comprehensive Unit & Integration Tests for
CS 1.6 Asset Studio Pro Advancements:
1. Photographic Color Grading Engine (color_adjuster.py)
2. Slot Sticker Transform & Scale Tuner (image_pipeline.py)
3. 3D WebGL StudioModel Geometry Extractor (mdl_core.py)
4. Chrome Shimmer & Environment Mapping (mdl_core.py)
5. StatTrak LED Customizer (stattrak_customizer.py)
6. Float & Wear Simulator (wear_simulator.py)
7. 1-Click Glove & Sleeve Transfer Studio (glove_transfer.py)
8. REST API Endpoints in server.py
"""

import base64
import io
import json
from pathlib import Path
import shutil
import socket
import struct
import tempfile
import threading
import time
import unittest
import urllib.request
import numpy as np
from PIL import Image

from scripts.cs16_studio.baker import (
    bake_sticker_onto_texture,
)
from scripts.cs16_studio.color_adjuster import (
    PRESETS,
    adjust_and_quantize,
    adjust_color_grading,
)
from scripts.cs16_studio.glove_transfer import (
    classify_glove_role,
    transfer_gloves,
)
from scripts.cs16_studio.image_pipeline import (
    GOLDSRC_MASK_COLOR,
    process_slot_sticker_with_transform,
)
from scripts.cs16_studio.mdl_core import (
    STUDIO_NF_CHROME,
    MdlModel,
    extract_model_3d,
    resolve_model_path,
)
from scripts.cs16_studio.stattrak_customizer import (
    LED_COLORS,
    customize_stattrak_texture,
    recolor_digit_texture,
    render_7segment_display,
)
from scripts.cs16_studio.wear_simulator import (
    apply_wear_simulation,
    get_wear_condition_name,
    simulate_and_quantize,
)
from scripts.cs16_studio.web.server import create_server


def get_free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("", 0))
        return s.getsockname()[1]


class TestColorAdjuster(unittest.TestCase):
    """Verifies color grading mathematical bounds and GoldSrc quantization."""

    def setUp(self):
        self.test_img = Image.new("RGBA", (128, 128), (140, 90, 210, 255))

    def test_extreme_slider_bounds(self):
        # Extreme negative sliders
        neg_img = adjust_color_grading(
            self.test_img,
            brightness=-100,
            contrast=-100,
            saturation=-100,
            vibrance=-100,
            clarity=-100,
            shadows=-100,
            highlights=-100,
            temperature=-100,
            tint=-100,
        )
        neg_arr = np.array(neg_img)
        self.assertTrue(np.all(neg_arr >= 0))
        self.assertTrue(np.all(neg_arr <= 255))

        # Extreme positive sliders
        pos_img = adjust_color_grading(
            self.test_img,
            brightness=100,
            contrast=100,
            saturation=100,
            vibrance=100,
            clarity=100,
            shadows=100,
            highlights=100,
            temperature=100,
            tint=100,
        )
        pos_arr = np.array(pos_img)
        self.assertTrue(np.all(pos_arr >= 0))
        self.assertTrue(np.all(pos_arr <= 255))

    def test_all_presets_and_quantization(self):
        for preset_name, params in PRESETS.items():
            payload, q_img = adjust_and_quantize(
                self.test_img, is_masked=False, **params
            )
            expected_len = 128 * 128 + 768
            self.assertEqual(
                len(payload),
                expected_len,
                f"Preset {preset_name} payload length mismatch",
            )
            self.assertEqual(q_img.size, (128, 128))

    def test_sigmoid_contrast_monotonicity_and_knee_rolloff(self):
        """Verifies Sigmoid S-Curve contrast does not posterize or invert tones."""
        # Create a smooth gradient from 0 to 255
        gradient = np.tile(np.linspace(0, 255, 256, dtype=np.uint8), (10, 1))
        grad_img = Image.fromarray(np.stack([gradient, gradient, gradient], axis=-1), mode="RGB")

        # Test at maximum +100 contrast
        graded = adjust_color_grading(grad_img, contrast=100)
        arr = np.array(graded)[:, :, 0]
        row = arr[5, :]

        # 1. Monotonicity: every tone is >= preceding tone
        diffs = np.diff(row.astype(np.int32))
        self.assertTrue(np.all(diffs >= 0), "Sigmoid contrast curve must be monotonically non-decreasing")

        # 2. Bound preservation and soft knee roll-off
        self.assertEqual(row[0], 0, "Black (0) must remain 0")
        self.assertEqual(row[255], 255, "White (255) must remain 255")
        # Midtone (around index 127/128) must stay centered around 128
        self.assertAlmostEqual(int(row[127]), 127, delta=3)

        # 3. Soft knee roll-off: values near 0 and 255 are NOT crushed into 1-bit posterization
        # There must be at least 100 distinct tonal levels preserved even at +100 contrast
        unique_levels = len(np.unique(row))
        self.assertGreater(unique_levels, 100, "Sigmoid contrast must preserve smooth dynamic range without 1-bit posterization")

    def test_luminance_preserving_temperature_and_tint(self):
        """Verifies Kelvin Planckian white balance and Tint strictly preserve perceived luminance."""
        test_patch = Image.new("RGBA", (64, 64), (180, 140, 100, 255))
        orig_arr = np.array(test_patch, dtype=np.float32) / 255.0
        orig_lum = 0.299 * orig_arr[:, :, 0] + 0.587 * orig_arr[:, :, 1] + 0.114 * orig_arr[:, :, 2]
        mean_orig_lum = float(np.mean(orig_lum))

        # Warm temperature test (+100)
        warm_img = adjust_color_grading(test_patch, temperature=100)
        warm_arr = np.array(warm_img, dtype=np.float32) / 255.0
        warm_lum = float(np.mean(0.299 * warm_arr[:, :, 0] + 0.587 * warm_arr[:, :, 1] + 0.114 * warm_arr[:, :, 2]))
        self.assertAlmostEqual(warm_lum, mean_orig_lum, delta=0.015, msg="Warm temperature must preserve luminance")

        # Cool temperature test (-100)
        cool_img = adjust_color_grading(test_patch, temperature=-100)
        cool_arr = np.array(cool_img, dtype=np.float32) / 255.0
        cool_lum = float(np.mean(0.299 * cool_arr[:, :, 0] + 0.587 * cool_arr[:, :, 1] + 0.114 * cool_arr[:, :, 2]))
        self.assertAlmostEqual(cool_lum, mean_orig_lum, delta=0.015, msg="Cool temperature must preserve luminance")

        # Tint tests (+100 Magenta, -100 Green)
        mag_img = adjust_color_grading(test_patch, tint=100)
        mag_arr = np.array(mag_img, dtype=np.float32) / 255.0
        mag_lum = float(np.mean(0.299 * mag_arr[:, :, 0] + 0.587 * mag_arr[:, :, 1] + 0.114 * mag_arr[:, :, 2]))
        self.assertAlmostEqual(mag_lum, mean_orig_lum, delta=0.015, msg="Magenta tint must preserve luminance")

    def test_shadows_and_highlights_gaussian_rolloff(self):
        """Verifies Shadows boost affects dark tones and Highlights recovery affects bright tones independently."""
        # Split image: left half is dark (15% lum), right half is highlight (90% lum)
        img_arr = np.zeros((32, 64, 3), dtype=np.uint8)
        img_arr[:, :32, :] = 35   # shadows
        img_arr[:, 32:, :] = 230  # highlights
        patch = Image.fromarray(img_arr, mode="RGB")

        # Shadow boost only
        sh_img = adjust_color_grading(patch, shadows=80)
        sh_arr = np.array(sh_img)
        # Left half (shadows) should be brightened
        self.assertGreater(int(np.mean(sh_arr[:, :32, 0])), 35)
        # Right half (highlights) should be virtually unchanged
        self.assertAlmostEqual(float(np.mean(sh_arr[:, 32:, 0])), 230.0, delta=4.0)

        # Highlight recovery only
        hi_img = adjust_color_grading(patch, highlights=-80)
        hi_arr = np.array(hi_img)
        # Right half (highlights) should be pulled down
        self.assertLess(int(np.mean(hi_arr[:, 32:, 0])), 230)
        # Left half (shadows) should be virtually unchanged
        self.assertAlmostEqual(float(np.mean(hi_arr[:, :32, 0])), 35.0, delta=4.0)

    def test_selective_hsl_color_mixer_isolation(self):
        """
        Verifies 8-Channel Selective HSL Color Mixer changes target color (Yellow)
        while strictly isolating and preserving dark gun metal and grayscale gloves.
        """
        img_arr = np.zeros((32, 64, 3), dtype=np.uint8)
        # Left half: Vibrant Yellow stripe (R=250, G=220, B=10)
        img_arr[:, :32] = [250, 220, 10]
        # Right half: Gun metal dark gray (R=40, G=40, B=42)
        img_arr[:, 32:] = [40, 40, 42]
        source = Image.fromarray(img_arr, mode="RGB")

        # Turn Yellow into Purple/Magenta via +120 degree Hue shift on yellow channel
        graded = adjust_color_grading(
            source,
            hsl_adjustments={
                "yellow": {"hue": 120.0, "saturation": 0.0, "lightness": 0.0}
            }
        )
        res_arr = np.array(graded)

        # 1. Yellow region must undergo significant color shift (Red & Blue increase, Green lowers)
        yellow_res = res_arr[10, 10]
        self.assertNotEqual(int(yellow_res[1]), 220, "Yellow channel hue rotation should modify green component")

        # 2. Gun metal region must remain completely untouched (achromatic saturation gating)
        metal_res = res_arr[10, 45]
        self.assertAlmostEqual(int(metal_res[0]), 40, delta=2, msg="Metal R must not change")
        self.assertAlmostEqual(int(metal_res[1]), 40, delta=2, msg="Metal G must not change")
        self.assertAlmostEqual(int(metal_res[2]), 42, delta=2, msg="Metal B must not change")

    def test_halo_free_clarity_and_sharpen(self):
        """Verifies Clarity and Sharpening enhance details within valid [0, 255] bounds."""
        base = Image.new("RGBA", (64, 64), (100, 100, 100, 255))
        # Add high-contrast white box in the center
        box = Image.new("RGBA", (16, 16), (250, 250, 250, 255))
        base.paste(box, (24, 24))

        graded = adjust_color_grading(base, clarity=80, sharpen=80)
        arr = np.array(graded)
        self.assertTrue(np.all(arr >= 0))
        self.assertTrue(np.all(arr <= 255))
        self.assertFalse(np.any(np.isnan(arr)))
    def test_selective_hsl_multi_channel_decoupled_normalization(self):
        """
        Verifies that adjusting Saturation on one channel (Orange) does NOT dilute
        or attenuate the Hue shift on another channel (Red).
        """
        # Create a pure Red patch (Hue 0)
        red_patch = Image.new("RGB", (16, 16), (255, 0, 0))

        # 1. Shift Red hue by +30 alone
        graded_alone = adjust_color_grading(
            red_patch,
            hsl_adjustments={
                "red": {"hue": 30.0, "saturation": 0.0, "lightness": 0.0}
            }
        )
        alone_rgb = np.array(graded_alone)[0, 0]

        # 2. Shift Red hue by +30 WITH Orange saturation +50
        graded_combined = adjust_color_grading(
            red_patch,
            hsl_adjustments={
                "red": {"hue": 30.0, "saturation": 0.0, "lightness": 0.0},
                "orange": {"hue": 0.0, "saturation": 50.0, "lightness": 0.0},
            }
        )
        combined_rgb = np.array(graded_combined)[0, 0]

        # Red channel's hue shift must remain identical and not be diluted by Orange saturation
        self.assertAlmostEqual(int(alone_rgb[0]), int(combined_rgb[0]), delta=2)
        self.assertAlmostEqual(int(alone_rgb[1]), int(combined_rgb[1]), delta=2)
        self.assertAlmostEqual(int(alone_rgb[2]), int(combined_rgb[2]), delta=2)

    def test_selective_hsl_boundary_and_extreme_wraparound(self):
        """Verifies Red hue shift with negative angles wraps correctly around 360 degrees."""
        red_patch = Image.new("RGB", (16, 16), (255, 0, 0))
        graded = adjust_color_grading(
            red_patch,
            hsl_adjustments={
                "red": {"hue": -40.0, "saturation": 0.0, "lightness": 0.0}
            }
        )
        arr = np.array(graded)
        self.assertTrue(np.all(arr >= 0))
        self.assertTrue(np.all(arr <= 255))
        # Shifting Red by -40 degrees moves into Magenta (Red + Blue)
        pixel = arr[0, 0]
        self.assertGreater(int(pixel[2]), 50, "Red shifted by -40 degrees should produce magenta with high blue")

    def test_masked_texture_color_grading_with_pinning(self):
        """Verifies masked texture preserves Index 255 Pinning after color grading and quantization."""
        masked_img = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
        # Draw solid colored circle in the center
        from PIL import ImageDraw
        draw = ImageDraw.Draw(masked_img)
        draw.ellipse([8, 8, 24, 24], fill=(220, 180, 20, 255))

        payload, q_img = adjust_and_quantize(
            masked_img,
            is_masked=True,
            vibrance=30,
            hsl_adjustments={"yellow": {"hue": 40.0}}
        )
        self.assertEqual(len(payload), 32 * 32 + 768)
        pix = payload[:32 * 32]
        pal = payload[32 * 32:]
        # Transparent border must be pinned to index 255
        self.assertEqual(pix[0], 255)
        # Palette index 255 must be pure blue (0, 0, 255)
        self.assertEqual(pal[255 * 3], 0)
        self.assertEqual(pal[255 * 3 + 1], 0)
        self.assertEqual(pal[255 * 3 + 2], 255)


class TestSlotStickerTransform(unittest.TestCase):
    """Verifies slot sticker scaling, rotation, offset, and Index 255 Pinning."""

    def test_slot_transform_dimensions_and_pinning(self):
        target_w, target_h = 176, 161
        sticker = Image.new("RGBA", (200, 200), (255, 50, 50, 255))

        for scale in [0.5, 1.0, 1.5]:
            payload, preview = process_slot_sticker_with_transform(
                sticker,
                target_w=target_w,
                target_h=target_h,
                scale=scale,
                offset_x=15,
                offset_y=-10,
                rotation=45.0,
            )

            expected_size = target_w * target_h + 768
            self.assertEqual(len(payload), expected_size)
            self.assertEqual(preview.size, (target_w, target_h))

            # Verify Index 255 Pinning in palette
            palette_bytes = payload[target_w * target_h :]
            slot_255_rgb = (
                palette_bytes[255 * 3],
                palette_bytes[255 * 3 + 1],
                palette_bytes[255 * 3 + 2],
            )
            self.assertEqual(slot_255_rgb, GOLDSRC_MASK_COLOR)

    def test_slot_stretch_mode(self):
        target_w, target_h = 200, 100
        # Rectangular non-square image
        sticker = Image.new("RGBA", (100, 300), (0, 200, 255, 255))
        payload, preview = process_slot_sticker_with_transform(
            sticker,
            target_w=target_w,
            target_h=target_h,
            scale=1.0,
            fit_mode="stretch",
        )
        self.assertEqual(len(payload), target_w * target_h + 768)
        self.assertEqual(preview.size, (target_w, target_h))


class TestModel3dExtractor(unittest.TestCase):
    """Verifies 3D geometry extraction for WebGL rendering."""

    def test_usp_3d_extraction(self):
        usp_path = resolve_model_path("usp", team="ct")
        data = extract_model_3d(usp_path)

        self.assertTrue(data["success"])
        self.assertGreater(data["mesh_count"], 0)
        self.assertIn("bounds", data)
        self.assertGreater(data["bounds"]["radius"], 0)

        # Verify weapon-specific bounds
        self.assertIn("weapon_bounds", data)
        wb = data["weapon_bounds"]
        self.assertIn("center", wb)
        self.assertIn("radius", wb)
        self.assertIn("size", wb)
        self.assertIn("min", wb)
        self.assertIn("max", wb)
        self.assertGreater(wb["radius"], 0)
        # Weapon bounding radius is tighter than overall model with outstretched arms
        self.assertLessEqual(wb["radius"], data["bounds"]["radius"])

        # Check that meshes contain vertex positions, UVs, and role classification
        roles = set()
        for m in data["meshes"]:
            self.assertIn("positions", m)
            self.assertIn("uvs", m)
            self.assertIn("role", m)
            roles.add(m["role"])
            self.assertEqual(len(m["positions"]) % 3, 0)
            self.assertEqual(len(m["uvs"]) % 2, 0)
            self.assertEqual(len(m["positions"]) // 3, len(m["uvs"]) // 2)

        self.assertIn("glove", roles)
        self.assertIn("skin", roles)

    def test_awp_3d_extraction(self):
        awp_path = resolve_model_path("awp", team="ct")
        data = extract_model_3d(awp_path)

        self.assertTrue(data["success"])
        self.assertGreater(data["mesh_count"], 0)
        self.assertIn("weapon_bounds", data)
        self.assertGreater(data["weapon_bounds"]["radius"], 0)

    def test_corrupted_sequence_fallback_to_bind_pose(self):
        # Create a copy of USP with invalid sequence index to verify graceful fallback
        usp_path = resolve_model_path("usp", team="ct")
        with open(usp_path, "rb") as f:
            raw = bytearray(f.read())

        # Corrupt numseq/seqindex header fields to out-of-bounds offset
        struct.pack_into("<II", raw, 164, 999, 99999999)

        temp_dir = tempfile.mkdtemp()
        try:
            corrupt_path = Path(temp_dir) / "v_corrupt.mdl"
            with open(corrupt_path, "wb") as f:
                f.write(raw)

            # Should not raise exception and should fallback gracefully
            data = extract_model_3d(corrupt_path)
            self.assertTrue(data["success"])
            self.assertGreater(data["mesh_count"], 0)
            self.assertIn("weapon_bounds", data)
        finally:
            shutil.rmtree(temp_dir, ignore_errors=True)

    def test_goldsrc_angle_matrix_mathematical_precision(self):
        # Verify roll, pitch, yaw rotation orientation
        usp_path = resolve_model_path("usp", team="ct")
        data = extract_model_3d(usp_path)
        self.assertTrue(data["success"])
        # In CS 1.6 holding pose, weapon points forward in front of player along negative Z in Three.js
        self.assertLess(data["weapon_bounds"]["center"][2], 0)
        self.assertLess(data["weapon_bounds"]["center"][1], 0)

    def test_multi_model_stride_and_player_model_extraction(self):
        import warnings
        leet_path = Path("cstrike/models/player/leet/leet.mdl")
        if leet_path.exists():
            with warnings.catch_warnings(record=True) as w:
                warnings.simplefilter("always")
                data = extract_model_3d(leet_path)
                self.assertTrue(data["success"])
                self.assertGreater(data["mesh_count"], 0)
                # Confirm no RuntimeWarning (e.g. overflow) occurred
                runtime_warnings = [item for item in w if issubclass(item.category, RuntimeWarning)]
                self.assertEqual(len(runtime_warnings), 0)

    def test_weapon_handle_classification_not_glove(self):
        from scripts.cs16_studio.mdl_core import classify_texture, ROLE_GLOVE
        # Textures with 'handle' should NOT be misclassified as gloves
        role, _ = classify_texture("handle.bmp", 0, 128, 128)
        self.assertNotEqual(role, ROLE_GLOVE)
        role2, _ = classify_texture("Pythonhandle.bmp", 0, 128, 128)
        self.assertNotEqual(role2, ROLE_GLOVE)
        # Actual gloves should still be classified as glove
        role3, _ = classify_texture("sport_right.bmp", 0, 128, 128)
        self.assertEqual(role3, ROLE_GLOVE)
        role4, _ = classify_texture("sleeve.bmp", 0, 128, 128)
        self.assertEqual(role4, ROLE_GLOVE)


class TestChromeShimmer(unittest.TestCase):
    """Verifies STUDIO_NF_CHROME (0x02) flag toggling."""

    def test_toggle_chrome(self):
        usp_path = resolve_model_path("usp", team="ct")
        model = MdlModel(usp_path)
        tex = model.textures[0]
        initial_flags = tex.flags

        # Toggle on
        model.toggle_chrome_shimmer(tex, enable=True)
        self.assertTrue(bool(tex.flags & STUDIO_NF_CHROME))

        # Toggle off
        model.toggle_chrome_shimmer(tex, enable=False)
        self.assertFalse(bool(tex.flags & STUDIO_NF_CHROME))


class TestStatTrakCustomizer(unittest.TestCase):
    """Verifies StatTrak LED digit color remapping and custom counter rendering."""

    def test_stat_digit_recolor(self):
        dummy_digit = Image.new("RGBA", (32, 47), (255, 120, 0, 255))
        for color_name in LED_COLORS.keys():
            recolored = recolor_digit_texture(dummy_digit, color_name=color_name)
            self.assertEqual(recolored.size, (32, 47))

            payload, _ = customize_stattrak_texture(
                dummy_digit, color_name=color_name, custom_number="001337"
            )
            self.assertEqual(len(payload), 32 * 47 + 768)

    def test_7segment_render(self):
        disp = render_7segment_display(width=32, height=47, number_str="1337", color_name="cyan")
        self.assertEqual(disp.size, (32, 47))

    def test_numeric_int_custom_number(self):
        dummy_digit = Image.new("RGBA", (32, 47), (255, 120, 0, 255))
        # Pass numeric integer directly
        payload, preview = customize_stattrak_texture(dummy_digit, color_name="green", custom_number=1337)
        self.assertEqual(len(payload), 32 * 47 + 768)
        self.assertEqual(preview.size, (32, 47))


class TestBakeCoordinates(unittest.TestCase):
    """Verifies WYSIWYG bake coordinate alignment and bounds clipping."""

    def test_baker_custom_coords_edge_clipping(self):
        base = Image.new("RGBA", (256, 256), (50, 50, 50, 255))
        sticker = Image.new("RGBA", (80, 80), (255, 0, 0, 255))

        # Position sticker center at (10, 10) so it hangs partially off top-left edge
        payload, comp = bake_sticker_onto_texture(
            base,
            sticker,
            custom_coords=(10, 10),
            scale_multiplier=1.0,
        )
        self.assertEqual(len(payload), 256 * 256 + 768)
        self.assertEqual(comp.size, (256, 256))
        comp_arr = np.array(comp)
        # Pixel at (10, 10) should have the sticker's red color
        self.assertEqual(comp_arr[10, 10, 0], 255)


class TestWearSimulator(unittest.TestCase):
    """Verifies procedural float wear simulation."""

    def test_wear_levels_and_payload(self):
        test_skin = Image.new("RGBA", (256, 256), (40, 60, 180, 255))
        for f in [0.00, 0.05, 0.20, 0.40, 0.75, 1.00]:
            name = get_wear_condition_name(f)
            self.assertIsInstance(name, str)

            payload, worn_img = simulate_and_quantize(test_skin, wear_float=f)
            self.assertEqual(len(payload), 256 * 256 + 768)
            self.assertEqual(worn_img.size, (256, 256))


class TestGloveTransfer(unittest.TestCase):
    """Verifies 1-click glove texture transfer between viewmodels."""

    def test_glove_role_classification(self):
        self.assertEqual(classify_glove_role("sport_right.bmp"), "right_glove")
        self.assertEqual(classify_glove_role("sport_left.bmp"), "left_glove")
        self.assertEqual(classify_glove_role("sleeve.bmp"), "sleeve")
        self.assertIsNone(classify_glove_role("ak47.bmp"))

    def test_transfer_gloves_usp_to_awp(self):
        usp_path = resolve_model_path("usp", team="ct")
        awp_path = resolve_model_path("awp", team="ct")

        temp_dir = tempfile.mkdtemp()
        try:
            test_usp = Path(temp_dir) / "v_usp.mdl"
            test_awp = Path(temp_dir) / "v_awp.mdl"
            shutil.copy2(usp_path, test_usp)
            shutil.copy2(awp_path, test_awp)

            res = transfer_gloves(test_usp, test_awp)
            self.assertTrue(res["success"])
            self.assertGreater(len(res["transferred"]), 0)
        finally:
            shutil.rmtree(temp_dir, ignore_errors=True)


class TestAdvancementsApiEndpoints(unittest.TestCase):
    """Integration test suite for all new REST endpoints."""

    @classmethod
    def setUpClass(cls):
        cls.temp_dir = tempfile.mkdtemp()
        cls.custom_ct_dir = Path(cls.temp_dir) / "cstrike" / "models" / "custom_skins" / "ct"
        cls.custom_ct_dir.mkdir(parents=True, exist_ok=True)

        real_usp = resolve_model_path("usp", team="ct")
        cls.test_usp = cls.custom_ct_dir / "v_usp.mdl"
        shutil.copy2(real_usp, cls.test_usp)

        real_awp = resolve_model_path("awp", team="ct")
        cls.test_awp = cls.custom_ct_dir / "v_awp.mdl"
        shutil.copy2(real_awp, cls.test_awp)

        cls.port = get_free_port()
        cls.server = create_server(host="127.0.0.1", port=cls.port, workspace_root=Path(cls.temp_dir))
        cls.server_thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.server_thread.start()
        time.sleep(0.3)

    @classmethod
    def tearDownClass(cls):
        try:
            cls.server.shutdown()
            cls.server.server_close()
        except Exception:
            pass
        shutil.rmtree(cls.temp_dir, ignore_errors=True)

    def _api_get(self, path):
        url = f"http://127.0.0.1:{self.port}{path}"
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=15) as res:
            return json.loads(res.read().decode("utf-8"))

    def _api_post(self, path, payload):
        url = f"http://127.0.0.1:{self.port}{path}"
        data = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=15) as res:
            return json.loads(res.read().decode("utf-8"))

    def test_api_model_3d(self):
        res = self._api_get("/api/model_3d?team=ct&weapon=usp")
        self.assertTrue(res["success"])
        self.assertGreater(res["mesh_count"], 0)
        self.assertIn("meshes", res)
        self.assertIn("bounds", res)
        self.assertIn("weapon_bounds", res)
        self.assertGreater(res["weapon_bounds"]["radius"], 0)
        self.assertTrue(any(m.get("role") == "skin" for m in res["meshes"]))

    def test_api_color_preview_and_apply(self):
        # Preview
        prev_res = self._api_post("/api/color_preview", {
            "team": "ct",
            "weapon": "usp",
            "texture_index": 3,
            "vibrance": 40,
            "clarity": 20,
        })
        self.assertTrue(prev_res["success"])
        self.assertTrue(prev_res["preview"].startswith("data:image/png;base64,"))

        # Apply
        apply_res = self._api_post("/api/color_apply", {
            "team": "ct",
            "weapon": "usp",
            "texture_index": 3,
            "vibrance": 40,
            "clarity": 20,
        })
        self.assertTrue(apply_res["success"])

    def test_api_color_preview_and_apply_with_hsl_mixer(self):
        """Verifies /api/color_preview and /api/color_apply accept 8-channel HSL mixer, hue, and sharpen."""
        payload = {
            "team": "ct",
            "weapon": "usp",
            "texture_index": 3,
            "contrast": 25,
            "hue": 45,
            "sharpen": 30,
            "hsl_adjustments": {
                "yellow": {"hue": 90, "saturation": 20, "lightness": -10},
                "cyan": {"hue": -30, "saturation": 50, "lightness": 15},
            },
        }
        prev = self._api_post("/api/color_preview", payload)
        self.assertTrue(prev["success"])
        self.assertTrue(prev["preview"].startswith("data:image/png;base64,"))

        applied = self._api_post("/api/color_apply", payload)
        self.assertTrue(applied["success"])
        self.assertTrue(applied["preview"].startswith("data:image/png;base64,"))

    def test_api_slot_tune_preview_and_apply(self):
        prev_res = self._api_post("/api/slot_tune_preview", {
            "team": "ct",
            "weapon": "usp",
            "texture_index": 6,  # 1.bmp
            "scale": 0.8,
            "offset_x": 10,
            "offset_y": -5,
            "rotation": 30,
        })
        self.assertTrue(prev_res["success"])
        self.assertTrue(prev_res["preview"].startswith("data:image/png;base64,"))

        apply_res = self._api_post("/api/slot_tune_apply", {
            "team": "ct",
            "weapon": "usp",
            "texture_index": 6,
            "scale": 0.8,
            "offset_x": 10,
            "offset_y": -5,
            "rotation": 30,
        })
        self.assertTrue(apply_res["success"])

    def test_api_stattrak_apply(self):
        res = self._api_post("/api/stattrak_apply", {
            "team": "ct",
            "weapon": "usp",
            "color": "cyan",
            "number": "001337",
        })
        self.assertTrue(res["success"])

    def test_api_wear_apply(self):
        res = self._api_post("/api/wear_apply", {
            "team": "ct",
            "weapon": "usp",
            "texture_index": 3,
            "wear_float": 0.35,
        })
        self.assertTrue(res["success"])
        self.assertEqual(res["tier_name"], "Field-Tested (FT)")

    def test_api_toggle_chrome(self):
        res = self._api_post("/api/toggle_chrome", {
            "team": "ct",
            "weapon": "usp",
            "texture_index": 6,
            "enable": True,
        })
        self.assertTrue(res["success"])
        self.assertTrue(res["is_chrome"])

    def test_api_glove_transfer(self):
        res = self._api_post("/api/glove_transfer", {
            "source_weapon": "usp",
            "target_weapons": ["awp"],
            "team": "ct",
            "sync_sleeves": True,
        })
        self.assertTrue(res["success"])
        self.assertIn("awp", res["results"])
        self.assertTrue(res["results"]["awp"]["success"])

    def test_api_bake_custom_coords(self):
        sticker = Image.new("RGBA", (32, 32), (255, 0, 0, 255))
        buf = io.BytesIO()
        sticker.save(buf, format="PNG")
        b64 = "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode("ascii")

        res = self._api_post("/api/bake", {
            "team": "ct",
            "weapon": "usp",
            "texture_index": 3,
            "coords": [50, 50],
            "scale": 1.0,
            "rotation": 0.0,
            "image_base64": b64,
        })
        self.assertTrue(res["success"])
        self.assertTrue(res["preview"].startswith("data:image/png;base64,"))

    def test_api_slot_tune_stretch_mode(self):
        sticker = Image.new("RGBA", (64, 32), (0, 255, 100, 255))
        buf = io.BytesIO()
        sticker.save(buf, format="PNG")
        b64 = "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode("ascii")

        prev = self._api_post("/api/slot_tune_preview", {
            "team": "ct",
            "weapon": "usp",
            "texture_index": 6,
            "scale": 1.0,
            "mode": "stretch",
            "image_base64": b64,
        })
        self.assertTrue(prev["success"])
        self.assertTrue(prev["preview"].startswith("data:image/png;base64,"))

    def test_api_stattrak_integer_number(self):
        res = self._api_post("/api/stattrak_apply", {
            "team": "ct",
            "weapon": "usp",
            "color": "red",
            "number": 1337,
        })
        self.assertTrue(res["success"])

    def test_baker_pre_emphasis_enhancement(self):
        """Verify Solusi 2: pre-emphasis vibrance/saturation, contrast, and unsharp masking."""
        base = Image.new("RGBA", (256, 256), (30, 30, 30, 255))
        sticker = Image.new("RGBA", (64, 64), (100, 150, 200, 255))

        # Bake without pre-emphasis
        _, comp_raw = bake_sticker_onto_texture(
            base, sticker, custom_coords=(128, 128), scale_multiplier=1.0, pre_emphasis=False
        )

        # Bake with pre-emphasis
        _, comp_enhanced = bake_sticker_onto_texture(
            base, sticker, custom_coords=(128, 128), scale_multiplier=1.0, pre_emphasis=True
        )

        raw_px = comp_raw.getpixel((128, 128))
        enh_px = comp_enhanced.getpixel((128, 128))

        # Color vibrance and contrast boost should alter the pixel values
        self.assertNotEqual(raw_px, enh_px)
        self.assertEqual(comp_raw.size, (256, 256))
        self.assertEqual(comp_enhanced.size, (256, 256))

    def test_api_bake_with_pre_emphasis_flag(self):
        """Verify /api/bake handles pre_emphasis flag cleanly."""
        sticker = Image.new("RGBA", (32, 32), (0, 180, 255, 255))
        buf = io.BytesIO()
        sticker.save(buf, format="PNG")
        b64 = "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode("ascii")

        res_on = self._api_post("/api/bake", {
            "team": "ct",
            "weapon": "usp",
            "coords": [100, 100],
            "scale": 1.0,
            "image_base64": b64,
            "pre_emphasis": True,
        })
        self.assertTrue(res_on["success"])
        self.assertTrue(res_on["preview"].startswith("data:image/png;base64,"))

        res_off = self._api_post("/api/bake_preview", {
            "team": "ct",
            "weapon": "usp",
            "coords": [100, 100],
            "scale": 1.0,
            "image_base64": b64,
            "pre_emphasis": False,
        })
        self.assertTrue(res_off["success"])
        self.assertTrue(res_off["preview"].startswith("data:image/png;base64,"))

    def test_baker_pre_emphasis_with_scrape_and_rotation(self):
        """Verify pre-emphasis works in synergy with scrape and rotation."""
        base = Image.new("RGBA", (256, 256), (40, 40, 40, 255))
        sticker = Image.new("RGBA", (64, 64), (20, 220, 240, 255))

        payload, comp = bake_sticker_onto_texture(
            base,
            sticker,
            custom_coords=(128, 128),
            scale_multiplier=1.2,
            rotation_deg=45.0,
            scrape=30.0,
            pre_emphasis=True,
        )
        self.assertEqual(len(payload), 256 * 256 + 768)
        self.assertEqual(comp.size, (256, 256))

    def test_baker_pre_emphasis_preserves_alpha_mask(self):
        """Verify pre-emphasis does not bleed beyond the sticker alpha boundaries."""
        base = Image.new("RGBA", (64, 64), (10, 10, 10, 255))
        # Sticker with transparent outer margin
        sticker = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
        # Center square 16x16 is opaque colored
        center = Image.new("RGBA", (16, 16), (255, 50, 50, 255))
        sticker.paste(center, (8, 8))

        _, comp = bake_sticker_onto_texture(
            base,
            sticker,
            custom_coords=(32, 32),
            scale_multiplier=1.0,
            pre_emphasis=True,
        )
        # Pixel far from center (e.g. at (5, 5)) must remain untouched base color (10, 10, 10, 255)
        self.assertEqual(comp.getpixel((5, 5)), (10, 10, 10, 255))
        # Center pixel (32, 32) must be modified by sticker
        self.assertNotEqual(comp.getpixel((32, 32)), (10, 10, 10, 255))

