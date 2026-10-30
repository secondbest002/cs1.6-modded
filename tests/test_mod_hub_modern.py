"""
tests/test_mod_hub_modern.py
Comprehensive automated test suite for modernized CS 1.6 Mod Hub.
Tests atomic CFG parser/writer, AMXX modern plugins, CS2 Modern Engine configuration,
YaPB and Savage Bot ecosystem, and REST API server.
"""

from http import HTTPStatus
import json
from pathlib import Path
import shutil
import socket
import tempfile
import threading
import time
import unittest
import urllib.request
import urllib.error

# Ensure root is in sys.path
import sys
ROOT_DIR = Path(__file__).resolve().parent.parent
if str(ROOT_DIR) not in sys.path:
    sys.path.insert(0, str(ROOT_DIR))

from tools.cs16_mod_hub.core.cfg_utils import (
    detect_line_ending,
    atomic_write_file,
    parse_cfg_cvars,
    get_cfg_cvar,
    set_cfg_cvar,
    set_cfg_cvars,
)
from tools.cs16_mod_hub.core.amxx_adapter import (
    AmxxAdapter,
    MODERN_CORE_PLUGINS,
    PLUGIN_METADATA,
)
from tools.cs16_mod_hub.core.bot_adapter import (
    BotAdapter,
    PRESET_DEFINITIONS,
)
from tools.cs16_mod_hub.core.api import ModHubAPI
from tools.cs16_mod_hub.server import ModHubRequestHandler
from http.server import HTTPServer


def get_free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("", 0))
        return s.getsockname()[1]


class TestCfgUtils(unittest.TestCase):
    """Tests the atomic, comment-preserving CFG utility functions."""

    def setUp(self):
        self.tmp_dir = Path(tempfile.mkdtemp())
        self.cfg_file = self.tmp_dir / "test_config.cfg"

    def tearDown(self):
        shutil.rmtree(self.tmp_dir, ignore_errors=True)

    def test_line_ending_and_atomic_write(self):
        sample_crlf = "cvar_a \"1\"\r\ncvar_b \"2\"\r\n"
        atomic_write_file(self.cfg_file, sample_crlf)
        self.assertTrue(self.cfg_file.is_file())
        raw_text = self.cfg_file.read_bytes().decode("utf-8")
        self.assertEqual(detect_line_ending(raw_text), "\r\n")
        self.assertIn("\r\n", raw_text)

    def test_parse_and_update_cvars_preserving_comments(self):
        initial_content = (
            "// Header comment\r\n"
            "amx_test_mode 1 // Inline comment about mode\r\n"
            "yb_quota \"10\"\r\n"
            "; A semicolon comment line\r\n"
            "custom_flag \"hello world\"\r\n"
        )
        atomic_write_file(self.cfg_file, initial_content)

        # 1. Parse cvars
        cvars = parse_cfg_cvars(self.cfg_file)
        self.assertEqual(cvars.get("amx_test_mode"), "1")
        self.assertEqual(cvars.get("yb_quota"), "10")
        self.assertEqual(cvars.get("custom_flag"), "hello world")

        # 2. Update cvars atomically
        set_cfg_cvars(self.cfg_file, {
            "amx_test_mode": "0",
            "yb_quota": "16",
            "new_cvar": "appended_value",
        })

        updated_text = self.cfg_file.read_text(encoding="utf-8")
        # Ensure comments remain intact
        self.assertIn("// Header comment", updated_text)
        self.assertIn("; A semicolon comment line", updated_text)
        self.assertIn("// Inline comment about mode", updated_text)
        # Ensure updated values
        self.assertIn("amx_test_mode 0 // Inline comment about mode", updated_text)
        self.assertIn('yb_quota "16"', updated_text)
        self.assertIn("new_cvar \"appended_value\"", updated_text)

        # 3. Re-parse
        re_parsed = parse_cfg_cvars(self.cfg_file)
        self.assertEqual(re_parsed.get("amx_test_mode"), "0")
        self.assertEqual(re_parsed.get("yb_quota"), "16")
        self.assertEqual(re_parsed.get("new_cvar"), "appended_value")

    def test_append_without_trailing_newline_isolation(self):
        # File with no trailing newline
        content_no_newline = "cvar_first 1\r\ncvar_second 2"
        atomic_write_file(self.cfg_file, content_no_newline)
        set_cfg_cvar(self.cfg_file, "cvar_third", "3")
        raw = self.cfg_file.read_bytes().decode("utf-8")
        # cvar_second must not be corrupted by third
        self.assertIn("cvar_second 2\r\n", raw)
        self.assertIn("cvar_third 3\r\n", raw)


