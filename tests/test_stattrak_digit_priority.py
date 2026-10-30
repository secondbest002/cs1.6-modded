"""
tests/test_stattrak_digit_priority.py - Unit & integration tests for:
1. StatTrak texture priority (digit textures over module casing).
2. Explicit texture_index & texture_name override in StatTrak modifier.
3. Sticker library complete freedom: deletion of built-in stickers with .initialized marker.
4. Restoration of default tournament stickers via restore_default_stickers and API.
"""

import base64
import json
from pathlib import Path
import shutil
import socket
import tempfile
import threading
import time
import unittest
import urllib.request
import urllib.parse
import urllib.error
from PIL import Image

from scripts.cs16_studio.asset_library import (
    delete_custom_sticker,
    edit_custom_sticker,
    ensure_builtin_assets,
    get_library_stickers,
    restore_default_stickers,
)
from scripts.cs16_studio.mdl_core import MdlModel
from scripts.cs16_studio.web.server import create_server


def get_free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("", 0))
        return s.getsockname()[1]


class TestStatTrakDigitPriorityAndLibraryFreedom(unittest.TestCase):

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
        self.root = Path(self.temp_dir)
        ensure_builtin_assets(self.root)

    def tearDown(self):
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_marker_initialized_created(self):
        marker = self.root / "assets" / ".initialized"
        self.assertTrue(marker.is_file(), "assets/.initialized must exist after ensure_builtin_assets")

    def test_delete_builtin_sticker_with_allow_builtin(self):
        target = self.root / "assets" / "stickers" / "titan_holo.png"
        self.assertTrue(target.is_file(), "titan_holo.png should exist initially")

        # Deleting with allow_builtin=True must succeed
        res = delete_custom_sticker("titan_holo.png", workspace_root=self.root, allow_builtin=True)
        self.assertTrue(res["success"])
        self.assertFalse(target.exists(), "titan_holo.png must be deleted from disk")

        # Subsequent call to ensure_builtin_assets must NOT recreate it
        ensure_builtin_assets(self.root)
        self.assertFalse(target.exists(), "ensure_builtin_assets must not resurrect deleted sticker")

        # Verify not returned in get_library_stickers
        stickers = get_library_stickers(self.root)
        filenames = [s["filename"] for s in stickers]
        self.assertNotIn("titan_holo.png", filenames)

    def test_restore_default_stickers(self):
        target = self.root / "assets" / "stickers" / "dignitas_holo.png"
        self.assertTrue(target.is_file())

        delete_custom_sticker("dignitas_holo.png", workspace_root=self.root, allow_builtin=True)
        self.assertFalse(target.exists())

        # Restore default stickers
        res = restore_default_stickers(self.root)
        self.assertTrue(res["success"])
        self.assertTrue(target.is_file(), "dignitas_holo.png must be recreated on restore")

        stickers = get_library_stickers(self.root)
        filenames = [s["filename"] for s in stickers]
        self.assertIn("dignitas_holo.png", filenames)

    def test_edit_builtin_sticker_metadata(self):
        # Renaming a built-in sticker in assets/stickers
        res = edit_custom_sticker(
            "crown_foil.png",
            new_name="Royal Crown Foil Edition",
            new_category="King Collection",
            workspace_root=self.root,
        )
        self.assertTrue(res["success"])
        self.assertEqual(res["name"], "Royal Crown Foil Edition")
        self.assertEqual(res["category"], "King Collection")

        stickers = get_library_stickers(self.root)
        match = [s for s in stickers if s["filename"] == "crown_foil.png"][0]
        self.assertEqual(match["name"], "Royal Crown Foil Edition")
        self.assertEqual(match["category"], "King Collection")


