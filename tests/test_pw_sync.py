"""
tests/test_pw_sync.py - Unit and Integration Tests for P/W Model Synchronization & Injection.
"""

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

from scripts.cs16_studio.amxx_manager import sync_pw_models
from scripts.cs16_studio.web.server import create_server
from scripts.cs16_studio.mdl_core import resolve_model_path, MdlModel


def get_free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("", 0))
        return s.getsockname()[1]


class TestPwSync(unittest.TestCase):

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
        self.root = Path(self.temp_dir)

        # Setup mock cstrike folders
        self.custom_ct_dir = self.root / "cstrike" / "models" / "custom_skins" / "ct"
        self.custom_ct_dir.mkdir(parents=True, exist_ok=True)

        self.pw_dir = self.root / "cstrike" / "models" / "pw_models"
        self.pw_dir.mkdir(parents=True, exist_ok=True)

        # Copy real v_usp.mdl, p_usp.mdl, and w_usp.mdl
        real_v = resolve_model_path("usp", team="ct")
        shutil.copy2(real_v, self.custom_ct_dir / "v_usp.mdl")

        real_p = Path("cstrike/models/pw_models/p_usp.mdl").resolve()
        if real_p.is_file():
            shutil.copy2(real_p, self.pw_dir / "p_usp.mdl")

        real_w = Path("cstrike/models/pw_models/w_usp.mdl").resolve()
        if real_w.is_file():
            shutil.copy2(real_w, self.pw_dir / "w_usp.mdl")

    def tearDown(self):
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_sync_pw_models_direct(self):
        res = sync_pw_models(
            root_dir=self.root,
            weapon="usp",
            team="ct",
            auto_backup=True,
        )
        self.assertTrue(res["success"])
        self.assertTrue(res["p_injected"])
        self.assertTrue(res["w_injected"])

        # Check backup created
        p_bak = self.pw_dir / "p_usp.mdl.bak"
        w_bak = self.pw_dir / "w_usp.mdl.bak"
        self.assertTrue(p_bak.is_file())
        self.assertTrue(w_bak.is_file())

        # Validate that injected models are still valid IDST v10 GoldSrc models
        p_model = MdlModel(self.pw_dir / "p_usp.mdl")
        self.assertGreater(len(p_model.textures), 0)
        w_model = MdlModel(self.pw_dir / "w_usp.mdl")
        self.assertGreater(len(w_model.textures), 0)

    def test_sync_pw_models_relative_paths(self):
        # Verify that relative paths without 'cstrike/' prefix resolve properly
        res = sync_pw_models(
            root_dir=self.root,
            weapon="usp",
            team="ct",
            auto_backup=True,
            v_model_path="models/custom_skins/ct/v_usp.mdl",
            p_model_path="models/pw_models/p_usp.mdl",
            w_model_path="models/pw_models/w_usp.mdl",
        )
        self.assertTrue(res["success"])
        self.assertTrue(res["p_injected"])
        self.assertTrue(res["w_injected"])

    def test_sync_pw_models_no_backup(self):
        # Remove any existing .bak
        for bak in self.pw_dir.glob("*.bak"):
            bak.unlink()

        res = sync_pw_models(
            root_dir=self.root,
            weapon="usp",
            team="ct",
            auto_backup=False,
        )
        self.assertTrue(res["success"])
        self.assertFalse((self.pw_dir / "p_usp.mdl.bak").exists())


class TestPwSyncEndpoint(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.temp_dir = tempfile.mkdtemp()
        cls.root = Path(cls.temp_dir)

        # Setup mock directories
        cls.custom_ct_dir = cls.root / "cstrike" / "models" / "custom_skins" / "ct"
        cls.custom_ct_dir.mkdir(parents=True, exist_ok=True)
        cls.pw_dir = cls.root / "cstrike" / "models" / "pw_models"
        cls.pw_dir.mkdir(parents=True, exist_ok=True)

        real_v = resolve_model_path("usp", team="ct")
        shutil.copy2(real_v, cls.custom_ct_dir / "v_usp.mdl")

        real_p = Path("cstrike/models/pw_models/p_usp.mdl").resolve()
        if real_p.is_file():
            shutil.copy2(real_p, cls.pw_dir / "p_usp.mdl")

        real_w = Path("cstrike/models/pw_models/w_usp.mdl").resolve()
        if real_w.is_file():
            shutil.copy2(real_w, cls.pw_dir / "w_usp.mdl")

        # Start server
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

    def test_api_sync_pw(self):
        url = f"http://127.0.0.1:{self.port}/api/amxx/sync_pw"
        payload = json.dumps({
            "weapon": "usp",
            "team": "ct",
            "auto_backup": True,
        }).encode()
        req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read().decode())
            self.assertTrue(data["success"])
            self.assertTrue(data["p_injected"])
            self.assertTrue(data["w_injected"])
            self.assertIn("successfully synced", data["message"].lower())


if __name__ == "__main__":
    unittest.main()
