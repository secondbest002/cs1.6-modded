"""
tests/test_pov_manager.py - Unit and Integration Tests for Modern POV Controller.

Verifies:
- PovConfig defaults, cloning, and dictionary serialization
- Preset library integrity (cs2_classic, csgo_desktop, couch, quake_centered, vanilla_16)
- Engine boundary hard clamping and visual clipping warning detection
- CFG serialization, comment handling, unquoted values, and parsing round-trip
- Atomic file operations on modern_pov.cfg and non-destructive userconfig.cfg hook
- CLI subcommand argument parsing and execution
"""

import io
import os
from pathlib import Path
import shutil
import stat
import sys
import tempfile
import unittest
from unittest.mock import patch

# Ensure project root is in sys.path
PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))
SCRIPTS_DIR = PROJECT_ROOT / "scripts"
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

from cs16_studio.pov_manager import (
    PovConfig,
    PRESETS,
    get_preset,
    validate_and_clamp,
    export_cfg_string,
    parse_cfg_string,
    apply_to_game,
    reset_to_vanilla,
    read_current_config,
)
from cs16_studio.cli import build_parser, cmd_pov


class TestPovConfig(unittest.TestCase):
    """Tests PovConfig data structure initialization, cloning, and serialization."""

    def test_default_values(self):
        cfg = PovConfig()
        self.assertAlmostEqual(cfg.offset_x, 2.5)
        self.assertAlmostEqual(cfg.offset_y, 1.5)
        self.assertAlmostEqual(cfg.offset_z, -1.5)
        self.assertAlmostEqual(cfg.lag_scale, 1.5)
        self.assertAlmostEqual(cfg.lag_speed, 8.0)
        self.assertEqual(cfg.shift, 2)
        self.assertAlmostEqual(cfg.shift_left_amt, 0.5)
        self.assertAlmostEqual(cfg.shift_right_amt, 0.25)
        self.assertEqual(cfg.retract, 1)
        self.assertEqual(cfg.bobstyle, 2)
        self.assertAlmostEqual(cfg.bobamt_lat, 0.4)
        self.assertAlmostEqual(cfg.bobamt_vert, 0.25)
        self.assertAlmostEqual(cfg.bob_lower_amt, 21.0)
        self.assertAlmostEqual(cfg.bobcycle, 0.8)
        self.assertAlmostEqual(cfg.camera_movement_interp, 0.1)
        self.assertAlmostEqual(cfg.camera_movement_scale, 1.0)

    def test_custom_values(self):
        cfg = PovConfig(offset_x=1.0, offset_y=2.0, offset_z=-0.5, bobstyle=0, retract=0)
        self.assertAlmostEqual(cfg.offset_x, 1.0)
        self.assertAlmostEqual(cfg.offset_y, 2.0)
        self.assertAlmostEqual(cfg.offset_z, -0.5)
        self.assertEqual(cfg.bobstyle, 0)
        self.assertEqual(cfg.retract, 0)

    def test_dict_serialization_and_deserialization(self):
        cfg = PovConfig(offset_x=-1.25, offset_y=0.5, offset_z=1.0, bobstyle=2)
        data = cfg.to_dict()
        self.assertIsInstance(data, dict)
        self.assertAlmostEqual(data["offset_x"], -1.25)
        self.assertAlmostEqual(data["offset_y"], 0.5)

        # Deserialization with extra unknown keys ignored
        data["extra_unknown_field"] = "should_be_ignored"
        restored = PovConfig.from_dict(data)
        self.assertAlmostEqual(restored.offset_x, -1.25)
        self.assertAlmostEqual(restored.offset_y, 0.5)
        self.assertAlmostEqual(restored.offset_z, 1.0)
        self.assertEqual(restored.bobstyle, 2)

    def test_clone_independence(self):
        orig = PovConfig(offset_x=2.0, offset_y=1.0)
        cloned = orig.clone()
        cloned.offset_x = -2.0
        self.assertAlmostEqual(orig.offset_x, 2.0)
        self.assertAlmostEqual(cloned.offset_x, -2.0)