class TestStatTrakIntegrationAndServerEndpoints(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.temp_dir = tempfile.mkdtemp()
        cls.root = Path(cls.temp_dir)
        ensure_builtin_assets(cls.root)

        # Copy real AK-47 model from workspace to test temp dir
        repo_root = Path(__file__).resolve().parent.parent
        src_ak47 = repo_root / "cstrike" / "models" / "custom_skins" / "ct" / "v_ak47.mdl"

        dest_dir = cls.root / "cstrike" / "models" / "custom_skins" / "ct"
        dest_dir.mkdir(parents=True, exist_ok=True)
        if src_ak47.is_file():
            shutil.copy2(src_ak47, dest_dir / "v_ak47.mdl")
            # Also create backup original
            shutil.copy2(src_ak47, dest_dir / "v_ak47.orig.mdl")

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
        req = urllib.request.Request(url, method="GET")
        with urllib.request.urlopen(req, timeout=5) as resp:
            return json.loads(resp.read().decode("utf-8"))

    def _api_post(self, path, payload):
        url = f"http://127.0.0.1:{self.port}{path}"
        data = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"}, method="POST")
        with urllib.request.urlopen(req, timeout=5) as resp:
            return json.loads(resp.read().decode("utf-8"))

    def _api_post_with_status(self, path, payload):
        url = f"http://127.0.0.1:{self.port}{path}"
        data = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"}, method="POST")
        try:
            with urllib.request.urlopen(req, timeout=5) as resp:
                return json.loads(resp.read().decode("utf-8")), resp.status
        except urllib.error.HTTPError as e:
            return json.loads(e.read().decode("utf-8")), e.code

    def test_stattrak_ak47_prioritizes_digit_texture(self):
        ak47_path = self.root / "cstrike" / "models" / "custom_skins" / "ct" / "v_ak47.mdl"
        if not ak47_path.is_file():
            self.skipTest("v_ak47.mdl not found for integration test")

        # Inspect model textures to verify both module and digit exist
        model = MdlModel(ak47_path)
        tex_names = [t.name for t in model.textures]
        self.assertIn("stattrak_module.bmp", tex_names)
        self.assertIn("stattrak_digit.bmp", tex_names)

        # Call /api/stattrak_apply without specifying texture_index
        res = self._api_post(
            "/api/stattrak_apply",
            {
                "team": "ct",
                "weapon": "ak47",
                "color": "violet",
                "number": "8971",
            },
        )
        self.assertTrue(res["success"])
        # MUST choose stattrak_digit.bmp, NOT stattrak_module.bmp!
        self.assertEqual(res["texture_name"], "stattrak_digit.bmp")
        self.assertTrue(res["preview"].startswith("data:image/png;base64,"))

    def test_stattrak_explicit_texture_index_override(self):
        ak47_path = self.root / "cstrike" / "models" / "custom_skins" / "ct" / "v_ak47.mdl"
        if not ak47_path.is_file():
            self.skipTest("v_ak47.mdl not found for integration test")

        model = MdlModel(ak47_path)
        module_tex = model.find_texture("stattrak_module.bmp")
        self.assertIsNotNone(module_tex)

        res = self._api_post(
            "/api/stattrak_apply",
            {
                "team": "ct",
                "weapon": "ak47",
                "color": "cyan",
                "number": "000042",
                "texture_index": module_tex.index,
            },
        )
        self.assertTrue(res["success"])
        self.assertEqual(res["texture_index"], module_tex.index)
        self.assertEqual(res["texture_name"], "stattrak_module.bmp")

    def test_api_builtin_sticker_delete_and_restore(self):
        # 1. Delete Howling Dawn via API
        del_res = self._api_post(
            "/api/library/stickers/delete",
            {"filename": "howling_dawn.png"},
        )
        self.assertTrue(del_res["success"])

        # 2. Verify deleted in GET /api/library/stickers
        list_res = self._api_get("/api/library/stickers")
        filenames = [s["filename"] for s in list_res["stickers"]]
        self.assertNotIn("howling_dawn.png", filenames)

        # 3. Call restore defaults endpoint
        restore_res = self._api_post("/api/library/stickers/restore_defaults", {})
        self.assertTrue(restore_res["success"])

        # 4. Verify howling_dawn.png restored
        list_after = self._api_get("/api/library/stickers")
        filenames_after = [s["filename"] for s in list_after["stickers"]]
        self.assertIn("howling_dawn.png", filenames_after)

    def test_stattrak_nonexistent_weapon_returns_404(self):
        res, status = self._api_post_with_status(
            "/api/stattrak_apply",
            {"team": "ct", "weapon": "nonexistent_model_xyz", "color": "orange"}
        )
        self.assertEqual(status, 404)
        self.assertFalse(res["success"])

    def test_stattrak_invalid_texture_index_returns_404(self):
        res, status = self._api_post_with_status(
            "/api/stattrak_apply",
            {"team": "ct", "weapon": "ak47", "texture_index": 9999, "color": "orange"}
        )
        self.assertEqual(status, 404)
        self.assertFalse(res["success"])

    def test_sticker_edit_null_filename_returns_400(self):
        res, status = self._api_post_with_status(
            "/api/library/stickers/edit",
            {"filename": None, "name": "New Name"}
        )
        self.assertEqual(status, 400)
        self.assertFalse(res["success"])
        self.assertIn("Filename is required", res["error"])

    def test_sticker_delete_null_filename_returns_400(self):
        res, status = self._api_post_with_status(
            "/api/library/stickers/delete",
            {"filename": None}
        )
        self.assertEqual(status, 400)
        self.assertFalse(res["success"])
        self.assertIn("Filename is required", res["error"])

    def test_wear_apply_nonexistent_weapon_returns_404(self):
        res, status = self._api_post_with_status(
            "/api/wear_apply",
            {"team": "ct", "weapon": "nonexistent_model_xyz", "wear_float": 0.5}
        )
        self.assertEqual(status, 404)
        self.assertFalse(res["success"])


if __name__ == "__main__":
    unittest.main()