class TestAmxxAndCS2EngineAdapter(unittest.TestCase):
    """Tests AMXX plugin list, toggling, and CS2 Modern Engine configuration."""

    def setUp(self):
        self.tmp_dir = Path(tempfile.mkdtemp())
        self.adapter = AmxxAdapter(game_root=self.tmp_dir)

        # Mock plugins.ini
        self.adapter.plugins_ini.parent.mkdir(parents=True, exist_ok=True)
        self.adapter.plugins_ini.write_text(
            "; AMX Mod X plugins\r\n"
            "admin.amxx\r\n"
            "cs2_modern_engine.amxx ; CS2 Modern Engine\r\n"
            "cs2_skin_inventory.amxx\r\n"
            ";cs2_weapon_variants.amxx\r\n"
            "csgo_competitive.amxx\r\n"
            "bot_savage_ai.amxx\r\n",
            encoding="utf-8",
        )

        # Mock cs2_modern_engine.cfg
        self.adapter.cs2_engine_cfg.write_text(
            "amx_cs2_engine 1\r\n"
            "amx_cs2_kill_chimes 1\r\n"
            "amx_cs2_headshot_dink 1\r\n"
            "amx_cs2_throw_strength 1\r\n"
            "amx_switchhands_enable 1\r\n",
            encoding="utf-8",
        )

        # Mock csgo_competitive.cfg
        self.adapter.competitive_cfg.write_text(
            "amx_csgo_maxrounds 24\r\n"
            "amx_csgo_mode 1\r\n"
            "amx_csgo_warmup 60\r\n",
            encoding="utf-8",
        )

    def tearDown(self):
        shutil.rmtree(self.tmp_dir, ignore_errors=True)

    def test_plugins_status_and_metadata(self):
        plugins = self.adapter.list_custom_plugins()
        for p in MODERN_CORE_PLUGINS:
            self.assertIn(p, plugins)

        self.assertTrue(plugins["cs2_modern_engine.amxx"].enabled)
        self.assertTrue(plugins["cs2_skin_inventory.amxx"].enabled)
        self.assertFalse(plugins["cs2_weapon_variants.amxx"].enabled)  # Commented in mock
        self.assertTrue(plugins["csgo_competitive.amxx"].enabled)
        self.assertTrue(plugins["bot_savage_ai.amxx"].enabled)

    def test_plugin_toggle(self):
        # Enable cs2_weapon_variants.amxx
        ok = self.adapter.set_plugin_status("cs2_weapon_variants.amxx", True)
        self.assertTrue(ok)
        self.assertTrue(self.adapter.get_plugin_status("cs2_weapon_variants.amxx"))

        # Disable cs2_modern_engine.amxx
        ok = self.adapter.set_plugin_status("cs2_modern_engine.amxx", False)
        self.assertTrue(ok)
        self.assertFalse(self.adapter.get_plugin_status("cs2_modern_engine.amxx"))

    def test_cs2_engine_read_and_save(self):
        cvars = self.adapter.get_cs2_engine_settings()
        self.assertEqual(cvars.get("amx_cs2_engine"), "1")
        self.assertEqual(cvars.get("amx_cs2_kill_chimes"), "1")

        # Save updates
        self.adapter.set_cs2_engine_settings({
            "amx_cs2_kill_chimes": "0",
            "amx_switchhands_enable": "0",
        })

        updated = self.adapter.get_cs2_engine_settings()
        self.assertEqual(updated.get("amx_cs2_kill_chimes"), "0")
        self.assertEqual(updated.get("amx_switchhands_enable"), "0")

    def test_tweaking_auto_ammo_isolation(self):
        # Ensure cs2_engine_cfg has auto ammo and comments
        cfg_content = (
            "// CS2 Modern Engine Config\r\n"
            "amx_cs2_engine 1\r\n"
            "amx_cs2_kill_chimes 1          // Progressive Kill Chimes\r\n"
            "amx_csgo_ammo 1                // Aktifkan Sistem Amunisi Otomatis\r\n"
            "amx_usps_lock 1                // Kunci Peredam USP-S Selamanya\r\n"
        )
        self.adapter.cs2_engine_cfg.write_text(cfg_content, encoding="utf-8")

        # Tweak auto-ammo from 1 to 0
        ok = self.adapter.set_cs2_engine_cvar("amx_csgo_ammo", "0")
        self.assertTrue(ok)

        updated = self.adapter.cs2_engine_cfg.read_text(encoding="utf-8")
        # Target CVAR must be 0
        self.assertIn("amx_csgo_ammo 0                // Aktifkan Sistem Amunisi Otomatis", updated)
        # Other CVARs and comments must be UNCHANGED
        self.assertIn("// CS2 Modern Engine Config", updated)
        self.assertIn("amx_cs2_engine 1", updated)
        self.assertIn("amx_cs2_kill_chimes 1          // Progressive Kill Chimes", updated)
        self.assertIn("amx_usps_lock 1                // Kunci Peredam USP-S Selamanya", updated)

    def test_tweaking_c4_timer_isolation(self):
        # Ensure competitive_cfg has C4 timer with comment
        cfg_content = (
            "// Competitive Rules\r\n"
            "amx_csgo_mode 1\r\n"
            "mp_c4timer 40             // 40 detik C4 timer standar kompetitif\r\n"
            "mp_roundtime 1.92         // CS2 Regulation\r\n"
        )
        self.adapter.competitive_cfg.write_text(cfg_content, encoding="utf-8")

        # Tweak C4 timer from 40 to 35
        ok = self.adapter.set_cvar("mp_c4timer", "35")
        self.assertTrue(ok)

        updated = self.adapter.competitive_cfg.read_text(encoding="utf-8")
        self.assertIn("mp_c4timer 35             // 40 detik C4 timer standar kompetitif", updated)
        self.assertIn("// Competitive Rules", updated)
        self.assertIn("amx_csgo_mode 1", updated)
        self.assertIn("mp_roundtime 1.92         // CS2 Regulation", updated)


