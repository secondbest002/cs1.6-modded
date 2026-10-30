"""
tests/test_amxx_integration.py - Unit and Integration Tests for CS:GO AMXX Catalog & Active Loadout.
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

from scripts.cs16_studio.amxx_manager import (
    parse_skin_inventory,
    parse_active_loadout,
    set_active_loadout,
    find_weapon_audio,
    get_amxx_catalog,
)
from scripts.cs16_studio.web.server import create_server
from scripts.cs16_studio.mdl_core import resolve_model_path


def get_free_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("", 0))
        return s.getsockname()[1]


class TestAmxxIntegration(unittest.TestCase):

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
        self.root = Path(self.temp_dir)

        # Setup mock directories
        self.configs_dir = self.root / "cstrike" / "addons" / "amxmodx" / "configs"
        self.configs_dir.mkdir(parents=True, exist_ok=True)

        self.custom_ct_dir = self.root / "cstrike" / "models" / "custom_skins" / "ct"
        self.custom_ct_dir.mkdir(parents=True, exist_ok=True)

        self.custom_t_dir = self.root / "cstrike" / "models" / "custom_skins" / "t"
        self.custom_t_dir.mkdir(parents=True, exist_ok=True)

        self.sounds_dir = self.root / "cstrike" / "sound" / "weapons" / "csgo" / "m4a4"
        self.sounds_dir.mkdir(parents=True, exist_ok=True)

        # Mock sound file
        self.mock_sound = self.sounds_dir / "m4a4-1.wav"
        self.mock_sound.write_bytes(b"RIFF\x24\x00\x00\x00WAVEfmt \x10\x00\x00\x00\x01\x00\x01\x00\x44\xac\x00\x00data\x00\x00\x00\x00")

        # Mock skin_inventory.ini
        self.inventory_file = self.configs_dir / "skin_inventory.ini"
        self.inventory_content = """
; Mock Skin Inventory
[CT_KNIVES]
"M9 Bayonet" "models/custom_skins/ct/v_knife_m9.mdl" "models/pw_models/p_knife.mdl" "models/pw_models/w_knife.mdl"
"Default CT Knife" "models/custom_skins/t/v_knife.mdl" "models/pw_models/p_knife.mdl" "models/pw_models/w_knife.mdl"

[CT_M4A1]
"M4A1-S | Printstream" "models/custom_skins/ct/v_m4a1.mdl" "models/pw_models/p_m4a1.mdl" "models/pw_models/w_m4a1.mdl"
"M4A4 (Custom)" "models/custom_skins/ct/v_m4a4.mdl" "models/pw_models/p_m4a4.mdl" "models/pw_models/w_m4a4.mdl" "weapons/csgo/m4a4/m4a4-1.wav"

[T_KNIVES]
"Butterfly Knife" "models/custom_skins/t/v_knife_butterfly.mdl" "models/pw_models/p_knife.mdl" "models/pw_models/w_knife.mdl"
"""
        self.inventory_file.write_text(self.inventory_content, encoding="utf-8")

        # Mock active_loadout.ini
        self.loadout_file = self.configs_dir / "active_loadout.ini"
        self.loadout_content = """
[CT_ACTIVE]
KNIFE    = "models/custom_skins/ct/v_knife_m9.mdl"
M4A1     = "models/custom_skins/ct/v_m4a1.mdl"
USP      = "models/custom_skins/ct/v_usp.mdl"

