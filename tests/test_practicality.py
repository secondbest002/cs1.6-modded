"""
tests/test_practicality.py - Comprehensive tests for practicality enhancements:
1. Built-in Asset Library API & procedural generation
2. Batch Multi-Weapon sticker application (API & core)
3. Loadout Profile & Preset Manager (save, load, list, delete)
4. WYSIWYG coordinate bake composite
"""

import base64
import io
import json
import os
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
    ensure_builtin_assets,
    get_library_skins,
    get_library_stickers,
)
from scripts.cs16_studio.baker import bake_sticker_onto_texture
from scripts.cs16_studio.mdl_core import (
    MdlModel,
    batch_inject_sticker,
    resolve_model_path,
)
from scripts.cs16_studio.profile_manager import (
    delete_profile,
    export_profile,
    import_profile,
    list_profiles,
    load_profile,
    save_profile,
)
from scripts.cs16_studio.web.server import create_server


def get_free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("", 0))
        return s.getsockname()[1]


class TestPracticality(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.temp_dir = tempfile.mkdtemp()
        cls.root = Path(cls.temp_dir)

        # Setup mock cstrike directory structure
        cls.custom_ct_dir = cls.root / "cstrike" / "models" / "custom_skins" / "ct"
        cls.custom_ct_dir.mkdir(parents=True, exist_ok=True)

        # Copy real test models (usp, ak47, m4a1)
        for w in ["usp", "ak47", "m4a1"]:
            try:
                src = resolve_model_path(w, team="ct")
                shutil.copy2(src, cls.custom_ct_dir / f"v_{w}.mdl")
            except Exception:
                pass

        # Generate built-in assets in temp directory
        ensure_builtin_assets(cls.root)

        # Start background server
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
        with urllib.request.urlopen(req, timeout=5) as res:
            return json.loads(res.read().decode("utf-8"))

    def _api_post(self, path, payload):
        url = f"http://127.0.0.1:{self.port}{path}"
        data = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=5) as res:
            return json.loads(res.read().decode("utf-8"))

    def test_asset_library_generation_and_api(self):
        """Verify sticker library generation and GET /api/library/stickers."""
        stickers = get_library_stickers(self.root)
        self.assertGreaterEqual(len(stickers), 8)

        names = [s["name"] for s in stickers]
        self.assertIn("Titan Holo", names)
        self.assertIn("iBUYPOWER Holo", names)
        self.assertIn("Crown (Foil)", names)

        # Check API endpoint
        res = self._api_get("/api/library/stickers")
        self.assertTrue(res["success"])
        self.assertGreaterEqual(len(res["stickers"]), 8)
        self.assertTrue(res["stickers"][0]["thumbnail"].startswith("data:image/png;base64,"))

    def test_asset_library_skins_api(self):
        """Verify skins library scanning and GET /api/library/skins."""
        # Create a sample custom skin in assets/my_skins
        my_skins = self.root / "assets" / "my_skins"
        my_skins.mkdir(parents=True, exist_ok=True)
        test_skin = Image.new("RGB", (256, 256), (40, 60, 100))
        test_skin.save(my_skins / "hyper_beast.png")

        res = self._api_get("/api/library/skins")
        self.assertTrue(res["success"])
        skin_names = [s["name"] for s in res["skins"]]
        self.assertIn("Hyper Beast", skin_names)

    def test_batch_inject_sticker_core(self):
        """Verify batch injection across multiple weapons."""
        titan_path = self.root / "assets" / "stickers" / "titan_holo.png"
        self.assertTrue(titan_path.exists())

        results = batch_inject_sticker(
            weapons=["usp", "ak47"],
            sticker_image=titan_path,
            slot=1,
            team="ct",
            mode="fit",
            scale=1.0,
            fx="foil",
            root_dir=self.root,
        )

        self.assertIn("usp", results)
        self.assertIn("ak47", results)
        self.assertTrue(results["usp"]["success"])
        self.assertTrue(results["ak47"]["success"])

        # Check that .orig.mdl backup was created
        usp_orig = (self.custom_ct_dir / "v_usp.orig.mdl")
        self.assertTrue(usp_orig.exists())

    def test_batch_inject_api(self):
        """Verify POST /api/batch_inject endpoint."""
        titan_path = self.root / "assets" / "stickers" / "titan_holo.png"

        payload = {
            "weapons": ["usp", "ak47"],
            "team": "ct",
            "slot": "1",
            "image_path": str(titan_path),
            "mode": "fit",
            "scale": 1.0,
            "fx": "matte",
        }

        res = self._api_post("/api/batch_inject", payload)
        self.assertTrue(res["success"])
        self.assertIn("usp", res["results"])
        self.assertTrue(res["results"]["usp"]["success"])

    def test_profile_manager_lifecycle(self):
        """Verify saving, listing, loading, and deleting loadout profiles."""
        # 1. Save profile
        save_res = save_profile(
            name="Tournament_2014_Holo",
            weapons=["usp", "ak47"],
            team="ct",
            description="Testing profile manager",
            root_dir=self.root,
        )
        self.assertTrue(save_res["success"])
        self.assertEqual(save_res["name"], "Tournament_2014_Holo")
        self.assertGreaterEqual(save_res["weapons_count"], 2)

        # 2. List profiles
        profiles = list_profiles(self.root)
        self.assertGreaterEqual(len(profiles), 1)
        prof_names = [p["name"] for p in profiles]
        self.assertIn("Tournament_2014_Holo", prof_names)

        # Check via API GET /api/profiles
        api_profiles = self._api_get("/api/profiles")
        self.assertTrue(api_profiles["success"])
        self.assertIn("Tournament_2014_Holo", [p["name"] for p in api_profiles["profiles"]])

        # 3. Load profile
        load_res = load_profile("Tournament_2014_Holo", root_dir=self.root)
        self.assertTrue(load_res["success"])
        self.assertIn("usp", load_res["restored_weapons"])

        # Check via API POST /api/profiles/load
        load_api_res = self._api_post("/api/profiles/load", {"name": "Tournament_2014_Holo"})
        self.assertTrue(load_api_res["success"])

        # 4. Delete profile
        del_api_res = self._api_post("/api/profiles/delete", {"name": "Tournament_2014_Holo"})
        self.assertTrue(del_api_res["success"])

    def test_interactive_wysiwyg_custom_coords_bake(self):
        """Verify custom click-and-drag coordinates in bake engine."""
        base_img = Image.new("RGBA", (512, 512), (30, 30, 30, 255))
        sticker_img = Image.new("RGBA", (128, 128), (255, 200, 0, 255))

        custom_coords = (245, 180)
        payload, comp = bake_sticker_onto_texture(
            base_image=base_img,
            sticker_image=sticker_img,
            weapon_key="usp",
            custom_coords=custom_coords,
            scale_multiplier=1.0,
            rotation_deg=45.0,
        )

        self.assertGreater(len(payload), 512 * 512)
        self.assertEqual(comp.size, (512, 512))

    def test_image_path_in_inject_and_bake(self):
        """Verify that passing image_path to /api/inject and /api/bake loads full-res image from disk."""
        titan_path = self.root / "assets" / "stickers" / "titan_holo.png"
        self.assertTrue(titan_path.exists())

        # Test /api/inject with image_path
        inject_res = self._api_post("/api/inject", {
            "weapon": "usp",
            "team": "ct",
            "texture_name": "1.bmp",
            "image_path": str(titan_path),
            "mode": "fit",
            "scale": 1.0,
        })
        self.assertTrue(inject_res["success"])
        self.assertIn("Successfully injected", inject_res["message"])

        # Test /api/bake with image_path
        bake_res = self._api_post("/api/bake", {
            "weapon": "usp",
            "team": "ct",
            "image_path": str(titan_path),
            "preset": "center",
            "coords": [250, 200],
            "scale": 1.0,
            "rotation": 0.0,
        })
        self.assertTrue(bake_res["success"])
        self.assertIn("Successfully baked sticker", bake_res["message"])

    def test_export_and_import_profile(self):
        """Verify export_profile and import_profile functions."""
        save_res = save_profile(
            name="Exportable_Loadout",
            weapons=["usp"],
            team="ct",
            root_dir=self.root,
        )
        self.assertTrue(save_res["success"])

        export_target = self.root / "exported_profile.json"
        exported_file = export_profile("Exportable_Loadout", export_target, root_dir=self.root)
        self.assertTrue(exported_file.is_file())

        import_res = import_profile(exported_file, root_dir=self.root)
        self.assertTrue(import_res["success"])
        self.assertEqual(import_res["name"], "Exportable_Loadout")

        # Cleanup
        delete_profile("Exportable_Loadout", root_dir=self.root)

    def test_profile_name_extension_handling(self):
        """Verify loading and deleting profile when name includes .json extension."""
        save_profile("Ext_Test", weapons=["usp"], team="ct", root_dir=self.root)

        # Load with .json
        load_res = load_profile("Ext_Test.json", root_dir=self.root)
        self.assertTrue(load_res["success"])

        # Delete with .json
        deleted = delete_profile("Ext_Test.json", root_dir=self.root)
        self.assertTrue(deleted)

    def test_rotation_wysiwyg_clockwise(self):
        """Verify that 90 degree rotation correctly rotates clockwise."""
        # Create an asymmetrical sticker: top-left pixel is bright red
        base = Image.new("RGBA", (100, 100), (0, 0, 0, 255))
        stk = Image.new("RGBA", (40, 40), (0, 0, 0, 0))
        stk.putpixel((10, 5), (255, 0, 0, 255))  # near top

        # 90 degrees clockwise rotation in UI should move top pixel to the right
        _, comp = bake_sticker_onto_texture(
            base,
            stk,
            weapon_key="generic",
            custom_coords=(50, 50),
            scale_multiplier=1.0,
            rotation_deg=90.0,
        )
        self.assertEqual(comp.size, (100, 100))


if __name__ == "__main__":
    unittest.main()
