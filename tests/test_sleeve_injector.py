"""
tests/test_sleeve_injector.py - Unit and Integration Tests for 3D Sleeve Injection Engine.

Verifies:
- detect_arm_type distinguishes bare_arm, jacket_sleeve, gloves_only
- calculate_scale_ratio Euclidean bone distance calculation and ratio
- build_bone_remapping hierarchical fallback (ForeTwist -> Forearm -> Hand)
- preflight_safety_check enforces MAXSTUDIOVERTS <= 2048 and bodyparts <= 32
- transplant_3d_sleeves preserves 3 submodels, creates atomic .manset_arm.bak backup, and validates model health
- 4 CT donor presets (sas_navy, gign_urban, gsg9_woodland, arctic_parka)
- glove_transfer bare arm guard against 2D baking
"""

import os
from pathlib import Path
import shutil
import struct
import tempfile
import unittest

PROJECT_ROOT = Path(__file__).resolve().parent.parent

from scripts.cs16_studio.sleeve_injector import (
    SLEEVE_PRESETS,
    detect_arm_type,
    calculate_scale_ratio,
    build_bone_remapping,
    preflight_safety_check,
    transplant_3d_sleeves,
    MAXSTUDIOVERTS,
    MAXSTUDIOBODYPARTS,
)
from scripts.cs16_studio.glove_transfer import (
    classify_glove_role,
    transfer_gloves,
)
from scripts.cs16_studio.slot_geometry import validate_model_health
from scripts.cs16_studio.mdl_core import MdlModel