[T_ACTIVE]
KNIFE    = "models/custom_skins/t/v_knife_butterfly.mdl"
AK47     = "models/custom_skins/t/v_ak47.mdl"
"""
        self.loadout_file.write_text(self.loadout_content, encoding="utf-8")

    def tearDown(self):
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_parse_skin_inventory(self):
        catalog = parse_skin_inventory(self.inventory_file)
        self.assertIn("ct", catalog)
        self.assertIn("t", catalog)
        self.assertIn("KNIFE", catalog["ct"])
        self.assertIn("M4A1", catalog["ct"])

        m4_variants = catalog["ct"]["M4A1"]
        self.assertEqual(len(m4_variants), 2)
        self.assertEqual(m4_variants[0]["display_name"], "M4A1-S | Printstream")
        self.assertEqual(m4_variants[1]["weapon_key"], "m4a4")
        self.assertEqual(m4_variants[1]["sounds"], ["weapons/csgo/m4a4/m4a4-1.wav"])

    def test_parse_active_loadout(self):
        loadout = parse_active_loadout(self.loadout_file)
        self.assertEqual(loadout["ct"]["KNIFE"], "models/custom_skins/ct/v_knife_m9.mdl")
        self.assertEqual(loadout["ct"]["M4A1"], "models/custom_skins/ct/v_m4a1.mdl")
        self.assertEqual(loadout["t"]["KNIFE"], "models/custom_skins/t/v_knife_butterfly.mdl")

    def test_set_active_loadout(self):
        # Equip M4A4 for CT
        res = set_active_loadout(
            loadout_path=self.loadout_file,
            team="ct",
            weapon="m4a4",
            model_path="models/custom_skins/ct/v_m4a4.mdl",
        )
        self.assertTrue(res["success"])
        updated = parse_active_loadout(self.loadout_file)
        self.assertEqual(updated["ct"]["M4A1"], "models/custom_skins/ct/v_m4a4.mdl")
        # Ensure knife was preserved
        self.assertEqual(updated["ct"]["KNIFE"], "models/custom_skins/ct/v_knife_m9.mdl")

    def test_find_weapon_audio(self):
        snd = find_weapon_audio(self.root, "m4a4")
        self.assertIsNotNone(snd)
        self.assertTrue(snd.is_file())
        self.assertEqual(snd.name, "m4a4-1.wav")

        snd_direct = find_weapon_audio(self.root, "weapons/csgo/m4a4/m4a4-1.wav")
        self.assertIsNotNone(snd_direct)
        self.assertEqual(snd_direct.name, "m4a4-1.wav")

    def test_get_amxx_catalog(self):
        cat = get_amxx_catalog(self.root)
        self.assertTrue(cat["success"])
        self.assertIn("categories", cat)
        self.assertIn("catalog", cat)
        self.assertIn("ct", cat["catalog"])
        self.assertIn("M4A1", cat["catalog"]["ct"])

        m4_slot = cat["catalog"]["ct"]["M4A1"]
        self.assertEqual(len(m4_slot["variants"]), 2)
        # M4A1 should be active initially
        self.assertTrue(m4_slot["variants"][0]["is_active"])
        self.assertFalse(m4_slot["variants"][1]["is_active"])

    def test_set_active_loadout_canonical_lookup_without_path(self):
        # 1. Equip knife_karambit for CT without model_path: must look up skin_inventory.ini
        # In skin_inventory.ini, Karambit is at models/custom_skins/t/v_knife_karambit.mdl
        inv = self.configs_dir / "skin_inventory.ini"
        inv.write_text("""
[CT_KNIVES]
"M9 Bayonet" "models/custom_skins/ct/v_knife_m9.mdl" "models/pw_models/p_knife.mdl" "models/pw_models/w_knife.mdl"
"Karambit" "models/custom_skins/t/v_knife_karambit.mdl" "models/pw_models/p_knife.mdl" "models/pw_models/w_knife.mdl"