class TestBotAdapterAndPresets(unittest.TestCase):
    """Tests YaPB Bot and Savage Esports AI configuration and presets."""

    def setUp(self):
        self.tmp_dir = Path(tempfile.mkdtemp())
        self.adapter = BotAdapter(game_root=self.tmp_dir)

        # Mock yapb.cfg
        self.adapter.yapb_cfg.parent.mkdir(parents=True, exist_ok=True)
        self.adapter.yapb_cfg.write_text(
            "yb_quota \"10\"\r\n"
            "yb_quota_mode \"fill\"\r\n"
            "yb_difficulty \"4\"\r\n"
            "yb_shoots_thru_walls \"2\"\r\n"
            "yb_autovacate \"1\"\r\n",
            encoding="utf-8",
        )

        # Mock bot_savage_roles.cfg
        self.adapter.savage_cfg.parent.mkdir(parents=True, exist_ok=True)
        self.adapter.savage_cfg.write_text(
            "bot_savage_enable \"1\"\r\n"
            "bot_savage_roles \"1\"\r\n"
            "bot_savage_triggerbot \"1\"\r\n"
            "bot_savage_recoil \"1\"\r\n"
            "bot_savage_wallbang \"1\"\r\n"
            "bot_savage_hivemind \"1\"\r\n",
            encoding="utf-8",
        )

    def tearDown(self):
        shutil.rmtree(self.tmp_dir, ignore_errors=True)

    def test_detect_demon_preset(self):
        preset = self.adapter.detect_active_preset()
        self.assertEqual(preset, "demon")

    def test_apply_vanilla_preset(self):
        res = self.adapter.apply_difficulty_preset("vanilla")
        self.assertTrue(res["success"])

        savage = self.adapter.get_savage_settings()
        yapb = self.adapter.get_yapb_settings()

        self.assertEqual(savage.get("bot_savage_enable"), "0")
        self.assertEqual(yapb.get("yb_difficulty"), "1")
        self.assertEqual(yapb.get("yb_shoots_thru_walls"), "1")
        self.assertEqual(self.adapter.detect_active_preset(), "vanilla")

    def test_apply_tactical_preset(self):
        res = self.adapter.apply_difficulty_preset("tactical")
        self.assertTrue(res["success"])

        savage = self.adapter.get_savage_settings()
        self.assertEqual(savage.get("bot_savage_enable"), "1")
        self.assertEqual(savage.get("bot_savage_roles"), "1")
        # Cheats must be OFF
        self.assertEqual(savage.get("bot_savage_triggerbot"), "0")
        self.assertEqual(savage.get("bot_savage_recoil"), "0")
        self.assertEqual(savage.get("bot_savage_wallbang"), "0")
        self.assertEqual(savage.get("bot_savage_hivemind"), "0")

        self.assertEqual(self.adapter.detect_active_preset(), "tactical")

    def test_master_switch_revert_to_yapb(self):
        # Turn off Savage AI
        res = self.adapter.toggle_savage_ai(False)
        self.assertTrue(res["success"])

        savage = self.adapter.get_savage_settings()
        self.assertEqual(savage.get("bot_savage_enable"), "0")
        self.assertEqual(self.adapter.detect_active_preset(), "vanilla")

        # Turn back on
        res = self.adapter.toggle_savage_ai(True)
        self.assertTrue(res["success"])
        savage = self.adapter.get_savage_settings()
        self.assertEqual(savage.get("bot_savage_enable"), "1")

    def test_sanitize_cheats(self):
        # Initial: demon preset with cheats on
        self.assertEqual(self.adapter.detect_active_preset(), "demon")
        savage = self.adapter.get_savage_settings()
        self.assertEqual(savage.get("bot_savage_triggerbot"), "1")
        self.assertEqual(savage.get("bot_savage_roles"), "1")

        # Sanitize cheats
        res = self.adapter.sanitize_cheats()
        self.assertTrue(res["success"])

        updated = self.adapter.get_savage_settings()
        # Cheats MUST be 0
        self.assertEqual(updated.get("bot_savage_triggerbot"), "0")
        self.assertEqual(updated.get("bot_savage_recoil"), "0")
        self.assertEqual(updated.get("bot_savage_wallbang"), "0")
        self.assertEqual(updated.get("bot_savage_hivemind"), "0")
        # Non-cheat roles must be UNTOUCHED
        self.assertEqual(updated.get("bot_savage_roles"), "1")
        self.assertEqual(updated.get("bot_savage_enable"), "1")


