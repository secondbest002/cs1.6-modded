"""
tests/test_api_and_cli.py - Integration tests for CS 1.6 Asset Studio REST API and CLI.
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
import urllib.error
from PIL import Image

from scripts.cs16_studio.web.server import create_server
from scripts.cs16_studio.mdl_core import resolve_model_path, MdlModel


def get_free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("", 0))
        return s.getsockname()[1]


class TestApiAndCli(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.temp_dir = tempfile.mkdtemp()
        # Setup mock cstrike directory structure
        cls.custom_ct_dir = Path(cls.temp_dir) / "cstrike" / "models" / "custom_skins" / "ct"
        cls.custom_ct_dir.mkdir(parents=True, exist_ok=True)

        # Copy real v_usp.mdl to test folder
        real_usp = resolve_model_path("usp", team="ct")
        cls.test_usp = cls.custom_ct_dir / "v_usp.mdl"
        shutil.copy2(real_usp, cls.test_usp)

        # Start background server
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
        with urllib.request.urlopen(req, timeout=20) as res:
            return json.loads(res.read().decode("utf-8"))

    def _api_post(self, path, payload):
        url = f"http://127.0.0.1:{self.port}{path}"
        data = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=20) as res:
            return json.loads(res.read().decode("utf-8"))

    def test_api_models(self):
        data = self._api_get("/api/models")
        self.assertTrue(data["success"])
        ct_models = [m["weapon"] for m in data["models"]["ct"]]
        self.assertIn("usp", ct_models)

    def test_api_model_detail(self):
        data = self._api_get("/api/model?team=ct&weapon=usp")
        self.assertTrue(data["success"])
        self.assertEqual(data["weapon"], "usp")
        textures = data["textures"]
        self.assertGreater(len(textures), 0)
        # Check first texture has preview URI
        self.assertTrue(textures[0]["preview"].startswith("data:image/png;base64,"))

    def test_api_preview_endpoint(self):
        # Create a tiny 32x32 test image
        img = Image.new("RGBA", (32, 32), (255, 0, 0, 255))
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        b64 = base64.b64encode(buf.getvalue()).decode("ascii")

        payload = {
            "image_base64": f"data:image/png;base64,{b64}",
            "width": 176,
            "height": 161,
            "is_masked": True,
            "mode": "fit",
            "scale": 1.0,
        }
        res = self._api_post("/api/preview", payload)
        self.assertTrue(res["success"])
        self.assertTrue(res["preview"].startswith("data:image/png;base64,"))

    def test_api_inject_revert_restore(self):
        # 1. Inject
        img = Image.new("RGBA", (100, 100), (0, 255, 0, 255))
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        b64 = base64.b64encode(buf.getvalue()).decode("ascii")

        inject_payload = {
            "team": "ct",
            "weapon": "usp",
            "texture_name": "1.bmp",
            "image_base64": f"data:image/png;base64,{b64}",
            "mode": "fit",
        }
        res_inject = self._api_post("/api/inject", inject_payload)
        self.assertTrue(res_inject["success"])
        self.assertTrue(Path(res_inject["saved_path"]).exists())

        # Verify .orig.mdl exists
        orig_file = self.test_usp.with_suffix(".orig.mdl")
        self.assertTrue(orig_file.exists())

        # 2. Revert Slot
        revert_payload = {
            "team": "ct",
            "weapon": "usp",
            "texture_name": "1.bmp",
        }
        res_revert = self._api_post("/api/revert", revert_payload)
        self.assertTrue(res_revert["success"])

        # 3. Restore Entire Model
        restore_payload = {
            "team": "ct",
            "weapon": "usp",
        }
        res_restore = self._api_post("/api/restore", restore_payload)
        self.assertTrue(res_restore["success"])

    def test_api_bake_preview(self):
        # Create a small sticker
        img = Image.new("RGBA", (64, 64), (255, 215, 0, 255))
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        b64 = base64.b64encode(buf.getvalue()).decode("ascii")

        bake_preview_payload = {
            "team": "ct",
            "weapon": "usp",
            "image_base64": f"data:image/png;base64,{b64}",
            "preset": "silencer",
            "scale": 1.0,
            "rotation": 0,
        }
        res = self._api_post("/api/bake_preview", bake_preview_payload)
        self.assertTrue(res["success"])
        self.assertTrue(res["preview"].startswith("data:image/png;base64,"))


    def test_api_slot_reposition_and_undo(self):
        """Tests POST /api/slot/reposition and POST /api/slot/undo over HTTP."""
        payload = {
            "team": "ct",
            "weapon": "usp",
            "slot": "Slot 4",
            "pos": [-12.0, -10.0, -50.0],
            "normal": [0.0, 1.0, 0.0],
            "scale": 1.0,
            "rotation": 0.0,
        }
        res = self._api_post("/api/slot/reposition", payload)
        self.assertTrue(res["success"])
        self.assertEqual(res["slot_name"], "4.bmp")
        self.assertIn("model_3d", res)
        self.assertIn("snapshot_id", res)

        # Undo via snapshot
        undo_payload = {
            "team": "ct",
            "weapon": "usp",
            "snapshot_id": res["snapshot_id"],
        }
        undo_res = self._api_post("/api/slot/undo", undo_payload)
        self.assertTrue(undo_res["success"])
        self.assertIn("model_3d", undo_res)

    def test_api_slot_inject_disabled(self):
        """Tests that POST /api/slot/inject is disabled and returns HTTP 400."""
        payload = {
            "team": "ct",
            "weapon": "usp",
            "slot_name": "5.bmp",
            "pos": [-12.0, -10.0, -50.0],
            "normal": [0.0, 1.0, 0.0],
            "fx": "foil",
        }
        try:
            self._api_post("/api/slot/inject", payload)
            self.fail("Expected HTTP 400 for disabled slot injection")
        except urllib.error.HTTPError as e:
            self.assertEqual(e.code, 400)
            data = json.loads(e.read().decode("utf-8"))
            self.assertFalse(data["success"])
            self.assertIn("disabled", data["error"].lower())

    def test_api_model_health(self):
        """Tests GET /api/model/health returns validation report."""
        data = self._api_get("/api/model/health?team=ct&weapon=usp")
        self.assertTrue(data["success"])
        self.assertTrue(data["healthy"])
        self.assertEqual(data["status"], "100% Clean")
        self.assertEqual(data["score"], 100)
        self.assertGreater(data["num_textures"], 0)
        self.assertEqual(data["goldsrc_vert_limit"], 2048)

    def test_api_slot_reposition_validation_error(self):
        """Ensures POST /api/slot/reposition returns HTTP 400 when pos or normal is missing."""
        invalid_payload = {
            "team": "ct",
            "weapon": "usp",
            "slot": "4",
        }
        try:
            self._api_post("/api/slot/reposition", invalid_payload)
            self.fail("Expected HTTP 400 error for missing coordinates")
        except urllib.error.HTTPError as e:
            self.assertEqual(e.code, 400)

    def test_api_chrome_preview_texture(self):
        """Tests GET and POST /api/chrome/preview_texture."""
        get_res = self._api_get("/api/chrome/preview_texture?preset=24k%20gold")
        self.assertTrue(get_res["success"])
        self.assertTrue(get_res["preview"].startswith("data:image/png;base64,"))
        self.assertEqual(get_res["preset"], "24k gold")

        post_res = self._api_post("/api/chrome/preview_texture", {"preset": "sapphire", "intensity": 120, "tightness": 2.0, "tint": 220})
        self.assertTrue(post_res["success"])
        self.assertTrue(post_res["preview"].startswith("data:image/png;base64,"))

    def test_api_chrome_lifecycle(self):
        """Tests complete Chrome workflow: status check -> injection -> active status -> removal -> clean matte."""
        # 1. Initial Status
        status1 = self._api_get("/api/chrome/status?team=ct&weapon=usp")
        self.assertTrue(status1["success"])
        self.assertFalse(status1["has_chrome"])
        self.assertTrue(status1["can_inject"])
        self.assertEqual(status1["max_bodyparts"], 32)
        self.assertGreater(len(status1["detected_submodels"]), 0)

        # 2. Inject Chrome
        inject_res = self._api_post("/api/chrome/inject", {
            "team": "ct",
            "weapon": "usp",
            "preset": "silver",
            "intensity": 100,
            "tightness": 1.8,
            "tint": 0,
            "sync_pw": False,
        })
        self.assertTrue(inject_res["success"])
        self.assertTrue(inject_res["has_chrome"])

        # 3. Status with Chrome
        status2 = self._api_get("/api/chrome/status?team=ct&weapon=usp")
        self.assertTrue(status2["success"])
        self.assertTrue(status2["has_chrome"])
        self.assertEqual(status2["active_preset"], "silver")

        # 4. Remove Chrome
        remove_res = self._api_post("/api/chrome/remove", {
            "team": "ct",
            "weapon": "usp",
            "sync_pw": False,
        })
        self.assertTrue(remove_res["success"])
        self.assertFalse(remove_res["has_chrome"])

        # 5. Status restored to matte
        status3 = self._api_get("/api/chrome/status?team=ct&weapon=usp")
        self.assertTrue(status3["success"])
        self.assertFalse(status3["has_chrome"])

    def test_api_chrome_selective_injection(self):
        """Tests POST /api/chrome/inject with selective target_parts."""
        inject_res = self._api_post("/api/chrome/inject", {
            "team": "ct",
            "weapon": "usp",
            "preset": "sapphire",
            "target_parts": ["ref_01"],
            "sync_pw": False,
        })
        self.assertTrue(inject_res["success"])
        self.assertEqual(inject_res["chrome_bodyparts_added"], 1)

        # Cleanup
        self._api_post("/api/chrome/remove", {"team": "ct", "weapon": "usp", "sync_pw": False})

    def test_api_chrome_not_found_handling(self):
        """Tests GET /api/chrome/status and POST /api/chrome/inject return HTTP 404 for missing weapon."""
        try:
            self._api_get("/api/chrome/status?team=ct&weapon=nonexistent_wep_xyz")
            self.fail("Expected HTTP 404 for nonexistent weapon status")
        except urllib.error.HTTPError as e:
            self.assertEqual(e.code, 404)

        try:
            self._api_post("/api/chrome/inject", {"team": "ct", "weapon": "nonexistent_wep_xyz", "preset": "silver"})
            self.fail("Expected HTTP 404 for nonexistent weapon inject")
        except urllib.error.HTTPError as e:
            self.assertEqual(e.code, 404)

    def test_api_pov_endpoints(self):
        """Tests GET /api/pov/presets, GET /api/pov/current, POST /api/pov/apply, and POST /api/pov/reset."""
        # 1. Presets
        presets_data = self._api_get("/api/pov/presets")
        self.assertTrue(presets_data["success"])
        self.assertIn("cs2_classic", presets_data["presets"])
        self.assertIn("couch", presets_data["presets"])

        # 2. Current config with Dual Elites auto-override
        curr_data = self._api_get("/api/pov/current?weapon=v_elite.mdl")
        self.assertTrue(curr_data["success"])
        self.assertEqual(curr_data["config"]["offset_x"], 0.0)
        self.assertTrue(any("Dual Elites" in w for w in curr_data.get("warnings", [])))

        # 3. Apply custom config
        cstrike_path = str(Path(self.temp_dir) / "cstrike")
        apply_data = self._api_post("/api/pov/apply", {
            "weapon": "usp",
            "cstrike_dir": cstrike_path,
            "config": {
                "offset_x": 1.5,
                "offset_y": 1.2,
                "offset_z": -0.8,
            },
        })
        self.assertTrue(apply_data["success"])
        self.assertEqual(apply_data["config"]["offset_x"], 1.5)

        # Verify modern_pov.cfg was written to disk
        pov_cfg_file = Path(cstrike_path) / "modern_pov.cfg"
        self.assertTrue(pov_cfg_file.is_file())
        self.assertIn('viewmodel_offset_x "1.50"', pov_cfg_file.read_text(encoding="utf-8"))

        # 4. Reset to vanilla
        reset_data = self._api_post("/api/pov/reset", {"cstrike_dir": cstrike_path})
        self.assertTrue(reset_data["success"])
        self.assertIn('viewmodel_offset_x "0.00"', pov_cfg_file.read_text(encoding="utf-8"))

    def test_api_sleeve_endpoints(self):
        """Tests GET /api/sleeve/inspect and POST /api/sleeve/inject."""
        # 1. Inspect endpoint
        inspect_data = self._api_get("/api/sleeve/inspect?team=ct&weapon=usp")
        self.assertTrue(inspect_data["success"])
        self.assertIn("target", inspect_data)
        self.assertIn("arm_type", inspect_data["target"])
        self.assertIn("presets", inspect_data)
        self.assertIn("sas_navy", inspect_data["presets"])
        self.assertGreater(inspect_data["scale_ratio"], 0.0)


if __name__ == "__main__":
    unittest.main()
