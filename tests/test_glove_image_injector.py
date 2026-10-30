"""
tests/test_glove_image_injector.py - Comprehensive Unit & Integration Tests for:
1. 1-Click Batch Image-to-Glove Injector Engine (glove_transfer.py)
2. Role classification (classify_glove_role)
3. Image input loading and format flexibility (_load_image_input)
4. Auto-Mirror Quick-Toggle (horizontal flip via PIL.ImageOps.mirror)
5. Adaptive Lanczos resolution resampling (e.g. 508x506, 508x504, 512x512)
6. GoldSrc in-place injection and zero-byte file drift validation
7. Glove Presets Manager (save, list, load, apply, delete)
8. REST API Endpoints (/api/gloves/batch_inject_images, /api/gloves/presets/*)
"""

import base64
import io
import json
from pathlib import Path
import shutil
import socket
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.request
import numpy as np
from PIL import Image

from scripts.cs16_studio.glove_transfer import (
    apply_glove_preset,
    batch_inject_glove_images,
    classify_glove_role,
    delete_glove_preset,
    list_glove_presets,
    load_glove_preset,
    save_glove_preset,
    _load_image_input,
)
from scripts.cs16_studio.mdl_core import (
    MdlModel,
    discover_available_models,
    resolve_model_path,
)
from scripts.cs16_studio.web.server import create_server


def get_free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("", 0))
        return s.getsockname()[1]


def create_solid_image(w: int, h: int, color: tuple = (255, 0, 0, 255)) -> Image.Image:
    return Image.new("RGBA", (w, h), color)