class TestModHubServerAndEndpoints(unittest.TestCase):
    """Tests the Python HTTP server and REST API endpoints."""

    @classmethod
    def setUpClass(cls):
        cls.port = get_free_port()
        ModHubRequestHandler.api_instance = ModHubAPI()
        cls.server = HTTPServer(("127.0.0.1", cls.port), ModHubRequestHandler)
        cls.server_thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.server_thread.start()
        cls.base_url = f"http://127.0.0.1:{cls.port}"
        time.sleep(0.1)

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def _get(self, path: str):
        req = urllib.request.Request(f"{self.base_url}{path}")
        with urllib.request.urlopen(req, timeout=3) as resp:
            data = resp.read()
            return resp.status, resp.headers, data

    def _post_json(self, path: str, payload: dict):
        body = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(
            f"{self.base_url}{path}",
            data=body,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=3) as resp:
            data = resp.read()
            return resp.status, json.loads(data.decode("utf-8"))

    def test_static_files_delivery(self):
        # 1. index.html
        status, headers, content = self._get("/")
        self.assertEqual(status, HTTPStatus.OK)
        self.assertIn("text/html", headers.get("Content-Type", ""))
        self.assertIn(b"CS 1.6 MOD HUB", content)

        # 2. style.css
        status, headers, content = self._get("/style.css")
        self.assertEqual(status, HTTPStatus.OK)
        self.assertIn("text/css", headers.get("Content-Type", ""))

        # 3. app.js
        status, headers, content = self._get("/app.js")
        self.assertEqual(status, HTTPStatus.OK)
        self.assertIn("javascript", headers.get("Content-Type", ""))

    def test_api_status_endpoint(self):
        status, _, content = self._get("/api/status")
        self.assertEqual(status, HTTPStatus.OK)
        res = json.loads(content.decode("utf-8"))
        self.assertEqual(res.get("status"), "online")
        self.assertIn("asset_studio", res)

    def test_api_plugins_and_toggle(self):
        status, _, content = self._get("/api/plugins")
        self.assertEqual(status, HTTPStatus.OK)
        res = json.loads(content.decode("utf-8"))
        self.assertTrue(res.get("success"))
        plugins = [p["name"] for p in res.get("plugins", [])]
        self.assertIn("cs2_modern_engine.amxx", plugins)

        # Toggle test
        status, post_res = self._post_json("/api/plugins/toggle", {
            "plugin": "cs2_weapon_variants.amxx",
            "active": True,
        })
        self.assertEqual(status, HTTPStatus.OK)
        self.assertTrue(post_res.get("success"))

    def test_api_cs2_engine_endpoints(self):
        status, _, content = self._get("/api/cs2-engine")
        self.assertEqual(status, HTTPStatus.OK)
        res = json.loads(content.decode("utf-8"))
        self.assertTrue(res.get("success"))
        self.assertIn("amx_cs2_engine", res.get("cvars", {}))

    def test_api_bots_endpoints(self):
        status, _, content = self._get("/api/bots")
        self.assertEqual(status, HTTPStatus.OK)
        res = json.loads(content.decode("utf-8"))
        self.assertTrue(res.get("success"))
        self.assertIn("active_preset", res)
        self.assertIn("yapb", res)
        self.assertIn("savage", res)

        # Test applying tactical preset
        status, post_res = self._post_json("/api/bots/preset", {"preset": "tactical"})
        self.assertEqual(status, HTTPStatus.OK)
        self.assertTrue(post_res.get("success"))

    def test_api_competitive_preset_and_sanitize(self):
        # 1. Apply Valve Major preset
        status, res = self._post_json("/api/competitive/preset", {"preset": "valve_major"})
        self.assertEqual(status, HTTPStatus.OK)
        self.assertTrue(res.get("success"))
        self.assertEqual(res.get("preset"), "valve_major")

        # 2. Sanitize Savage AI cheats
        status, res = self._post_json("/api/bots/sanitize-cheats", {})
        self.assertEqual(status, HTTPStatus.OK)
        self.assertTrue(res.get("success"))

    def test_api_backups_telemetry_and_verify(self):
        # 1. Telemetry endpoint
        status, _, content = self._get("/api/backups/telemetry")
        self.assertEqual(status, HTTPStatus.OK)
        res = json.loads(content.decode("utf-8"))
        self.assertTrue(res.get("success"))
        self.assertIn("total_files", res)
        self.assertIn("total_mb", res)

        # 2. Verify endpoint
        status, _, content = self._get("/api/backups/verify")
        self.assertEqual(status, HTTPStatus.OK)
        res = json.loads(content.decode("utf-8"))
        self.assertTrue(res.get("success"))
        self.assertIn("backups", res)


if __name__ == "__main__":
    unittest.main()
