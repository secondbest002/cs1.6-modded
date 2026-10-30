"""
tests/test_modpack_and_modular.py - Tests for:
1. Mod Pack Exporter (modpack_exporter.py)
2. Mod Pack REST API endpoints (GET & POST /api/export_modpack)
3. 3D WebGL Library Assets (Three.js & OrbitControls integrity)
4. Modular JavaScript Files & Architecture
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
import zipfile

from scripts.cs16_studio.modpack_exporter import export_modpack
from scripts.cs16_studio.mdl_core import resolve_model_path
from scripts.cs16_studio.web.server import create_server


def get_free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("", 0))
        return s.getsockname()[1]


class TestModpackAndModular(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.temp_dir = tempfile.mkdtemp()
        cls.root = Path(cls.temp_dir)

        # Setup mock cstrike directory structure
        cls.custom_ct_dir = cls.root / "cstrike" / "models" / "custom_skins" / "ct"
        cls.custom_t_dir = cls.root / "cstrike" / "models" / "custom_skins" / "t"
        cls.custom_ct_dir.mkdir(parents=True, exist_ok=True)
        cls.custom_t_dir.mkdir(parents=True, exist_ok=True)

        # Copy real models for tests
        real_usp = resolve_model_path("usp", team="ct")
        real_ak = resolve_model_path("ak47", team="ct")
        cls.test_usp = cls.custom_ct_dir / "v_usp.mdl"
        cls.test_ak = cls.custom_ct_dir / "v_ak47.mdl"
        shutil.copy2(real_usp, cls.test_usp)
        shutil.copy2(real_ak, cls.test_ak)

        # Create an .orig.mdl backup for USP to test modified_only filter
        shutil.copy2(real_usp, cls.test_usp.with_suffix(".orig.mdl"))

        # Start test server
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

    def test_modpack_exporter_all_and_filtered(self):
        # 1. Export all
        zip_bytes, manifest = export_modpack(self.root, team="ct")
        self.assertGreater(len(zip_bytes), 1000)
        self.assertEqual(manifest["model_count"], 2)

        with zipfile.ZipFile(io.BytesIO(zip_bytes)) as zf:
            namelist = zf.namelist()
            self.assertIn("modpack_manifest.json", namelist)
            self.assertIn("README_MODPACK.txt", namelist)
            # Check manifest contents
            man_data = json.loads(zf.read("modpack_manifest.json").decode("utf-8"))
            self.assertEqual(man_data["model_count"], 2)

        # 2. Filter by weapon
        zip_bytes_usp, manifest_usp = export_modpack(self.root, team="ct", weapons=["usp"])
        self.assertEqual(manifest_usp["model_count"], 1)
        self.assertEqual(manifest_usp["models"][0]["weapon"], "usp")

        # 3. Filter by modified only (only USP has .orig.mdl)
        zip_bytes_mod, manifest_mod = export_modpack(self.root, team="ct", include_only_modified=True)
        self.assertEqual(manifest_mod["model_count"], 1)
        self.assertEqual(manifest_mod["models"][0]["weapon"], "usp")

    def test_api_export_modpack_post(self):
        url = f"http://127.0.0.1:{self.port}/api/export_modpack"
        payload = {
            "team": "ct",
            "weapons": ["usp"],
            "pack_name": "Test_CT_Pack",
        }
        data = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=15) as res:
            res_data = json.loads(res.read().decode("utf-8"))

        self.assertTrue(res_data["success"])
        self.assertEqual(res_data["model_count"], 1)
        self.assertTrue(res_data["zip_base64"].startswith("data:application/zip;base64,"))

        # Decode and verify zip
        b64 = res_data["zip_base64"].split(",", 1)[1]
        decoded = base64.b64decode(b64)
        with zipfile.ZipFile(io.BytesIO(decoded)) as zf:
            self.assertIn("modpack_manifest.json", zf.namelist())
            self.assertIn("README_MODPACK.txt", zf.namelist())

    def test_api_export_modpack_get(self):
        url = f"http://127.0.0.1:{self.port}/api/export_modpack?team=ct&weapon=usp"
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=15) as res:
            self.assertEqual(res.status, 200)
            self.assertEqual(res.headers.get("Content-Type"), "application/zip")
            raw_zip = res.read()

        self.assertGreater(len(raw_zip), 1000)
        with zipfile.ZipFile(io.BytesIO(raw_zip)) as zf:
            self.assertIn("modpack_manifest.json", zf.namelist())

    def test_threejs_and_orbitcontrols_bundle_integrity(self):
        static_dir = Path("scripts/cs16_studio/web/static")
        three_file = static_dir / "three.min.js"
        orbit_file = static_dir / "OrbitControls.js"

        self.assertTrue(three_file.exists())
        self.assertTrue(orbit_file.exists())

        # Verify not truncated: Three.js must be > 500 KB, OrbitControls must be > 25 KB
        self.assertGreater(three_file.stat().st_size, 500_000, "three.min.js is corrupted/truncated")
        self.assertGreater(orbit_file.stat().st_size, 25_000, "OrbitControls.js is corrupted/truncated")

    def test_modular_frontend_structure_exists(self):
        static_dir = Path("scripts/cs16_studio/web/static")
        required_modules = [
            static_dir / "js" / "app.js",
            static_dir / "js" / "core" / "state.js",
            static_dir / "js" / "core" / "api.js",
            static_dir / "js" / "modules" / "slots.js",
            static_dir / "js" / "modules" / "color_studio.js",
            static_dir / "js" / "modules" / "viewer3d.js",
            static_dir / "js" / "modules" / "bake.js",
            static_dir / "js" / "modules" / "library.js",
            static_dir / "js" / "modules" / "profiles.js",
            static_dir / "js" / "modules" / "pro_tools.js",
            static_dir / "js" / "modules" / "qol.js",
        ]

        for mod in required_modules:
            self.assertTrue(mod.exists(), f"Missing modular component: {mod}")
            self.assertGreater(mod.stat().st_size, 100, f"Module empty or corrupted: {mod}")

    def test_modpack_exporter_string_weapon_and_prefix(self):
        # String argument instead of list
        zip_bytes_str, man_str = export_modpack(self.root, team="ct", weapons="usp", pack_name="My Pack / Test: 123")
        self.assertEqual(man_str["model_count"], 1)
        self.assertEqual(man_str["models"][0]["weapon"], "usp")
        self.assertEqual(man_str["pack_name"], "My_Pack___Test__123")

        # Prefix v_ and .mdl suffix in weapon filter list
        zip_bytes_pref, man_pref = export_modpack(self.root, team="ct", weapons=["v_usp.mdl"])
        self.assertEqual(man_pref["model_count"], 1)
        self.assertEqual(man_pref["models"][0]["weapon"], "usp")

    def test_modpack_exporter_empty_matches(self):
        # No matching weapon
        zip_bytes_empty, man_empty = export_modpack(self.root, team="ct", weapons=["nonexistent_gun"])
        self.assertEqual(man_empty["model_count"], 0)
        self.assertEqual(len(man_empty["models"]), 0)

        with zipfile.ZipFile(io.BytesIO(zip_bytes_empty)) as zf:
            self.assertIn("modpack_manifest.json", zf.namelist())
            self.assertIn("README_MODPACK.txt", zf.namelist())

    def test_model_3d_endpoint_geometry(self):
        url = f"http://127.0.0.1:{self.port}/api/model_3d?team=ct&weapon=usp"
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=15) as res:
            self.assertEqual(res.status, 200)
            data = json.loads(res.read().decode("utf-8"))

        self.assertTrue(data["success"])
        self.assertGreater(data["mesh_count"], 0)
        self.assertIn("meshes", data)
        self.assertIn("bounds", data)
        self.assertGreater(len(data["meshes"]), 0)
        # Verify first mesh has positions and UVs
        first_mesh = data["meshes"][0]
        self.assertIn("positions", first_mesh)
        self.assertIn("uvs", first_mesh)
        self.assertGreater(len(first_mesh["positions"]), 0)
        self.assertEqual(len(first_mesh["positions"]) % 3, 0)
        self.assertEqual(len(first_mesh["uvs"]) % 2, 0)

    def test_javascript_syntax_with_node(self):
        import subprocess
        static_dir = Path("scripts/cs16_studio/web/static")
        js_files = list(static_dir.rglob("*.js"))
        self.assertGreater(len(js_files), 10, "Expected at least 10 JS files in static/")

        for js_file in js_files:
            result = subprocess.run(["node", "--check", str(js_file)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, f"Syntax error in {js_file.name}: {result.stderr}")


if __name__ == "__main__":
    unittest.main()