class TestPresets(unittest.TestCase):
    """Tests POV preset definitions and get_preset retrieval."""

    def test_required_presets_present(self):
        expected_presets = {"cs2_classic", "csgo_desktop", "couch", "quake_centered", "vanilla_16"}
        self.assertTrue(expected_presets.issubset(set(PRESETS.keys())))

    def test_cs2_classic_preset_parameters(self):
        cfg = get_preset("cs2_classic")
        self.assertIsNotNone(cfg)
        self.assertAlmostEqual(cfg.offset_x, 2.5)
        self.assertAlmostEqual(cfg.offset_y, 1.5)
        self.assertAlmostEqual(cfg.offset_z, -1.5)
        self.assertEqual(cfg.bobstyle, 2)
        self.assertAlmostEqual(cfg.lag_scale, 1.5)
        self.assertEqual(cfg.retract, 1)

    def test_vanilla_16_preset_parameters(self):
        cfg = get_preset("vanilla_16")
        self.assertIsNotNone(cfg)
        self.assertAlmostEqual(cfg.offset_x, 0.0)
        self.assertAlmostEqual(cfg.offset_y, 0.0)
        self.assertAlmostEqual(cfg.offset_z, 0.0)
        self.assertEqual(cfg.bobstyle, 0)
        self.assertAlmostEqual(cfg.lag_scale, 0.0)
        self.assertEqual(cfg.retract, 0)

    def test_case_insensitive_get_preset(self):
        cfg = get_preset("CS2_CLASSIC")
        self.assertIsNotNone(cfg)
        self.assertAlmostEqual(cfg.offset_x, 2.5)

    def test_preset_mutation_does_not_affect_registry(self):
        cfg = get_preset("cs2_classic")
        cfg.offset_x = 99.0
        re_fetched = get_preset("cs2_classic")
        self.assertAlmostEqual(re_fetched.offset_x, 2.5)

    def test_unknown_preset_returns_none(self):
        self.assertIsNone(get_preset("non_existent_preset"))


class TestValidationAndClamp(unittest.TestCase):
    """Tests boundary validation, hard clamping, and visual clipping warnings."""

    def test_clamp_upper_bounds(self):
        cfg = PovConfig(offset_x=5.0, offset_y=3.5, offset_z=4.0)
        clamped, warnings = validate_and_clamp(cfg)
        self.assertAlmostEqual(clamped.offset_x, 2.5)
        self.assertAlmostEqual(clamped.offset_y, 2.0)
        self.assertAlmostEqual(clamped.offset_z, 2.0)
        # Warning should be generated because offset_y was 2.0 > 1.8
        self.assertTrue(any("offset_y > 1.8" in w for w in warnings))

    def test_clamp_lower_bounds(self):
        cfg = PovConfig(offset_x=-10.0, offset_y=-5.0, offset_z=-7.0)
        clamped, warnings = validate_and_clamp(cfg)
        self.assertAlmostEqual(clamped.offset_x, -2.5)
        self.assertAlmostEqual(clamped.offset_y, -2.0)
        self.assertAlmostEqual(clamped.offset_z, -2.0)
        # Warning should be generated because offset_z was -2.0 < -1.8
        self.assertTrue(any("offset_z < -1.8" in w for w in warnings))

    def test_safe_bounds_no_warnings(self):
        cfg = PovConfig(offset_x=1.0, offset_y=1.0, offset_z=-1.0)
        clamped, warnings = validate_and_clamp(cfg)
        self.assertAlmostEqual(clamped.offset_x, 1.0)
        self.assertAlmostEqual(clamped.offset_y, 1.0)
        self.assertAlmostEqual(clamped.offset_z, -1.0)
        self.assertEqual(len(warnings), 0)

    def test_edge_warning_thresholds(self):
        # Exactly on the edge
        cfg1 = PovConfig(offset_x=0.0, offset_y=1.8, offset_z=-1.8)
        _, warnings1 = validate_and_clamp(cfg1)
        self.assertEqual(len(warnings1), 0)

        # Just past threshold
        cfg2 = PovConfig(offset_x=0.0, offset_y=1.85, offset_z=-1.85)
        _, warnings2 = validate_and_clamp(cfg2)
        self.assertEqual(len(warnings2), 2)

    def test_dual_elites_auto_override(self):
        cfg = PovConfig(offset_x=2.5, offset_y=1.5, offset_z=-1.0)
        clamped, warnings = validate_and_clamp(cfg, weapon="v_elite.mdl")
        self.assertAlmostEqual(clamped.offset_x, 0.0)
        self.assertAlmostEqual(clamped.offset_y, 1.5)
        self.assertAlmostEqual(clamped.offset_z, -1.0)
        self.assertTrue(any("Dual Elites" in w for w in warnings))

        cfg2 = PovConfig(offset_x=-1.5, offset_y=1.0, offset_z=-0.5)
        clamped2, warnings2 = validate_and_clamp(cfg2, weapon="elites")
        self.assertAlmostEqual(clamped2.offset_x, 0.0)
        self.assertTrue(any("Dual Elites" in w for w in warnings2))


