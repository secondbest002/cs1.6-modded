"""
tests/test_cs16_studio.py - Comprehensive Unit and Integration Test Suite
for CS 1.6 Asset Studio.
"""

import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import struct
import tempfile
import unittest
import numpy as np
from PIL import Image, ImageDraw

from scripts.cs16_studio.mdl_core import (
    MdlModel,
    ROLE_SKIN,
    ROLE_STICKER,
    ROLE_GLOVE,
    ROLE_STATTRAK,
    STUDIO_MAGIC,
    STUDIO_VERSION,
    resolve_model_path,
    discover_available_models,
)
from scripts.cs16_studio.image_pipeline import (
    defringe_matte,
    resize_smart_fit,
    resize_stretch_uv,
    quantize_goldsrc,
    process_image_for_texture,
    GOLDSRC_MASK_COLOR,
)
from scripts.cs16_studio.baker import (
    bake_sticker_onto_texture,
    resolve_bake_position,
)


class TestMdlClassificationAndExtraction(unittest.TestCase):
    """Verifies dynamic texture classification on real models."""

    def test_usp_texture_classification(self):
        usp_path = resolve_model_path("usp", team="ct")
        self.assertTrue(os.path.isfile(usp_path), f"USP model not found: {usp_path}")

        model = MdlModel(usp_path)
        self.assertGreaterEqual(len(model.textures), 5)

        # In USP CT, pist_223_vanila.bmp is body skin
        skin_tex = model.find_texture("pist_223_vanila.bmp")
        self.assertIsNotNone(skin_tex, "pist_223_vanila.bmp should exist in v_usp.mdl")
        self.assertEqual(skin_tex.role, ROLE_SKIN)

        # In USP CT, 1.bmp, 2.bmp, 3.bmp, 4.bmp have flags & 0x40 and are stickers
        stickers = model.get_stickers()
        sticker_names = [s.name for s in stickers]
        self.assertIn("1.bmp", sticker_names)
        self.assertIn("2.bmp", sticker_names)
        for s in stickers:
            self.assertEqual(s.role, ROLE_STICKER)
            self.assertTrue(s.is_masked)

        # Check gloves and sleeve
        sleeve_tex = model.find_texture("sleeve.bmp")
        self.assertIsNotNone(sleeve_tex)
        self.assertEqual(sleeve_tex.role, ROLE_GLOVE)

    def test_awp_multi_part_skin_classification(self):
        awp_path = resolve_model_path("awp", team="ct")
        self.assertTrue(os.path.isfile(awp_path), f"AWP model not found: {awp_path}")

        model = MdlModel(awp_path)

        # In AWP CT, 1.bmp through 5.bmp have flags=0 and are body parts, NOT stickers
        for part_name in ["1.bmp", "2.bmp", "3.bmp", "4.bmp", "5.bmp"]:
            t = model.find_texture(part_name)
            self.assertIsNotNone(t, f"{part_name} should exist in AWP")
            self.assertEqual(t.role, ROLE_SKIN, f"AWP {part_name} must be classified as SKIN, not STICKER")
            self.assertFalse(t.is_masked)

        # In AWP CT, sticker_1.bmp through sticker_4.bmp have flags & 0x40 and ARE stickers
        for st_name in ["sticker_1.bmp", "sticker_2.bmp", "sticker_3.bmp", "sticker_4.bmp"]:
            t = model.find_texture(st_name)
            self.assertIsNotNone(t, f"{st_name} should exist in AWP")
            self.assertEqual(t.role, ROLE_STICKER, f"AWP {st_name} must be classified as STICKER")
            self.assertTrue(t.is_masked)