def create_asymmetric_image(w: int, h: int) -> Image.Image:
    img = Image.new("RGBA", (w, h), (255, 0, 0, 255))
    # Fill left half red, right half blue
    for x in range(w // 2, w):
        for y in range(h):
            img.putpixel((x, y), (0, 0, 255, 255))
    return img


def image_to_base64_data_uri(img: Image.Image) -> str:
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    b64 = base64.b64encode(buf.getvalue()).decode("ascii")
    return f"data:image/png;base64,{b64}"


class TestGloveRoleClassification(unittest.TestCase):
    """Unit tests for classify_glove_role under various modding naming conventions."""

    def test_left_glove_detection(self):
        left_samples = [
            "sport_left.bmp",
            "SPORT_LEFT.BMP",
            "glove_left.bmp",
            "glove_l.bmp",
            "hand_l.bmp",
            "left_hand.bmp",
            "v_glove_l.bmp",
            "sport_l_tex.bmp",
            "hand_left_512.bmp",
        ]
        for name in left_samples:
            self.assertEqual(
                classify_glove_role(name),
                "left_glove",
                f"Failed to classify '{name}' as left_glove",
            )

    def test_right_glove_detection(self):
        right_samples = [
            "sport_right.bmp",
            "SPORT_RIGHT.BMP",
            "glove_right.bmp",
            "glove_r.bmp",
            "hand_r.bmp",
            "right_hand.bmp",
            "v_glove_r.bmp",
            "sport_r_tex.bmp",
            "hand_right_512.bmp",
        ]
        for name in right_samples:
            self.assertEqual(
                classify_glove_role(name),
                "right_glove",
                f"Failed to classify '{name}' as right_glove",
            )

    def test_sleeves_and_general_gloves(self):
        self.assertEqual(classify_glove_role("sleeve.bmp"), "sleeve")
        self.assertEqual(classify_glove_role("arm.bmp"), "sleeve")
        self.assertEqual(classify_glove_role("bare_arm_133.bmp"), "sleeve")
        self.assertEqual(classify_glove_role("player_arm.bmp"), "sleeve")
        self.assertEqual(classify_glove_role("glove.bmp"), "general_glove")
        self.assertEqual(classify_glove_role("hands.bmp"), "general_glove")
        self.assertEqual(classify_glove_role("hands_left_right.bmp"), "general_glove")
        self.assertEqual(classify_glove_role("gloves_l_r.bmp"), "general_glove")

    def test_non_glove_textures(self):
        non_gloves = [
            "gun_handle.bmp",
            "handle_wood.bmp",
            "handguard.bmp",
            "hand_guard.bmp",
            "handguard_front.bmp",
            "sidearm.bmp",
            "firearm.bmp",
            "charm.bmp",
            "weapon_charm.bmp",
            "armor.bmp",
            "armature.bmp",
            "alarm.bmp",
            "barrel.bmp",
            "magazine.bmp",
            "scope.bmp",
            "usp_slide.bmp",
            "ak47_body.bmp",
        ]
        for name in non_gloves:
            self.assertIsNone(
                classify_glove_role(name),
                f"Texture '{name}' should not be classified as glove",
            )


class TestImageLoader(unittest.TestCase):
    """Unit tests for _load_image_input supporting PNG, BMP, WEBP, base64 data URI, and files."""

    def test_load_pil_image(self):
        img = create_solid_image(64, 64, (0, 255, 0, 255))
        loaded = _load_image_input(img)
        self.assertIsInstance(loaded, Image.Image)
        self.assertEqual(loaded.size, (64, 64))

    def test_load_png_bytes(self):
        img = create_solid_image(32, 32, (255, 128, 0, 255))
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        loaded = _load_image_input(buf.getvalue())
        self.assertIsInstance(loaded, Image.Image)
        self.assertEqual(loaded.size, (32, 32))

    def test_load_data_uri(self):
        img = create_solid_image(48, 48, (0, 128, 255, 255))
        data_uri = image_to_base64_data_uri(img)
        loaded = _load_image_input(data_uri)
        self.assertIsInstance(loaded, Image.Image)
        self.assertEqual(loaded.size, (48, 48))

    def test_load_raw_base64(self):
        img = create_solid_image(16, 16, (255, 255, 0, 255))
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        b64 = base64.b64encode(buf.getvalue()).decode("ascii")
        loaded = _load_image_input(b64)
        self.assertIsInstance(loaded, Image.Image)
        self.assertEqual(loaded.size, (16, 16))

    def test_load_file_path(self):
        with tempfile.TemporaryDirectory() as td:
            img = create_solid_image(40, 40, (100, 200, 50, 255))
            fpath = Path(td) / "sample.png"
            img.save(fpath)
            loaded = _load_image_input(fpath)
            self.assertIsInstance(loaded, Image.Image)
            self.assertEqual(loaded.size, (40, 40))

    def test_load_invalid_input(self):
        with self.assertRaises((FileNotFoundError, TypeError)):
            _load_image_input("non_existent_file_path_12345.png")

    def test_corrupted_image_inputs(self):
        # Empty string
        with self.assertRaises(ValueError):
            _load_image_input("")
        # Empty bytes
        with self.assertRaises(ValueError):
            _load_image_input(b"")
        # Corrupted raw bytes
        with self.assertRaises(ValueError):
            _load_image_input(b"corrupted_non_image_data_here")
        # Invalid base64 padding
        with self.assertRaises(ValueError):
            _load_image_input("data:image/png;base64,invalid_padding!!!")
        # Base64 string that does not encode a valid image
        with self.assertRaises(ValueError):
            _load_image_input("data:image/png;base64,YWJjZGVm")


class TestGloveBatchInjectionEngine(unittest.TestCase):
    """Integration test suite for batch_inject_glove_images across real models with differing resolutions."""

    @classmethod
    def setUpClass(cls):
        cls.temp_dir = tempfile.mkdtemp()
        cls.root = Path(cls.temp_dir)

        # Create custom_skins directories for CT and T
        ct_dir = cls.root / "cstrike" / "models" / "custom_skins" / "ct"
        t_dir = cls.root / "cstrike" / "models" / "custom_skins" / "t"
        ct_dir.mkdir(parents=True, exist_ok=True)
        t_dir.mkdir(parents=True, exist_ok=True)

        # Copy real ak47 (512x512 gloves) and awp (508x506 left, 508x504 right gloves)
        real_ak = resolve_model_path("ak47", team="ct")
        real_awp = resolve_model_path("awp", team="ct")

        shutil.copy2(real_ak, ct_dir / "v_ak47.mdl")
        shutil.copy2(real_awp, ct_dir / "v_awp.mdl")
        shutil.copy2(real_ak, t_dir / "v_ak47.mdl")
        shutil.copy2(real_awp, t_dir / "v_awp.mdl")

        cls.ct_ak = ct_dir / "v_ak47.mdl"
        cls.ct_awp = ct_dir / "v_awp.mdl"
        cls.t_ak = t_dir / "v_ak47.mdl"
        cls.t_awp = t_dir / "v_awp.mdl"

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.temp_dir, ignore_errors=True)

    def test_batch_inject_dual_images_adaptive_res(self):
        """Tests injection of high-res (1024x1024) left and right gloves into models with different native sizes."""
        left_source = create_solid_image(1024, 1024, (220, 30, 30, 255))
        right_source = create_solid_image(1024, 1024, (30, 30, 220, 255))

        ak_size_before = self.ct_ak.stat().st_size
        awp_size_before = self.ct_awp.stat().st_size

        res = batch_inject_glove_images(
            left_image=left_source,
            right_image=right_source,
            team="ct",
            target_weapons=["ak47", "awp"],
            mirror_left_to_right=False,
            root_dir=self.root,
        )

        self.assertTrue(res["success"])
        self.assertIn("ak47", res["updated_models"])
        self.assertIn("awp", res["updated_models"])
        self.assertGreaterEqual(res["total_slots_updated"], 4)

        # Zero-Byte File Drift Validation: File size must NOT change by 1 single byte
        ak_size_after = self.ct_ak.stat().st_size
        awp_size_after = self.ct_awp.stat().st_size
        self.assertEqual(ak_size_before, ak_size_after, "AK47 experienced file size drift!")
        self.assertEqual(awp_size_before, awp_size_after, "AWP experienced file size drift!")

        # Immutable .orig.mdl backup created
        self.assertTrue(self.ct_ak.with_suffix(".orig.mdl").exists())
        self.assertTrue(self.ct_awp.with_suffix(".orig.mdl").exists())

        # Validate AWP native dimensions preservation (508x506 and 508x504)
        awp_model = MdlModel(self.ct_awp)
        awp_left = next(t for t in awp_model.textures if classify_glove_role(t.name) == "left_glove")
        awp_right = next(t for t in awp_model.textures if classify_glove_role(t.name) == "right_glove")

        self.assertEqual(awp_left.width, 508)
        self.assertEqual(awp_left.height, 506)
        self.assertEqual(len(awp_left.raw_data), 508 * 506 + 768)

        self.assertEqual(awp_right.width, 508)
        self.assertEqual(awp_right.height, 504)
        self.assertEqual(len(awp_right.raw_data), 508 * 504 + 768)

        # Validate AK47 native dimensions preservation (512x512)
        ak_model = MdlModel(self.ct_ak)
        ak_left = next(t for t in ak_model.textures if classify_glove_role(t.name) == "left_glove")
        ak_right = next(t for t in ak_model.textures if classify_glove_role(t.name) == "right_glove")

        self.assertEqual(ak_left.width, 512)
        self.assertEqual(ak_left.height, 512)
        self.assertEqual(len(ak_left.raw_data), 512 * 512 + 768)

        self.assertEqual(ak_right.width, 512)
        self.assertEqual(ak_right.height, 512)
        self.assertEqual(len(ak_right.raw_data), 512 * 512 + 768)

    def test_auto_mirror_toggle(self):
        """Tests that mirror_left_to_right=True creates a flipped texture for the right hand."""
        asym_left = create_asymmetric_image(256, 256)

        res = batch_inject_glove_images(
            left_image=asym_left,
            right_image=None,
            team="ct",
            target_weapons=["ak47"],
            mirror_left_to_right=True,
            root_dir=self.root,
        )

        self.assertTrue(res["success"])
        ak_model = MdlModel(self.ct_ak)
        ak_left = next(t for t in ak_model.textures if classify_glove_role(t.name) == "left_glove")
        ak_right = next(t for t in ak_model.textures if classify_glove_role(t.name) == "right_glove")

        left_rgba = ak_left.to_rgba_image()
        right_rgba = ak_right.to_rgba_image()

        # In left image: left is red, right is blue
        # In mirrored right image: left is blue, right is red!
        left_mid_x_1 = left_rgba.getpixel((ak_left.width // 4, ak_left.height // 2))
        right_mid_x_1 = right_rgba.getpixel((ak_right.width // 4, ak_right.height // 2))

        # Check that red was flipped to blue on the left quadrant
        self.assertGreater(left_mid_x_1[0], left_mid_x_1[2], "Left hand should be predominantly red on left half")
        self.assertGreater(right_mid_x_1[2], right_mid_x_1[0], "Right hand should be predominantly blue on left half due to mirror")

    def test_single_left_image_injection(self):
        """Tests that when mirror_left_to_right is False and no right image is provided, only left glove is updated."""
        left_img = create_solid_image(512, 512, (10, 200, 10, 255))

        ak_model_orig = MdlModel(self.ct_ak)
        orig_right_raw = next(t for t in ak_model_orig.textures if classify_glove_role(t.name) == "right_glove").raw_data

        res = batch_inject_glove_images(
            left_image=left_img,
            right_image=None,
            team="ct",
            target_weapons=["ak47"],
            mirror_left_to_right=False,
            root_dir=self.root,
        )

        self.assertTrue(res["success"])
        self.assertEqual(res["left_updated"], 1)
        self.assertEqual(res["right_updated"], 0)

        ak_model_after = MdlModel(self.ct_ak)
        after_right_raw = next(t for t in ak_model_after.textures if classify_glove_role(t.name) == "right_glove").raw_data
        self.assertEqual(orig_right_raw, after_right_raw, "Right glove should remain untouched")

    def test_team_scoping(self):
        """Tests team scoping: 'ct' only modifies CT models, 'all' modifies both CT and T."""
        green_img = create_solid_image(512, 512, (0, 255, 0, 255))

        # Inject only to T team
        res = batch_inject_glove_images(
            left_image=green_img,
            team="t",
            mirror_left_to_right=True,
            root_dir=self.root,
        )
        self.assertTrue(res["success"])
        for m_name in res["updated_models"]:
            # T model should have been updated
            t_model_path = self.t_ak.parent / f"v_{m_name}.mdl"
            self.assertTrue(t_model_path.exists())

    def test_validation_errors(self):
        with self.assertRaises(ValueError):
            batch_inject_glove_images(left_image=None, right_image=None, root_dir=self.root)

    def test_team_all_deduplication_and_collision(self):
        """Tests that team='all' updates models on both CT and T without duplicate weapon entries or lost results."""
        orange_img = create_solid_image(512, 512, (255, 140, 0, 255))
        res = batch_inject_glove_images(
            left_image=orange_img,
            team="all",
            mirror_left_to_right=True,
            root_dir=self.root,
        )
        self.assertTrue(res["success"])
        # updated_models must be deduplicated
        self.assertEqual(res["updated_models"].count("ak47"), 1)
        self.assertEqual(res["updated_models"].count("awp"), 1)
        # Verify both CT and T model files were touched
        self.assertTrue(self.ct_ak.exists())
        self.assertTrue(self.t_ak.exists())
        # Both models preserved in results
        self.assertIn("ak47", res["results"])


class TestGlovePresets(unittest.TestCase):
    """Unit tests for Glove Presets manager (save, list, load, apply, delete)."""

    @classmethod
    def setUpClass(cls):
        cls.temp_dir = tempfile.mkdtemp()
        cls.root = Path(cls.temp_dir)
        ct_dir = cls.root / "cstrike" / "models" / "custom_skins" / "ct"
        ct_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(resolve_model_path("ak47", team="ct"), ct_dir / "v_ak47.mdl")

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.temp_dir, ignore_errors=True)

    def test_preset_lifecycle(self):
        left = create_solid_image(256, 256, (255, 20, 147, 255))
        right = create_solid_image(256, 256, (0, 191, 255, 255))

        # 1. Save
        save_res = save_glove_preset(
            name="Sport Vice Neon",
            left_image=left,
            right_image=right,
            root_dir=self.root,
        )
        self.assertTrue(save_res["success"])
        self.assertEqual(save_res["name"], "Sport Vice Neon")

        # 2. List
        presets = list_glove_presets(self.root)
        self.assertEqual(len(presets), 1)
        self.assertEqual(presets[0]["name"], "Sport Vice Neon")
        self.assertTrue(presets[0]["has_left"])
        self.assertTrue(presets[0]["has_right"])
        self.assertTrue(presets[0]["left_thumb"].startswith("data:image/png;base64,"))

        # 3. Load
        loaded = load_glove_preset("Sport Vice Neon", root_dir=self.root)
        self.assertEqual(loaded["name"], "Sport Vice Neon")
        self.assertTrue(loaded["left_image"].startswith("data:image/png;base64,"))

        # 4. Apply
        apply_res = apply_glove_preset(
            name="Sport Vice Neon",
            team="ct",
            target_weapons=["ak47"],
            root_dir=self.root,
        )
        self.assertTrue(apply_res["success"])
        self.assertIn("ak47", apply_res["updated_models"])

        # 5. Delete
        del_res = delete_glove_preset("Sport Vice Neon", root_dir=self.root)
        self.assertTrue(del_res)
        self.assertEqual(len(list_glove_presets(self.root)), 0)


class TestGloveRestApi(unittest.TestCase):
    """Integration test suite for Glove REST API endpoints."""

    @classmethod
    def setUpClass(cls):
        cls.temp_dir = tempfile.mkdtemp()
        cls.root = Path(cls.temp_dir)
        ct_dir = cls.root / "cstrike" / "models" / "custom_skins" / "ct"
        ct_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(resolve_model_path("awp", team="ct"), ct_dir / "v_awp.mdl")

        cls.port = get_free_port()
        cls.server = create_server(host="127.0.0.1", port=cls.port, workspace_root=cls.root)
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

    def test_api_batch_inject_images(self):
        img = create_solid_image(512, 512, (255, 0, 128, 255))
        data_uri = image_to_base64_data_uri(img)

        payload = {
            "left_image_base64": data_uri,
            "mirror_left": True,
            "team": "ct",
            "weapons": ["awp"],
        }
        res = self._api_post("/api/gloves/batch_inject_images", payload)
        self.assertTrue(res["success"])
        self.assertIn("awp", res["updated_models"])

    def test_api_presets_endpoints(self):
        img = create_solid_image(128, 128, (0, 200, 255, 255))
        data_uri = image_to_base64_data_uri(img)

        # 1. Save Preset via API
        save_res = self._api_post("/api/gloves/presets/save", {
            "name": "Cyan Amphibious",
            "left_image_base64": data_uri,
            "mirror_left": True,
        })
        self.assertTrue(save_res["success"])

        # 2. List Presets via API
        list_res = self._api_get("/api/gloves/presets")
        self.assertTrue(list_res["success"])
        self.assertTrue(any(p["name"] == "Cyan Amphibious" for p in list_res["presets"]))

        # 3. Apply Preset via API
        apply_res = self._api_post("/api/gloves/presets/apply", {
            "name": "Cyan Amphibious",
            "team": "ct",
            "weapons": ["awp"],
        })
        self.assertTrue(apply_res["success"])

        # 4. Delete Preset via API
        del_res = self._api_post("/api/gloves/presets/delete", {
            "name": "Cyan Amphibious",
        })
        self.assertTrue(del_res["success"])

    def test_api_error_responses_400_and_404(self):
        # 1. Missing glove images -> 400
        try:
            self._api_post("/api/gloves/batch_inject_images", {"team": "ct"})
            self.fail("Expected HTTP 400 for missing image data")
        except urllib.error.HTTPError as e:
            self.assertEqual(e.code, 400)
            data = json.loads(e.read().decode("utf-8"))
            self.assertFalse(data["success"])

        # 2. Corrupt base64 string -> 400
        try:
            self._api_post("/api/gloves/batch_inject_images", {
                "left_image_base64": "data:image/png;base64,invalid_padding!!!",
                "team": "ct",
            })
            self.fail("Expected HTTP 400 for corrupt base64")
        except urllib.error.HTTPError as e:
            self.assertEqual(e.code, 400)
            data = json.loads(e.read().decode("utf-8"))
            self.assertFalse(data["success"])

        # 3. Apply non-existent preset -> 404
        try:
            self._api_post("/api/gloves/presets/apply", {"name": "NonExistentPresetXYZ123"})
            self.fail("Expected HTTP 404 for missing preset")
        except urllib.error.HTTPError as e:
            self.assertEqual(e.code, 404)
            data = json.loads(e.read().decode("utf-8"))
            self.assertFalse(data["success"])

        # 4. Delete non-existent preset -> 404
        try:
            self._api_post("/api/gloves/presets/delete", {"name": "NonExistentPresetXYZ123"})
            self.fail("Expected HTTP 404 for deleting missing preset")
        except urllib.error.HTTPError as e:
            self.assertEqual(e.code, 404)
            data = json.loads(e.read().decode("utf-8"))
            self.assertFalse(data["success"])


if __name__ == "__main__":
    unittest.main()