class TestCfgSerializationAndParsing(unittest.TestCase):
    """Tests export_cfg_string and parse_cfg_string round-trip integrity."""

    def test_export_cfg_content(self):
        cfg = PovConfig(
            offset_x=2.5,
            offset_y=1.5,
            offset_z=-1.5,
            lag_scale=1.5,
            lag_speed=8.0,
            shift=2,
            shift_left_amt=0.5,
            shift_right_amt=0.25,
            retract=1,
            bobstyle=2,
            bobamt_lat=0.4,
            bobamt_vert=0.25,
            bob_lower_amt=21.0,
            bobcycle=0.8,
        )
        cfg_str = export_cfg_string(cfg)

        self.assertIn('viewmodel_offset_x "2.50"', cfg_str)
        self.assertIn('viewmodel_offset_y "1.50"', cfg_str)
        self.assertIn('viewmodel_offset_z "-1.50"', cfg_str)
        self.assertIn('viewmodel_lag_scale "1.50"', cfg_str)
        self.assertIn('viewmodel_lag_speed "8.00"', cfg_str)
        self.assertIn('viewmodel_shift "2"', cfg_str)
        self.assertIn('viewmodel_shift_left_amt "0.50"', cfg_str)
        self.assertIn('viewmodel_shift_right_amt "0.25"', cfg_str)
        self.assertIn('viewmodel_retract "1"', cfg_str)
        self.assertIn('cl_bobstyle "2"', cfg_str)
        self.assertIn('cl_bobamt_lat "0.40"', cfg_str)
        self.assertIn('cl_bobamt_vert "0.25"', cfg_str)
        self.assertIn('cl_bob_lower_amt "21.0"', cfg_str)
        self.assertIn('cl_bobcycle "0.80"', cfg_str)
        self.assertIn('bind "f" "lookatweapon"', cfg_str)

    def test_parse_cfg_string_round_trip(self):
        original = PovConfig(
            offset_x=1.5,
            offset_y=-0.5,
            offset_z=-1.25,
            lag_scale=1.2,
            lag_speed=7.0,
            shift=1,
            shift_left_amt=0.3,
            shift_right_amt=0.15,
            retract=0,
            bobstyle=0,
            bobamt_lat=0.2,
            bobamt_vert=0.1,
            bob_lower_amt=15.0,
            bobcycle=0.75,
        )
        exported = export_cfg_string(original)
        parsed = parse_cfg_string(exported)

        self.assertAlmostEqual(parsed.offset_x, original.offset_x)
        self.assertAlmostEqual(parsed.offset_y, original.offset_y)
        self.assertAlmostEqual(parsed.offset_z, original.offset_z)
        self.assertAlmostEqual(parsed.lag_scale, original.lag_scale)
        self.assertAlmostEqual(parsed.lag_speed, original.lag_speed)
        self.assertEqual(parsed.shift, original.shift)
        self.assertAlmostEqual(parsed.shift_left_amt, original.shift_left_amt)
        self.assertAlmostEqual(parsed.shift_right_amt, original.shift_right_amt)
        self.assertEqual(parsed.retract, original.retract)
        self.assertEqual(parsed.bobstyle, original.bobstyle)
        self.assertAlmostEqual(parsed.bobamt_lat, original.bobamt_lat)
        self.assertAlmostEqual(parsed.bobamt_vert, original.bobamt_vert)
        self.assertAlmostEqual(parsed.bob_lower_amt, original.bob_lower_amt)
        self.assertAlmostEqual(parsed.bobcycle, original.bobcycle)

    def test_parse_unquoted_and_messy_cfg(self):
        raw = """
        // Comment header
        viewmodel_offset_x 2.50 // trailing comment
        viewmodel_offset_y '1.20'
        viewmodel_offset_z -1.00
        cl_bobstyle 2
        viewmodel_retract 1
        # alternate comment
        random_unrelated_cvar 123
        """
        parsed = parse_cfg_string(raw)
        self.assertAlmostEqual(parsed.offset_x, 2.5)
        self.assertAlmostEqual(parsed.offset_y, 1.2)
        self.assertAlmostEqual(parsed.offset_z, -1.0)
        self.assertEqual(parsed.bobstyle, 2)
        self.assertEqual(parsed.retract, 1)

    def test_parse_semicolons_and_multi_command(self):
        # Trailing semicolons and multi-command lines
        raw = (
            "viewmodel_offset_x 1.25;\n"
            "viewmodel_offset_y 1.80; viewmodel_offset_z -0.75;\n"
            "cl_bobstyle 0;\n"
        )
        parsed = parse_cfg_string(raw)
        self.assertAlmostEqual(parsed.offset_x, 1.25)
        self.assertAlmostEqual(parsed.offset_y, 1.80)
        self.assertAlmostEqual(parsed.offset_z, -0.75)
        self.assertEqual(parsed.bobstyle, 0)

    def test_parse_equals_assignment(self):
        raw = "viewmodel_offset_x = 1.30\nviewmodel_offset_y=1.40\n"
        parsed = parse_cfg_string(raw)
        self.assertAlmostEqual(parsed.offset_x, 1.30)
        self.assertAlmostEqual(parsed.offset_y, 1.40)