[T_MAC10]
"MAC-10" "models/custom_skins/t/v_mac10.mdl" "models/pw_models/p_mac10.mdl" "models/pw_models/w_mac10.mdl"
"CZ75-Auto" "models/custom_skins/t/v_cz75.mdl" "models/pw_models/p_cz75.mdl" "models/pw_models/w_cz75.mdl"
""", encoding="utf-8")

        res_knife = set_active_loadout(
            loadout_path=self.loadout_file,
            team="ct",
            weapon="knife_karambit",
            root_dir=self.root,
        )
        self.assertTrue(res_knife["success"])
        self.assertEqual(res_knife["slot"], "KNIFE")
        self.assertEqual(res_knife["model_path"], "models/custom_skins/t/v_knife_karambit.mdl")

        updated = parse_active_loadout(self.loadout_file)
        self.assertEqual(updated["ct"]["KNIFE"], "models/custom_skins/t/v_knife_karambit.mdl")

        # 2. Equip CZ75 for T without model_path: must assign to MAC10 slot, NOT TMP slot
        res_cz = set_active_loadout(
            loadout_path=self.loadout_file,
            team="t",
            weapon="cz75",
            root_dir=self.root,
        )
        self.assertTrue(res_cz["success"])
        self.assertEqual(res_cz["slot"], "MAC10")
        self.assertEqual(res_cz["model_path"], "models/custom_skins/t/v_cz75.mdl")

        updated_t = parse_active_loadout(self.loadout_file)
        self.assertEqual(updated_t["t"]["MAC10"], "models/custom_skins/t/v_cz75.mdl")

    def test_set_active_loadout_short_section_names(self):
        # Test active_loadout.ini that uses [CT] and [T] instead of [CT_ACTIVE]
        short_file = self.configs_dir / "short_loadout.ini"
        short_file.write_text("[CT]\nKNIFE = \"models/v_knife.mdl\"\n\n[T]\nKNIFE = \"models/v_knife.mdl\"\n", encoding="utf-8")

        res = set_active_loadout(
            loadout_path=short_file,
            team="ct",
            weapon="knife_m9",
            model_path="models/custom_skins/ct/v_knife_m9.mdl",
        )
        self.assertTrue(res["success"])
        content = short_file.read_text(encoding="utf-8")
        # Ensure no duplicate [CT_ACTIVE] was created
        self.assertNotIn("[CT_ACTIVE]", content)
        self.assertIn("models/custom_skins/ct/v_knife_m9.mdl", content)

    def test_find_weapon_audio_prefix_fallback(self):
        cz_dir = self.root / "cstrike" / "sound" / "weapons" / "csgo" / "cz75a"
        cz_dir.mkdir(parents=True, exist_ok=True)
        (cz_dir / "cz75-1.wav").write_bytes(b"RIFF\x24\x00\x00\x00WAVEfmt ")

        snd = find_weapon_audio(self.root, "cz75")
        self.assertIsNotNone(snd)
        self.assertEqual(snd.name, "cz75-1.wav")


class TestAmxxServerEndpoints(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.temp_dir = tempfile.mkdtemp()
        cls.root = Path(cls.temp_dir)

        # Copy real v_usp.mdl
        cls.custom_ct_dir = cls.root / "cstrike" / "models" / "custom_skins" / "ct"
        cls.custom_ct_dir.mkdir(parents=True, exist_ok=True)
        real_usp = resolve_model_path("usp", team="ct")
        shutil.copy2(real_usp, cls.custom_ct_dir / "v_usp.mdl")

        # Config files
        configs_dir = cls.root / "cstrike" / "addons" / "amxmodx" / "configs"
        configs_dir.mkdir(parents=True, exist_ok=True)
        inv = configs_dir / "skin_inventory.ini"
        inv.write_text("""
[CT_USP]
"USP-S | Kill Confirmed" "models/custom_skins/ct/v_usp.mdl" "models/pw_models/p_usp.mdl" "models/pw_models/w_usp.mdl"
""", encoding="utf-8")

        loadout = configs_dir / "active_loadout.ini"
        loadout.write_text("""
[CT_ACTIVE]
USP = "models/custom_skins/ct/v_usp.mdl"
""", encoding="utf-8")

        # Mock sound file
        sound_dir = cls.root / "cstrike" / "sound" / "weapons" / "csgo" / "usp"
        sound_dir.mkdir(parents=True, exist_ok=True)
        (sound_dir / "usp-1.wav").write_bytes(b"RIFF\x24\x00\x00\x00WAVEfmt \x10\x00\x00\x00\x01\x00\x01\x00\x44\xac\x00\x00data\x00\x00\x00\x00")

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

    def test_api_amxx_catalog(self):
        url = f"http://127.0.0.1:{self.port}/api/amxx/catalog"
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read().decode())
            self.assertTrue(data["success"])
            self.assertIn("catalog", data)
            self.assertIn("categories", data)

    def test_api_amxx_loadout(self):
        url = f"http://127.0.0.1:{self.port}/api/amxx/loadout"
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read().decode())
            self.assertTrue(data["success"])
            self.assertEqual(data["loadout"]["ct"]["USP"], "models/custom_skins/ct/v_usp.mdl")

    def test_api_amxx_equip(self):
        url = f"http://127.0.0.1:{self.port}/api/amxx/loadout/equip"
        payload = json.dumps({
            "team": "ct",
            "weapon": "usp",
            "model_path": "models/custom_skins/ct/v_usp.mdl"
        }).encode()
        req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read().decode())
            self.assertTrue(data["success"])
            self.assertIn("equipped", data["message"].lower())

    def test_api_amxx_sound(self):
        url = f"http://127.0.0.1:{self.port}/api/amxx/sound?weapon=usp"
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req) as resp:
            self.assertEqual(resp.status, 200)
            self.assertEqual(resp.headers.get("Content-Type"), "audio/wav")
            content = resp.read()
            self.assertTrue(content.startswith(b"RIFF"))


if __name__ == "__main__":
    unittest.main()