class TestImagePipelineAndQuantization(unittest.TestCase):
    """Verifies quantization, defringing, and Index 255 Pinning."""

    def test_transparency_pinning_and_payload_size(self):
        # Create a 1024x1024 test image with a circular logo and alpha gradient
        img = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0))
        draw = ImageDraw.Draw(img)
        # Solid red circle
        draw.ellipse((200, 200, 800, 800), fill=(220, 30, 30, 255))
        # Blue inner circle (to test that pure blue in art doesn't become transparent!)
        draw.ellipse((400, 400, 600, 600), fill=(0, 0, 255, 255))

        target_w, target_h = 176, 161
        expected_size = target_w * target_h + 768

        payload, preview = process_image_for_texture(
            img, target_w, target_h, is_masked=True, mode="fit"
        )

        self.assertEqual(len(payload), expected_size)
        self.assertEqual(preview.size, (target_w, target_h))

        # Check pixels and palette
        pixels = np.frombuffer(payload[: target_w * target_h], dtype=np.uint8)
        palette = list(payload[target_w * target_h :])

        self.assertEqual(len(palette), 768)

        # Palette Index 255 must be pure blue (0, 0, 255)
        p255_r = palette[255 * 3]
        p255_g = palette[255 * 3 + 1]
        p255_b = palette[255 * 3 + 2]
        self.assertEqual((p255_r, p255_g, p255_b), GOLDSRC_MASK_COLOR)

        # Transparent pixels must have index 255
        # The corners outside the circle should definitely be transparent (index 255)
        self.assertEqual(pixels[0], 255)  # top-left corner
        self.assertEqual(pixels[-1], 255)  # bottom-right corner

        # Center pixel (from the inner blue circle) MUST NOT have index 255!
        center_idx = (target_h // 2) * target_w + (target_w // 2)
        self.assertNotEqual(
            pixels[center_idx],
            255,
            "Center solid pixel should NOT be index 255 (no transparent holes allowed in art!)",
        )

    def test_matte_defringing(self):
        # Semi-transparent edge test
        img = Image.new("RGBA", (100, 100), (0, 0, 0, 0))
        draw = ImageDraw.Draw(img)
        # Outer semi-transparent ring
        draw.ellipse((10, 10, 90, 90), fill=(200, 100, 50, 100))
        # Inner solid circle
        draw.ellipse((30, 30, 70, 70), fill=(200, 100, 50, 255))

        defringed = defringe_matte(img, alpha_thresh=128)
        self.assertEqual(defringed.size, (100, 100))

        alpha = np.array(defringed.split()[-1])
        unique_alphas = np.unique(alpha)
        # Should be strictly binary alpha: only 0 and 255
        for a in unique_alphas:
            self.assertIn(a, [0, 255])


class TestBakingEngine(unittest.TestCase):
    """Verifies 2D texture baking onto weapon skin."""

    def test_bake_sticker_composite(self):
        base_skin = Image.new("RGBA", (512, 512), (50, 50, 50, 255))
        sticker = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
        draw = ImageDraw.Draw(sticker)
        draw.rectangle((50, 50, 200, 200), fill=(255, 215, 0, 255))

        payload, composite = bake_sticker_onto_texture(
            base_skin, sticker, weapon_key="usp", preset="silencer", scale_multiplier=1.0
        )

        expected_size = 512 * 512 + 768
        self.assertEqual(len(payload), expected_size)
        self.assertEqual(composite.size, (512, 512))

        # Check composite pixel at silencer location (approx 360, 180)
        c_arr = np.array(composite)
        # Color at (180, 360) should be gold (255, 215, 0)
        pixel_color = c_arr[180, 360]
        self.assertEqual(pixel_color[0], 255)
        self.assertEqual(pixel_color[1], 215)
        self.assertEqual(pixel_color[2], 0)


class TestAtomicLifecycleAndBackupRestore(unittest.TestCase):
    """Verifies atomic injection, immutable .orig.mdl backup, and restoration."""

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
        # Copy real v_usp.mdl to temp directory
        src_usp = resolve_model_path("usp", team="ct")
        self.test_mdl = Path(self.temp_dir) / "v_usp.mdl"
        shutil.copy2(src_usp, self.test_mdl)

        # Compute initial hash
        with open(self.test_mdl, "rb") as f:
            self.initial_hash = hashlib.md5(f.read()).hexdigest()

    def tearDown(self):
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_immutable_backup_and_full_restore(self):
        model = MdlModel(self.test_mdl)

        # Inject into sticker slot 1 (1.bmp, 176x161)
        tex = model.find_texture("1.bmp")
        self.assertIsNotNone(tex)

        dummy_img = Image.new("RGBA", (176, 161), (255, 0, 0, 255))
        payload, _ = process_image_for_texture(dummy_img, 176, 161, is_masked=True)

        model.save_slot_snapshot(tex)
        model.inject_texture_payload(tex, payload)
        saved_path = model.save_atomic(create_backup=True)

        self.assertTrue(saved_path.exists())

        # Verify .orig.mdl exists
        orig_backup = self.test_mdl.with_suffix(".orig.mdl")
        self.assertTrue(orig_backup.exists(), "Immutable .orig.mdl must be created on first modification")

        # Verify modified hash differs
        with open(self.test_mdl, "rb") as f:
            modified_hash = hashlib.md5(f.read()).hexdigest()
        self.assertNotEqual(modified_hash, self.initial_hash)

        # Verify .orig.mdl hash matches initial hash
        with open(orig_backup, "rb") as f:
            orig_hash = hashlib.md5(f.read()).hexdigest()
        self.assertEqual(orig_hash, self.initial_hash)

        # Now test single-slot revert
        reloaded = MdlModel(self.test_mdl)
        revert_ok = reloaded.revert_texture_from_backup("1.bmp")
        self.assertTrue(revert_ok)

        # Re-check hash after slot revert: should be back to initial!
        with open(self.test_mdl, "rb") as f:
            reverted_hash = hashlib.md5(f.read()).hexdigest()
        self.assertEqual(reverted_hash, self.initial_hash)

        # Now modify again and test full restore
        model2 = MdlModel(self.test_mdl)
        model2.inject_texture_payload("1.bmp", payload)
        model2.save_atomic(create_backup=True)

        # Restore from original
        restored_ok = model2.restore_from_immutable_original()
        self.assertTrue(restored_ok)

        with open(self.test_mdl, "rb") as f:
            final_hash = hashlib.md5(f.read()).hexdigest()
        self.assertEqual(final_hash, self.initial_hash, "Restored file must match original hash 100%")

    def test_numeric_identifier_resolution_and_slot_revert(self):
        """Verifies that '1' resolves to '1.bmp' (sticker), NOT raw index 1 ('sport_left.bmp')."""
        model = MdlModel(self.test_mdl)

        # On USP, texture at index 1 is sport_left.bmp, but 1.bmp is sticker slot 1 (index 6)
        tex_by_digit = model.find_texture("1")
        self.assertIsNotNone(tex_by_digit)
        self.assertEqual(
            tex_by_digit.name,
            "1.bmp",
            f"find_texture('1') must resolve to '1.bmp', but got '{tex_by_digit.name}'",
        )
        self.assertEqual(tex_by_digit.role, ROLE_STICKER)

        # Inject into '1'
        dummy_img = Image.new("RGBA", (176, 161), (0, 255, 0, 255))
        payload, _ = process_image_for_texture(dummy_img, 176, 161, is_masked=True)
        model.save_slot_snapshot(tex_by_digit)
        model.inject_texture_payload(tex_by_digit, payload)
        model.save_atomic(create_backup=True)

        # Revert passing '1' (numeric slot input)
        reloaded = MdlModel(self.test_mdl)
        revert_ok = reloaded.revert_texture_from_backup("1")
        self.assertTrue(revert_ok, "revert_texture_from_backup('1') must succeed")

        with open(self.test_mdl, "rb") as f:
            reverted_hash = hashlib.md5(f.read()).hexdigest()
        self.assertEqual(
            reverted_hash,
            self.initial_hash,
            "Reverting via slot '1' must restore original file hash exactly",
        )


class TestEdgeCasesAndRobustness(unittest.TestCase):
    """Verifies untested edge cases and boundary conditions."""

    def test_all_semi_transparent_image_quantization(self):
        """Edge case: Image where ALL alpha values are 1..127 (below 128 threshold)."""
        img = Image.new("RGBA", (64, 64), (200, 100, 50, 80))  # alpha = 80 (< 128)
        payload, preview = process_image_for_texture(img, 64, 64, is_masked=True)

        expected_size = 64 * 64 + 768
        self.assertEqual(len(payload), expected_size)

        # All pixels must safely default to index 255 (transparent)
        pixels = np.frombuffer(payload[: 64 * 64], dtype=np.uint8)
        self.assertTrue(np.all(pixels == 255), "All pixels must be transparent index 255")

        palette = list(payload[64 * 64 :])
        self.assertEqual(
            (palette[255 * 3], palette[255 * 3 + 1], palette[255 * 3 + 2]),
            GOLDSRC_MASK_COLOR,
        )

    def test_smart_fit_aspect_ratio_preservation_under_scale(self):
        """Verifies that scale multiplier > 1.0 never distorts aspect ratio on non-square canvas."""
        # Non-square target: 176x161
        target_w, target_h = 176, 161
        square_logo = Image.new("RGBA", (400, 400), (255, 0, 0, 255))

        fitted = resize_smart_fit(square_logo, target_w, target_h, scale_multiplier=1.5)
        self.assertEqual(fitted.size, (target_w, target_h))

        # Check the bounding box of non-transparent pixels
        bbox = fitted.getbbox()
        self.assertIsNotNone(bbox)
        logo_w = bbox[2] - bbox[0]
        logo_h = bbox[3] - bbox[1]
        # Aspect ratio must remain 1:1 (square logo should not become rectangular)
        self.assertEqual(
            logo_w,
            logo_h,
            f"Square logo distorted on non-square canvas: {logo_w}x{logo_h}",
        )

    def test_cli_ui_parser(self):
        """Verifies both 'cs16_studio.py --ui' and 'cs16_studio.py ui' parse without error."""
        from scripts.cs16_studio.cli import build_parser

        parser = build_parser()
        args1 = parser.parse_args(["ui", "--port", "5165"])
        self.assertEqual(args1.command, "ui")
        self.assertEqual(args1.port, 5165)

        args2 = parser.parse_args(["--ui", "--port", "5166"])
        self.assertTrue(args2.ui)
        self.assertEqual(args2.port, 5166)


if __name__ == "__main__":
    unittest.main()
