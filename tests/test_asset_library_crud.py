"""
tests/test_asset_library_crud.py - Unit and Integration tests for Asset Library CRUD
and Custom Sticker management.
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
import urllib.request
import urllib.parse
from PIL import Image

from scripts.cs16_studio.asset_library import (
    delete_custom_sticker,
    edit_custom_sticker,
    ensure_builtin_assets,
    get_library_stickers,
    save_custom_sticker,
)
from scripts.cs16_studio.profile_manager import list_profiles, save_profile
from scripts.cs16_studio.web.server import create_server


def get_free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("", 0))
        return s.getsockname()[1]


class TestAssetLibraryCrud(unittest.TestCase):

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
        self.root = Path(self.temp_dir)
        ensure_builtin_assets(self.root)

    def tearDown(self):
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def _create_test_image_bytes(self, color=(255, 0, 0, 255), size=(64, 64)):
        img = Image.new("RGBA", size, color)
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        return buf.getvalue()

    def test_save_custom_sticker(self):
        raw_bytes = self._create_test_image_bytes()
        res = save_custom_sticker(
            name="My Test Foil",
            image_bytes=raw_bytes,
            category="Custom / User",
            workspace_root=self.root,
        )
        self.assertTrue(res["success"])
        self.assertEqual(res["name"], "My Test Foil")
        self.assertTrue(res["is_custom"])
        self.assertTrue(res["thumbnail"].startswith("data:image/png;base64,"))
        self.assertTrue(res["preview"].startswith("data:image/png;base64,"))

        # Check file exists on disk
        saved_file = self.root / res["path"]
        self.assertTrue(saved_file.is_file())

        # Check library listing
        stickers = get_library_stickers(self.root)
        custom_items = [s for s in stickers if s.get("is_custom")]
        self.assertEqual(len(custom_items), 1)
        self.assertEqual(custom_items[0]["name"], "My Test Foil")
        self.assertEqual(custom_items[0]["preview"], res["preview"])

    def test_auto_alpha_black_removal(self):
        # Create 64x64 image with black background and red circle in center
        img = Image.new("RGBA", (64, 64), (0, 0, 0, 255))
        for x in range(24, 40):
            for y in range(24, 40):
                img.putpixel((x, y), (255, 0, 0, 255))
        buf = io.BytesIO()
        img.save(buf, format="PNG")

        res = save_custom_sticker(
            name="Black Cutout",
            image_bytes=buf.getvalue(),
            auto_alpha=True,
            workspace_root=self.root,
        )
        self.assertTrue(res["success"])

        saved_file = self.root / res["path"]
        with Image.open(saved_file) as processed:
            # Corner should now be transparent
            corner_alpha = processed.getpixel((0, 0))[3]
            self.assertEqual(corner_alpha, 0)
            # Center red should remain opaque
            center_pixel = processed.getpixel((32, 32))
            self.assertEqual(center_pixel[0], 255)
            self.assertEqual(center_pixel[3], 255)

    def test_edit_custom_sticker(self):
        raw_bytes = self._create_test_image_bytes()
        saved = save_custom_sticker(
            name="Original Sticker",
            image_bytes=raw_bytes,
            category="User",
            workspace_root=self.root,
        )

        res = edit_custom_sticker(
            filename=saved["filename"],
            new_name="Renamed Golden Sticker",
            new_category="Championship Holo",
            workspace_root=self.root,
        )
        self.assertTrue(res["success"])
        self.assertEqual(res["name"], "Renamed Golden Sticker")
        self.assertEqual(res["category"], "Championship Holo")

        # Verify reflected in get_library_stickers
        stickers = get_library_stickers(self.root)
        match = [s for s in stickers if s["filename"] == saved["filename"]][0]
        self.assertEqual(match["name"], "Renamed Golden Sticker")
        self.assertEqual(match["category"], "Championship Holo")

    def test_delete_custom_sticker(self):
        raw_bytes = self._create_test_image_bytes()
        saved = save_custom_sticker(
            name="To Delete",
            image_bytes=raw_bytes,
            workspace_root=self.root,
        )
        self.assertTrue((self.root / saved["path"]).is_file())

        res = delete_custom_sticker(saved["filename"], workspace_root=self.root)
        self.assertTrue(res["success"])
        self.assertFalse((self.root / saved["path"]).exists())

    def test_protect_builtin_stickers(self):
        # Attempting to delete titan_holo.png must fail
        with self.assertRaises(ValueError):
            delete_custom_sticker("titan_holo.png", workspace_root=self.root)

    def test_auto_alpha_preserves_black_on_transparent_input(self):
        # Image that already has transparent corners and black center details
        img = Image.new("RGBA", (64, 64), (0, 0, 0, 0))
        for x in range(20, 44):
            for y in range(20, 44):
                img.putpixel((x, y), (10, 10, 10, 255))
        buf = io.BytesIO()
        img.save(buf, format="PNG")

        res = save_custom_sticker(
            name="Transparent With Black Center",
            image_bytes=buf.getvalue(),
            auto_alpha=True,
            workspace_root=self.root,
        )
        self.assertTrue(res["success"])
        saved_file = self.root / res["path"]
        with Image.open(saved_file) as processed:
            # Corner remains transparent
            self.assertEqual(processed.getpixel((0, 0))[3], 0)
            # Center black details MUST NOT be erased to 0
            self.assertEqual(processed.getpixel((32, 32))[3], 255)
            self.assertEqual(processed.getpixel((32, 32))[0], 10)

    def test_builtin_name_collision_indexing_and_visibility(self):
        # Upload sticker with identical name as built-in Katowice sticker
        raw_bytes = self._create_test_image_bytes(color=(0, 255, 0, 255))
        res = save_custom_sticker(
            name="Titan Holo",
            image_bytes=raw_bytes,
            workspace_root=self.root,
        )
        self.assertTrue(res["success"])
        # Should be indexed to titan_holo_1.png to prevent overwriting or collision
        self.assertEqual(res["filename"], "titan_holo_1.png")

        # In get_library_stickers, BOTH built-in and user custom sticker must be returned
        all_stickers = get_library_stickers(self.root)
        filenames = [s["filename"] for s in all_stickers]
        self.assertIn("titan_holo.png", filenames, "Built-in titan_holo.png must remain in library")
        self.assertIn("titan_holo_1.png", filenames, "Custom titan_holo_1.png must appear in library")

        custom_titan = [s for s in all_stickers if s["filename"] == "titan_holo_1.png"][0]
        self.assertTrue(custom_titan["is_custom"])

    def test_upload_webp_and_jpeg_conversion(self):
        # Test WEBP upload converted to PNG
        img = Image.new("RGBA", (32, 32), (50, 150, 250, 255))
        webp_buf = io.BytesIO()
        img.save(webp_buf, format="WEBP")

        res = save_custom_sticker(
            name="Webp Test",
            image_bytes=webp_buf.getvalue(),
            workspace_root=self.root,
        )
        self.assertTrue(res["success"])
        self.assertTrue(res["filename"].endswith(".png"))
        self.assertTrue((self.root / res["path"]).is_file())



class TestAssetLibraryApiEndpoints(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.temp_dir = tempfile.mkdtemp()
        cls.root = Path(cls.temp_dir)
        ensure_builtin_assets(cls.root)

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
        with urllib.request.urlopen(req, timeout=10) as res:
            return json.loads(res.read().decode("utf-8"))

    def _api_post(self, path, payload):
        url = f"http://127.0.0.1:{self.port}{path}"
        data = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=10) as res:
            return json.loads(res.read().decode("utf-8"))

    def test_api_upload_edit_delete_lifecycle(self):
        # 1. Upload sticker via base64
        img = Image.new("RGBA", (32, 32), (0, 200, 255, 255))
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        b64 = base64.b64encode(buf.getvalue()).decode("ascii")

        upload_res = self._api_post(
            "/api/library/stickers/upload",
            {
                "name": "API Sticker Test",
                "category": "API Tested",
                "image_base64": f"data:image/png;base64,{b64}",
                "auto_alpha": False,
            },
        )
        self.assertTrue(upload_res["success"])
        filename = upload_res["filename"]
        self.assertIn("API Sticker Test", upload_res["name"])
        self.assertTrue(upload_res["preview"].startswith("data:image/png;base64,"))

        # 2. Check it appears in /api/library/stickers
        stickers_res = self._api_get("/api/library/stickers")
        self.assertTrue(stickers_res["success"])
        found = [s for s in stickers_res["stickers"] if s["filename"] == filename]
        self.assertEqual(len(found), 1)
        self.assertEqual(found[0]["name"], "API Sticker Test")
        self.assertTrue(found[0]["is_custom"])
        self.assertTrue(found[0]["thumbnail"].startswith("data:image/png;base64,"))
        self.assertTrue(found[0]["preview"].startswith("data:image/png;base64,"))

        # 3. Edit sticker
        edit_res = self._api_post(
            "/api/library/stickers/edit",
            {
                "filename": filename,
                "name": "API Sticker Updated",
                "category": "Updated Category",
            },
        )
        self.assertTrue(edit_res["success"])
        self.assertEqual(edit_res["name"], "API Sticker Updated")

        # 4. Delete sticker
        del_res = self._api_post(
            "/api/library/stickers/delete",
            {
                "filename": filename,
            },
        )
        self.assertTrue(del_res["success"])

        # 5. Verify deleted from list
        stickers_after = self._api_get("/api/library/stickers")
        found_after = [s for s in stickers_after["stickers"] if s["filename"] == filename]
        self.assertEqual(len(found_after), 0)

    def test_api_profile_delete(self):
        # Create a mock profile file in .studio_profiles
        profiles_dir = self.root / ".studio_profiles"
        profiles_dir.mkdir(parents=True, exist_ok=True)
        prof_file = profiles_dir / "test_prof_del.json"
        with open(prof_file, "w", encoding="utf-8") as f:
            json.dump({"name": "test_prof_del", "weapons": {}}, f)

        self.assertTrue(prof_file.is_file())

        res = self._api_post(
            "/api/profiles/delete",
            {"name": "test_prof_del"},
        )
        self.assertTrue(res["success"])
        self.assertFalse(prof_file.exists())