class TestFileApplicationAndGameHook(unittest.TestCase):
    """Tests apply_to_game, reset_to_vanilla, and read_current_config file system operations."""

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
        self.cstrike_dir = Path(self.temp_dir) / "cstrike"
        self.cstrike_dir.mkdir(parents=True, exist_ok=True)

    def tearDown(self):
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_apply_to_clean_directory(self):
        cfg = get_preset("cs2_classic")
        success = apply_to_game(self.cstrike_dir, cfg)
        self.assertTrue(success)

        # Check modern_pov.cfg exists
        pov_file = self.cstrike_dir / "modern_pov.cfg"
        self.assertTrue(pov_file.is_file())
        pov_content = pov_file.read_text(encoding="utf-8")
        self.assertIn('viewmodel_offset_x "2.50"', pov_content)

        # Check userconfig.cfg created with hook
        user_file = self.cstrike_dir / "userconfig.cfg"
        self.assertTrue(user_file.is_file())
        user_content = user_file.read_text(encoding="utf-8")
        self.assertIn("exec modern_pov.cfg", user_content)

    def test_apply_preserves_existing_userconfig(self):
        user_file = self.cstrike_dir / "userconfig.cfg"
        initial_content = (
            'bind "MOUSE4" "arm_toggle"\n'
            'alias "arm_toggle" "cl_righthand 0"\n'
            'mp_consistency "0"\n'
        )
        user_file.write_text(initial_content, encoding="utf-8")

        cfg = get_preset("csgo_desktop")
        success = apply_to_game(self.cstrike_dir, cfg)
        self.assertTrue(success)

        updated = user_file.read_text(encoding="utf-8")
        # Ensure previous content is untouched
        self.assertIn('bind "MOUSE4" "arm_toggle"', updated)
        self.assertIn('alias "arm_toggle" "cl_righthand 0"', updated)
        self.assertIn('mp_consistency "0"', updated)
        # Ensure hook was appended
        self.assertIn("exec modern_pov.cfg", updated)

    def test_apply_idempotent_hook(self):
        user_file = self.cstrike_dir / "userconfig.cfg"
        user_file.write_text('// Custom config\nexec modern_pov.cfg\n', encoding="utf-8")

        cfg = get_preset("cs2_classic")
        apply_to_game(self.cstrike_dir, cfg)
        apply_to_game(self.cstrike_dir, cfg)

        updated = user_file.read_text(encoding="utf-8")
        # Verify it occurs exactly once
        self.assertEqual(updated.count("exec modern_pov.cfg"), 1)

    def test_read_current_config(self):
        # Missing file returns None
        self.assertIsNone(read_current_config(self.cstrike_dir))

        # After applying, returns valid config
        cfg = get_preset("couch")
        apply_to_game(self.cstrike_dir, cfg)
        read_cfg = read_current_config(self.cstrike_dir)
        self.assertIsNotNone(read_cfg)
        self.assertAlmostEqual(read_cfg.offset_x, 0.0)
        self.assertAlmostEqual(read_cfg.offset_y, 2.0)
        self.assertAlmostEqual(read_cfg.offset_z, -2.0)
        self.assertAlmostEqual(read_cfg.lag_speed, 7.0)

    def test_reset_to_vanilla(self):
        # First apply cs2_classic
        apply_to_game(self.cstrike_dir, get_preset("cs2_classic"))
        cfg1 = read_current_config(self.cstrike_dir)
        self.assertAlmostEqual(cfg1.offset_x, 2.5)

        # Reset to vanilla
        reset_success = reset_to_vanilla(self.cstrike_dir)
        self.assertTrue(reset_success)

        cfg_vanilla = read_current_config(self.cstrike_dir)
        self.assertIsNotNone(cfg_vanilla)
        self.assertAlmostEqual(cfg_vanilla.offset_x, 0.0)
        self.assertAlmostEqual(cfg_vanilla.offset_y, 0.0)
        self.assertAlmostEqual(cfg_vanilla.offset_z, 0.0)
        self.assertEqual(cfg_vanilla.bobstyle, 0)
        self.assertAlmostEqual(cfg_vanilla.lag_scale, 0.0)

    def test_apply_with_readonly_files(self):
        # Create initial files
        cfg = get_preset("csgo_desktop")
        apply_to_game(self.cstrike_dir, cfg)

        pov_file = self.cstrike_dir / "modern_pov.cfg"
        user_file = self.cstrike_dir / "userconfig.cfg"

        # Make files read-only
        os.chmod(pov_file, stat.S_IREAD)
        os.chmod(user_file, stat.S_IREAD)

        # Now update config to cs2_classic while files are read-only
        cfg2 = get_preset("cs2_classic")
        success = apply_to_game(self.cstrike_dir, cfg2)
        self.assertTrue(success)

        # Verify update applied successfully
        read_cfg = read_current_config(self.cstrike_dir)
        self.assertIsNotNone(read_cfg)
        self.assertAlmostEqual(read_cfg.offset_x, 2.5)

        # Verify no stray tmp files left behind
        tmp_files = list(self.cstrike_dir.glob("*.tmp_*"))
        self.assertEqual(len(tmp_files), 0)

        # Cleanup permissions for teardown
        os.chmod(pov_file, stat.S_IWRITE)
        os.chmod(user_file, stat.S_IWRITE)

    def test_apply_with_utf8_bom(self):
        user_file = self.cstrike_dir / "userconfig.cfg"
        # Write userconfig starting with UTF-8 BOM and existing hook
        user_file.write_bytes("\ufeff// Comment\nexec modern_pov.cfg\n".encode("utf-8"))

        cfg = get_preset("cs2_classic")
        apply_to_game(self.cstrike_dir, cfg)

        content = user_file.read_text(encoding="utf-8-sig")
        # Ensure hook is not duplicated
        self.assertEqual(content.count("exec modern_pov.cfg"), 1)