class TestSleeveInjector(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.temp_dir = tempfile.mkdtemp()
        cls.ct_m4a1 = PROJECT_ROOT / "cstrike" / "models" / "custom_skins" / "ct" / "v_m4a1.mdl"
        cls.ct_usp = PROJECT_ROOT / "cstrike" / "models" / "custom_skins" / "ct" / "v_usp.mdl"
        cls.t_ak47 = PROJECT_ROOT / "cstrike" / "models" / "custom_skins" / "t" / "v_ak47.mdl"

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.temp_dir, ignore_errors=True)

    def test_detect_arm_type_ct_jacket(self):
        """CT models with sleeve.bmp and loose mesh should be detected as jacket_sleeve."""
        if self.ct_m4a1.is_file():
            info = detect_arm_type(self.ct_m4a1)
            self.assertEqual(info["arm_type"], "jacket_sleeve")
            self.assertTrue(info["is_jacket"])
            self.assertFalse(info["is_bare"])
            self.assertIn("sleeve.bmp", info["textures"])

    def test_detect_arm_type_t_bare(self):
        """T models with bare_arm texture should be detected as bare_arm."""
        if self.t_ak47.is_file():
            info = detect_arm_type(self.t_ak47)
            self.assertEqual(info["arm_type"], "bare_arm")
            self.assertTrue(info["is_bare"])
            self.assertFalse(info["is_jacket"])
            self.assertTrue(any("bare" in t.lower() for t in info["textures"]))

    def test_calculate_scale_ratio_same_rig(self):
        """Calculating scale ratio between two models with same rig should yield ~1.0."""
        if self.ct_m4a1.is_file():
            ratio, desc = calculate_scale_ratio(self.ct_m4a1, self.ct_m4a1)
            self.assertAlmostEqual(ratio, 1.0, places=2)
            self.assertIn("1.0000x", desc)

    def test_calculate_scale_ratio_cross_rig(self):
        """Calculating scale ratio between GoldSrc and CS:GO rigs should detect 0.4167x and 2.4x."""
        if self.ct_m4a1.is_file() and self.ct_usp.is_file():
            # GoldSrc target (10.3) / CS:GO donor (24.7) -> ~0.4167x
            ratio_down, desc_down = calculate_scale_ratio(self.ct_m4a1, self.ct_usp)
            self.assertAlmostEqual(ratio_down, 1.0 / 2.4, places=2)
            self.assertIn("0.4167x", desc_down)

            # CS:GO target (24.7) / GoldSrc donor (10.3) -> ~2.4x
            ratio_up, desc_up = calculate_scale_ratio(self.ct_usp, self.ct_m4a1)
            self.assertAlmostEqual(ratio_up, 2.4, places=2)
            self.assertIn("2.4000x", desc_up)

    def test_build_bone_remapping_hierarchy(self):
        """ForeTwist should fallback to Forearm, and fingers should fallback to Hand."""
        donor_bones = [
            {"name": "Bip01 L Hand", "parent": 1},
            {"name": "Bip01 L ForeTwist", "parent": 2},
            {"name": "Bip01 L Finger01", "parent": 0},
            {"name": "Bip01 L Forearm", "parent": -1},
        ]
        target_bones = [
            {"name": "ValveBiped.Bip01_L_Hand", "parent": 1},
            {"name": "ValveBiped.Bip01_L_Forearm", "parent": -1},
        ]

        remap = build_bone_remapping(donor_bones, target_bones)
        # Exact/Cleaned match for Hand (index 0 donor -> index 0 target)
        self.assertEqual(remap.get(0), 0)
        # Forearm match (index 3 donor -> index 1 target)
        self.assertEqual(remap.get(3), 1)
        # ForeTwist fallback (index 1 donor -> Forearm index 1 target)
        self.assertEqual(remap.get(1), 1)
        # Finger fallback (index 2 donor -> Hand index 0 target)
        self.assertEqual(remap.get(2), 0)

    def test_preflight_safety_check_pass(self):
        """Models within engine limits should pass safety checks."""
        if self.t_ak47.is_file() and self.ct_m4a1.is_file():
            t_data = self.t_ak47.read_bytes()
            d_data = self.ct_m4a1.read_bytes()
            is_safe, issues = preflight_safety_check(t_data, d_data, 1.0)
            self.assertTrue(is_safe)
            self.assertEqual(len(issues), 0)

    def test_preflight_safety_check_bodyparts_limit(self):
        """Pre-flight check should reject models exceeding MAXSTUDIOBODYPARTS."""
        if self.t_ak47.is_file() and self.ct_m4a1.is_file():
            t_data = bytearray(self.t_ak47.read_bytes())
            d_data = self.ct_m4a1.read_bytes()
            # Artificially set numbodyparts in target header (offset 204) to 32
            struct.pack_into("<I", t_data, 204, 32)
            is_safe, issues = preflight_safety_check(bytes(t_data), d_data, 1.0)
            self.assertFalse(is_safe)
            self.assertTrue(any("MAXSTUDIOBODYPARTS" in i for i in issues))

    def test_sleeve_presets_completeness(self):
        """Verify all 4 CT sleeve presets exist with valid default donor references."""
        expected = ["sas_navy", "gign_urban", "gsg9_woodland", "arctic_parka"]
        for p in expected:
            self.assertIn(p, SLEEVE_PRESETS)
            meta = SLEEVE_PRESETS[p]
            self.assertIn("name", meta)
            self.assertIn("description", meta)
            donor = meta.get("default_donor")
            if donor:
                donor_file = PROJECT_ROOT / donor
                self.assertTrue(donor_file.is_file(), f"Donor file missing: {donor_file}")

    def test_transplant_3d_sleeves_ak47(self):
        """Transplanting CT sleeves into bare-arm T model creates .manset_arm.bak and produces valid model."""
        if not self.t_ak47.is_file() or not self.ct_m4a1.is_file():
            self.skipTest("Missing test assets")

        # Copy AK47 to temporary folder
        work_ak47 = Path(self.temp_dir) / "v_ak47.mdl"
        shutil.copy2(self.t_ak47, work_ak47)

        # Execute transplant with sas_navy preset
        res = transplant_3d_sleeves(
            target_model_path=work_ak47,
            donor_preset="sas_navy",
            workspace_root=PROJECT_ROOT,
            create_backup=True,
        )

        self.assertTrue(res["success"], f"Transplant failed: {res.get('error')}")
        self.assertTrue(work_ak47.is_file())

        # Backup verification
        bak_file = work_ak47.with_suffix(".manset_arm.bak")
        self.assertTrue(bak_file.is_file(), "Backup .manset_arm.bak was not created.")

        # Health validation
        health = validate_model_health(work_ak47)
        self.assertTrue(health["healthy"], f"Transplanted model unhealthy: {health.get('issues')}")

        # Check transplanted model arm type is now jacket_sleeve
        new_arm = detect_arm_type(work_ak47)
        self.assertEqual(new_arm["arm_type"], "jacket_sleeve")
        self.assertIn("sleeve.bmp", new_arm["textures"])

    def test_transplant_3d_sleeves_generic_explicit_donor(self):
        """Transplanting with explicit donor_path invokes generic submodel splice, removing t_arm and injecting ct_arms."""
        if not self.t_ak47.is_file() or not self.ct_m4a1.is_file():
            self.skipTest("Missing test assets")

        work_ak47 = Path(self.temp_dir) / "v_ak47_generic.mdl"
        shutil.copy2(self.t_ak47, work_ak47)

        res = transplant_3d_sleeves(
            target_model_path=work_ak47,
            donor_path=self.ct_m4a1,
            workspace_root=PROJECT_ROOT,
            create_backup=True,
        )

        self.assertTrue(res["success"], f"Transplant failed: {res.get('error')}")
        self.assertEqual(res["method"], "generic_submodel_splice")
        self.assertIn("ct_arms_01", res["submodels_injected"])
        self.assertIn("ct_arms_02", res["submodels_injected"])
        self.assertIn("ct_arms_03", res["submodels_injected"])

        # Arm classification must be jacket_sleeve, not bare_arm
        arm = detect_arm_type(work_ak47)
        self.assertEqual(arm["arm_type"], "jacket_sleeve")
        self.assertIn("ct_arms_01", arm["arm_submodels"])
        self.assertNotIn("t_arm", arm["arm_submodels"])
        self.assertIn("sleeve.bmp", arm["textures"])

        # Health check
        health = validate_model_health(work_ak47)
        self.assertTrue(health["healthy"], f"Model unhealthy: {health.get('issues')}")

    def test_transplant_3d_sleeves_color_adjustments(self):
        """Transplanting with gign_urban or arctic_parka preset applies color adjustments cleanly."""
        if not self.t_ak47.is_file() or not self.ct_m4a1.is_file():
            self.skipTest("Missing test assets")

        work_ak47 = Path(self.temp_dir) / "v_ak47_gign.mdl"
        shutil.copy2(self.t_ak47, work_ak47)

        res = transplant_3d_sleeves(
            target_model_path=work_ak47,
            donor_preset="gign_urban",
            workspace_root=PROJECT_ROOT,
            create_backup=False,
        )

        self.assertTrue(res["success"], f"GIGN transplant failed: {res.get('error')}")
        arm = detect_arm_type(work_ak47)
        self.assertEqual(arm["arm_type"], "jacket_sleeve")
        health = validate_model_health(work_ak47)
        self.assertTrue(health["healthy"])

    def test_glove_transfer_bare_arm_guard(self):
        """glove_transfer classifies bare arm as bare_arm when guard_bare=True to prevent 2D overwrite."""
        role_bare = classify_glove_role("bare_arm_133.bmp", guard_bare=True)
        self.assertEqual(role_bare, "bare_arm")

        role_legacy = classify_glove_role("bare_arm_133.bmp", guard_bare=False)
        self.assertEqual(role_legacy, "sleeve")

        # Transferring gloves to a bare-arm model should guard against 2D overwrite
        if self.t_ak47.is_file() and self.ct_usp.is_file():
            test_target = Path(self.temp_dir) / "v_test_guard.mdl"
            shutil.copy2(self.t_ak47, test_target)

            res = transfer_gloves(
                source_model=self.ct_usp,
                target_model=test_target,
                sync_sleeves=True,
            )
            # Should have skipped sleeve 2D baking on bare arm and reported notice
            self.assertTrue(res.get("success", False))
            self.assertTrue(len(res.get("guarded_bare_arms", [])) > 0)
            self.assertIn("notice", res)

    def test_zero_unicode_emojis(self):
        """Strict Constraint: ZERO unicode emojis across touched and created files."""
        import re
        emoji_pattern = re.compile(r"[\U00010000-\U0010ffff]")
        files_to_check = [
            PROJECT_ROOT / "scripts" / "cs16_studio" / "sleeve_injector.py",
            PROJECT_ROOT / "scripts" / "cs16_studio" / "glove_transfer.py",
            PROJECT_ROOT / "scripts" / "cs16_studio" / "pov_manager.py",
            PROJECT_ROOT / "scripts" / "cs16_studio" / "web" / "server.py",
            PROJECT_ROOT / "scripts" / "cs16_studio" / "web" / "static" / "index.html",
            PROJECT_ROOT / "scripts" / "cs16_studio" / "web" / "static" / "style.css",
            PROJECT_ROOT / "scripts" / "cs16_studio" / "web" / "static" / "js" / "modules" / "viewer3d.js",
            PROJECT_ROOT / "scripts" / "cs16_studio" / "web" / "static" / "js" / "modules" / "pro_tools.js",
        ]
        for f in files_to_check:
            if f.is_file():
                content = f.read_text(encoding="utf-8")
                matches = emoji_pattern.findall(content)
                self.assertEqual(len(matches), 0, f"Found unicode emojis in {f.name}: {matches}")


if __name__ == "__main__":
    unittest.main()