class TestCliIntegration(unittest.TestCase):
    """Tests CLI parser and cmd_pov dispatch integration."""

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
        self.cstrike_dir = Path(self.temp_dir) / "cstrike"
        self.cstrike_dir.mkdir(parents=True, exist_ok=True)
        self.parser = build_parser()

    def tearDown(self):
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_cli_preset_application(self):
        args = self.parser.parse_args([
            "pov",
            "--preset", "csgo_desktop",
            "--cstrike", str(self.cstrike_dir),
        ])
        with patch("sys.stdout", new_callable=io.StringIO) as mock_out:
            cmd_pov(args)
            output = mock_out.getvalue()

        self.assertIn("Modern POV configuration successfully applied", output)
        read_cfg = read_current_config(self.cstrike_dir)
        self.assertIsNotNone(read_cfg)
        self.assertAlmostEqual(read_cfg.offset_x, 1.0)
        self.assertAlmostEqual(read_cfg.offset_y, 1.0)
        self.assertAlmostEqual(read_cfg.offset_z, -1.0)

    def test_cli_custom_offset_overrides(self):
        args = self.parser.parse_args([
            "pov",
            "--preset", "cs2_classic",
            "--x", "1.5",
            "--y", "0.8",
            "--z", "-1.0",
            "--bob", "0",
            "--lag", "0.5",
            "--cstrike", str(self.cstrike_dir),
        ])
        with patch("sys.stdout", new_callable=io.StringIO):
            cmd_pov(args)

        read_cfg = read_current_config(self.cstrike_dir)
        self.assertIsNotNone(read_cfg)
        self.assertAlmostEqual(read_cfg.offset_x, 1.5)
        self.assertAlmostEqual(read_cfg.offset_y, 0.8)
        self.assertAlmostEqual(read_cfg.offset_z, -1.0)
        self.assertEqual(read_cfg.bobstyle, 0)
        self.assertAlmostEqual(read_cfg.lag_scale, 0.5)

    def test_cli_status_display(self):
        # First apply
        apply_to_game(self.cstrike_dir, get_preset("cs2_classic"))

        args = self.parser.parse_args([
            "pov",
            "--status",
            "--cstrike", str(self.cstrike_dir),
        ])
        with patch("sys.stdout", new_callable=io.StringIO) as mock_out:
            cmd_pov(args)
            output = mock_out.getvalue()

        self.assertIn("Active Viewmodel POV Configuration", output)
        self.assertIn("cs2_classic", output)
        self.assertIn("2.50", output)

    def test_cli_reset(self):
        apply_to_game(self.cstrike_dir, get_preset("cs2_classic"))

        args = self.parser.parse_args([
            "pov",
            "--reset",
            "--cstrike", str(self.cstrike_dir),
        ])
        with patch("sys.stdout", new_callable=io.StringIO) as mock_out:
            cmd_pov(args)
            output = mock_out.getvalue()

        self.assertIn("reset to vanilla CS 1.6 defaults", output)
        cfg = read_current_config(self.cstrike_dir)
        self.assertAlmostEqual(cfg.offset_x, 0.0)

    def test_cli_export_to_custom_output_file(self):
        out_file = Path(self.temp_dir) / "custom_output.cfg"
        args = self.parser.parse_args([
            "pov",
            "--preset", "quake_centered",
            "--output", str(out_file),
        ])
        with patch("sys.stdout", new_callable=io.StringIO) as mock_out:
            cmd_pov(args)
            output = mock_out.getvalue()

        self.assertIn("exported to", output)
        self.assertTrue(out_file.is_file())
        content = out_file.read_text(encoding="utf-8")
        self.assertIn('viewmodel_offset_y "1.80"', content)

    def test_cli_preset_case_insensitive(self):
        args = self.parser.parse_args([
            "pov",
            "--preset", "CS2_CLASSIC",
            "--cstrike", str(self.cstrike_dir),
        ])
        with patch("sys.stdout", new_callable=io.StringIO):
            cmd_pov(args)

        read_cfg = read_current_config(self.cstrike_dir)
        self.assertIsNotNone(read_cfg)
        self.assertAlmostEqual(read_cfg.offset_x, 2.5)


if __name__ == "__main__":
    unittest.main()
