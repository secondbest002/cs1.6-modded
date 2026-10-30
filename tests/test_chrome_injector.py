"""
tests/test_chrome_injector.py - Unit and Regression Test Suite for
Dual-Layer Chrome Overlay Injection Engine (scripts/cs16_studio/chrome_injector.py).
"""

import io
import math
import os
from pathlib import Path
import shutil
import struct
import tempfile
import unittest

import numpy as np
from PIL import Image

from scripts.cs16_studio.chrome_injector import (
    CHROME_FLAGS,
    CHROME_PRESETS,
    MAXSTUDIOBODYPARTS,
    MAXSTUDIOVERTS,
    generate_chrome_texture,
    inspect_chrome_status,
    inject_chrome_overlay,
    remove_chrome_overlay,
    is_chrome_bodypart,
    is_chrome_texture,
    is_excluded_geometry,
    parse_model_geometry,
    serialize_model_binary,
)
from scripts.cs16_studio.mdl_core import extract_model_3d, ROLE_SKIN
from scripts.cs16_studio.slot_geometry import validate_model_health


class TestChromeTextureGeneration(unittest.TestCase):
    """Verifies procedural and custom reflection map generation."""

    def test_generate_chrome_silver_specifications(self):
        """Verifies silver preset matches verified gumus.bmp specifications."""
        pixels, palette = generate_chrome_texture("silver")

        self.assertEqual(len(pixels), 4096, "Pixel buffer must be exactly 64x64 (4096 bytes)")
        self.assertEqual(len(palette), 768, "Palette buffer must be exactly 256*3 (768 bytes)")

        pix_arr = np.frombuffer(pixels, dtype=np.uint8)
        pal_arr = np.frombuffer(palette, dtype=np.uint8).reshape((256, 3))

        # Index 0 must be pure black [0, 0, 0] for additive transparency
        np.testing.assert_array_equal(pal_arr[0], [0, 0, 0])

        # Verify ~88.7% index 0 black background
        zero_count = int((pix_arr == 0).sum())
        zero_pct = (zero_count / 4096.0) * 100.0
        self.assertAlmostEqual(zero_pct, 88.7, delta=1.0)

        # Verify RGB values
        rgb_img = pal_arr[pix_arr]
        avg_rgb = float(rgb_img.mean())
        max_rgb = int(rgb_img.max())

        self.assertGreaterEqual(avg_rgb, 5.0)
        self.assertLessEqual(avg_rgb, 9.5)
        self.assertAlmostEqual(max_rgb, 174, delta=2)

    def test_generate_chrome_presets(self):
        """Verifies subtle, intense, and gold preset variations."""
        # Subtle
        pix_subtle, pal_subtle = generate_chrome_texture("subtle")
        rgb_subtle = np.frombuffer(pal_subtle, dtype=np.uint8).reshape((256, 3))[np.frombuffer(pix_subtle, dtype=np.uint8)]
        self.assertAlmostEqual(int(rgb_subtle.max()), 120, delta=2)

        # Intense
        pix_intense, pal_intense = generate_chrome_texture("intense")
        rgb_intense = np.frombuffer(pal_intense, dtype=np.uint8).reshape((256, 3))[np.frombuffer(pix_intense, dtype=np.uint8)]
        self.assertAlmostEqual(int(rgb_intense.max()), 220, delta=2)

        # Gold
        pix_gold, pal_gold = generate_chrome_texture("gold")
        pal_gold_arr = np.frombuffer(pal_gold, dtype=np.uint8).reshape((256, 3))
        # Non-zero indices must show golden warm tint (R > G > B)
        sample_color = pal_gold_arr[150]
        self.assertGreater(sample_color[0], sample_color[1])
        self.assertGreater(sample_color[1], sample_color[2])

    def test_generate_chrome_custom_image(self):
        """Verifies custom image source conversion to 64x64 paletted reflection map."""
        test_img = Image.new("RGBA", (128, 128), (255, 0, 0, 255))
        pixels, palette = generate_chrome_texture(custom_image=test_img)

        self.assertEqual(len(pixels), 4096)
        self.assertEqual(len(palette), 768)
        pal_arr = np.frombuffer(palette, dtype=np.uint8).reshape((256, 3))
        np.testing.assert_array_equal(pal_arr[0], [0, 0, 0])

    def test_preset_custom_requires_custom_image(self):
        """Verifies that preset='custom' without custom_image raises ValueError."""
        with self.assertRaises(ValueError) as ctx:
            generate_chrome_texture(preset="custom", custom_image=None)
        self.assertIn("custom_image must be provided", str(ctx.exception))


class TestChromeInjectorUSPVerification(unittest.TestCase):
    """Performs deep verification of the chrome overlay injection on CT USP."""

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp(prefix="cs16_chrome_test_")
        self.src_usp = Path("cstrike/models/custom_skins/ct/v_usp.orig.mdl")
        if not self.src_usp.is_file():
            self.src_usp = Path("cstrike/models/custom_skins/ct/v_usp.mdl")

        self.test_mdl = Path(self.temp_dir) / "v_usp.mdl"
        shutil.copy2(self.src_usp, self.test_mdl)

    def tearDown(self):
        if os.path.exists(self.temp_dir):
            shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_clean_model_status_inspection(self):
        """Verifies status inspection on a pristine model before injection."""
        status = inspect_chrome_status(self.test_mdl)

        self.assertFalse(status["has_chrome"])
        self.assertEqual(status["chrome_bodyparts"], [])
        self.assertEqual(status["chrome_textures"], [])
        self.assertIsNone(status["preset"])
        self.assertTrue(status["can_inject"])
        self.assertEqual(status["target_count"], 5)
        # Verify 5 weapon skin bodyparts are identified (ref_01..05)
        self.assertEqual(len(status["target_skin_bodyparts"]), 5)

    def test_injection_trial_and_health_score(self):
        """
        Verifies injection trial on CT USP:
        - 100/100 health score
        - 0 byte drift
        - Correct flags (0x0022)
        - 3D mesh parity (vertex-to-vertex alignment between diffuse and chrome layers)
        """
        res = inject_chrome_overlay(self.test_mdl, preset="silver")

        self.assertTrue(res["success"])
        self.assertEqual(res["preset"], "silver")
        self.assertEqual(res["chrome_bodyparts_added"], 5)

        # Health Validation
        health = validate_model_health(self.test_mdl)
        self.assertTrue(health["healthy"], f"Health issues: {health.get('issues')}")
        self.assertEqual(health["score"], 100)
        self.assertTrue(health["size_match"], "0 byte drift required (file_size == header_length)")
        self.assertEqual(len(health["issues"]), 0)
        self.assertFalse(health["exceeds_vert_limit"])

        # Check status after injection
        status = inspect_chrome_status(self.test_mdl)
        self.assertTrue(status["has_chrome"])
        self.assertEqual(len(status["chrome_bodyparts"]), 5)
        self.assertEqual(len(status["chrome_textures"]), 1)
        self.assertEqual(status["chrome_textures"][0]["flags"], CHROME_FLAGS)
        self.assertEqual(status["preset"], "silver")

        # 3D Mesh Parity Check
        m3d = extract_model_3d(self.test_mdl)
        self.assertTrue(m3d["success"])

        # Sum all diffuse skin vertices and all chrome vertices
        base_skin_verts = sum(
            m["vertex_count"]
            for m in m3d["meshes"]
            if m["role"] == ROLE_SKIN and not m["is_chrome"]
        )
        chrome_verts = sum(
            m["vertex_count"]
            for m in m3d["meshes"]
            if m["is_chrome"]
        )

        self.assertGreater(base_skin_verts, 0, "Base diffuse weapon skin mesh must exist")
        self.assertGreater(chrome_verts, 0, "Chrome overlay mesh must exist")
        # Ensure exact 100% vertex count parity between skin mesh and chrome overlay
        self.assertEqual(
            base_skin_verts,
            chrome_verts,
            "Chrome overlay must have exact vertex parity with weapon diffuse mesh",
        )

    def test_idempotent_re_injection(self):
        """Verifies injecting twice updates the layer cleanly without stacking duplicate bodyparts."""
        # First injection: silver
        res1 = inject_chrome_overlay(self.test_mdl, preset="silver")
        self.assertTrue(res1["success"])
        bp_count_1 = res1["num_bodyparts"]

        # Second injection: gold (idempotent replacement)
        res2 = inject_chrome_overlay(self.test_mdl, preset="gold", force=True)
        self.assertTrue(res2["success"])
        bp_count_2 = res2["num_bodyparts"]

        self.assertEqual(bp_count_1, bp_count_2, "Idempotent injection must not stack duplicate bodyparts")

        status = inspect_chrome_status(self.test_mdl)
        self.assertTrue(status["has_chrome"])
        self.assertEqual(status["preset"], "gold")

        health = validate_model_health(self.test_mdl)
        self.assertEqual(health["score"], 100)

    def test_custom_image_status_detection(self):
        """Verifies injecting custom colored reflection map is correctly detected as 'custom' preset."""
        blue_img = Image.new("RGBA", (64, 64), (20, 50, 200, 255))
        res = inject_chrome_overlay(self.test_mdl, preset="custom", custom_image=blue_img, force=True)
        self.assertTrue(res["success"])

        status = inspect_chrome_status(self.test_mdl)
        self.assertTrue(status["has_chrome"])
        self.assertEqual(status["preset"], "custom")

    def test_reversion_and_removal(self):
        """Verifies remove_chrome_overlay restores pristine pre-injection model state."""
        orig_health = validate_model_health(self.test_mdl)
        orig_bodyparts = orig_health["num_bodyparts"]
        orig_textures = orig_health["num_textures"]

        # Inject
        inject_chrome_overlay(self.test_mdl, preset="silver")

        # Remove
        res_remove = remove_chrome_overlay(self.test_mdl)
        self.assertTrue(res_remove["success"])
        self.assertTrue(res_remove["removed"])

        # Status after removal
        status = inspect_chrome_status(self.test_mdl)
        self.assertFalse(status["has_chrome"])
        self.assertEqual(status["num_bodyparts"], orig_bodyparts)
        self.assertEqual(status["num_textures"], orig_textures)

        # Health validation
        health = validate_model_health(self.test_mdl)
        self.assertTrue(health["healthy"])
        self.assertEqual(health["score"], 100)
        self.assertTrue(health["size_match"])

        # Removing again when already clean
        res_remove2 = remove_chrome_overlay(self.test_mdl)
        self.assertTrue(res_remove2["success"])
        self.assertFalse(res_remove2["removed"])

    def test_remove_chrome_overlay_output_path_pristine(self):
        """Verifies remove_chrome_overlay copies model to output_path if model is already pristine."""
        out_dst = Path(self.temp_dir) / "pristine_copy.mdl"
        self.assertFalse(out_dst.exists())

        res = remove_chrome_overlay(self.test_mdl, output_path=out_dst)
        self.assertTrue(res["success"])
        self.assertFalse(res["removed"])
        self.assertTrue(out_dst.exists(), "Output path file must be written even when pristine")

    def test_immutable_backup_created(self):
        """Verifies .orig.mdl backup is created on first injection if missing."""
        orig_backup = self.test_mdl.with_suffix(".orig.mdl")
        if orig_backup.exists():
            orig_backup.unlink()

        inject_chrome_overlay(self.test_mdl, preset="silver")
        self.assertTrue(orig_backup.exists(), ".orig.mdl backup must be created on first edit")


class TestLimitsAndSafeties(unittest.TestCase):
    """Verifies isolation safeties, engine limits, and multi-mesh handling."""

    def test_bodypart_limit_preflight(self):
        """Verifies error raised when bodyparts would exceed MAXSTUDIOBODYPARTS (32)."""
        temp_dir = tempfile.mkdtemp(prefix="cs16_limit_test_")
        try:
            test_mdl = Path(temp_dir) / "limit.mdl"
            src = Path("cstrike/models/custom_skins/ct/v_usp.orig.mdl")
            if not src.is_file():
                src = Path("cstrike/models/custom_skins/ct/v_usp.mdl")
            shutil.copy2(src, test_mdl)

            # Modify header in memory to have 28 bodyparts (28 + 5 > 32)
            with open(test_mdl, "rb") as f:
                raw = bytearray(f.read())
            struct.pack_into("<I", raw, 204, 28)
            with open(test_mdl, "wb") as f:
                f.write(raw)

            with self.assertRaises(ValueError) as ctx:
                inject_chrome_overlay(test_mdl, preset="silver")
            self.assertIn("MAXSTUDIOBODYPARTS", str(ctx.exception))
        finally:
            shutil.rmtree(temp_dir, ignore_errors=True)

    def test_vertex_limit_preflight(self):
        """Verifies error raised when a duplicated submodel exceeds MAXSTUDIOVERTS (2048)."""
        temp_dir = tempfile.mkdtemp(prefix="cs16_vert_test_")
        try:
            test_mdl = Path(temp_dir) / "verts.mdl"
            src = Path("cstrike/models/custom_skins/ct/v_usp.orig.mdl")
            if not src.is_file():
                src = Path("cstrike/models/custom_skins/ct/v_usp.mdl")
            shutil.copy2(src, test_mdl)

            # Modify model 0 in bodypart 7 (ref_01) to declare 2049 vertices
            with open(test_mdl, "rb") as f:
                raw = bytearray(f.read())
            bpidx = struct.unpack_from("<I", raw, 208)[0]
            bp7_off = bpidx + 7 * 76
            m_idx = struct.unpack_from("<i", raw, bp7_off + 72)[0]
            struct.pack_into("<I", raw, m_idx + 80, 2049)  # numverts offset in mstudiomodel_t
            with open(test_mdl, "wb") as f:
                f.write(raw)

            with self.assertRaises(ValueError) as ctx:
                inject_chrome_overlay(test_mdl, preset="silver")
            self.assertIn("MAXSTUDIOVERTS", str(ctx.exception))
        finally:
            shutil.rmtree(temp_dir, ignore_errors=True)

    def test_multi_mesh_emptying_safety(self):
        """
        Verifies that in a submodel with multiple meshes (e.g. skin + scope/other),
        non-skin meshes in the duplicated chrome submodel have numtris = 0 and empty stream.
        Tested both on synthetic multi-mesh USP and real-world multi-mesh AWP.
        """
        temp_dir = tempfile.mkdtemp(prefix="cs16_multimesh_test_")
        try:
            # 1. Test real-world multi-mesh weapon: v_awp.mdl
            src_awp = Path("cstrike/models/custom_skins/ct/v_awp.mdl")
            if src_awp.is_file():
                test_awp = Path(temp_dir) / "v_awp.mdl"
                shutil.copy2(src_awp, test_awp)
                res = inject_chrome_overlay(test_awp, preset="silver")
                self.assertTrue(res["success"])

                with open(test_awp, "rb") as f:
                    p_awp = parse_model_geometry(f.read())

                chrome_bps = [bp for bp in p_awp["bodyparts"] if is_chrome_bodypart(bp["name"])]
                self.assertGreater(len(chrome_bps), 0)

                found_emptied_mesh = False
                found_active_skin_mesh = False

                for cbp in chrome_bps:
                    for m in cbp["models"]:
                        for mesh in m["meshes"]:
                            if mesh["actual_tex_idx"] != (len(p_awp["textures"]) - 1):
                                # Non-skin mesh (e.g. scope lens) must be completely emptied
                                self.assertEqual(mesh["numtris"], 0)
                                self.assertEqual(len(mesh["tri_commands"]), 0)
                                found_emptied_mesh = True
                            else:
                                # Weapon skin mesh must have active triangles
                                self.assertGreater(mesh["numtris"], 0)
                                self.assertGreater(len(mesh["tri_commands"]), 0)
                                found_active_skin_mesh = True

                self.assertTrue(found_emptied_mesh, "Must find and empty at least one non-skin mesh in AWP")
                self.assertTrue(found_active_skin_mesh, "Must find and keep active skin meshes in AWP")

            # 2. Test synthetic multi-mesh model on USP
            test_usp = Path(temp_dir) / "synth_multimesh.mdl"
            src_usp = Path("cstrike/models/custom_skins/ct/v_usp.orig.mdl")
            if not src_usp.is_file():
                src_usp = Path("cstrike/models/custom_skins/ct/v_usp.mdl")
            shutil.copy2(src_usp, test_usp)

            with open(test_usp, "rb") as f:
                parsed_usp = parse_model_geometry(f.read())

            # Add a non-skin (glove/scope) mesh to bodypart 7 (ref_01)
            target_model = parsed_usp["bodyparts"][7]["models"][0]
            orig_m0 = target_model["meshes"][0]
            # Non-skin mesh using texture 0 (sport_right.bmp, glove)
            synthetic_non_skin_mesh = {
                "numtris": orig_m0["numtris"],
                "skinref": 0,
                "actual_tex_idx": 0,
                "tri_commands": list(orig_m0["tri_commands"]),
                "n1": orig_m0["n1"],
                "n2": orig_m0["n2"],
            }
            target_model["meshes"].append(synthetic_non_skin_mesh)

            synth_buf = serialize_model_binary(
                header_block1=parsed_usp["header_block1"],
                bodyparts=parsed_usp["bodyparts"],
                textures=parsed_usp["textures"],
                skin_table=parsed_usp["skin_table"],
                numskinfamilies=parsed_usp["numskinfamilies"],
            )
            with open(test_usp, "wb") as f:
                f.write(synth_buf)

            # Inject chrome on synthetic multi-mesh model
            res_synth = inject_chrome_overlay(test_usp, preset="silver")
            self.assertTrue(res_synth["success"])

            with open(test_usp, "rb") as f:
                parsed_result = parse_model_geometry(f.read())

            chrome_bp7 = [bp for bp in parsed_result["bodyparts"] if bp["name"] == "chrome_1"][0]
            chrome_model = chrome_bp7["models"][0]
            self.assertEqual(len(chrome_model["meshes"]), 2)
            # Mesh 0 is skin mesh -> active chrome
            self.assertEqual(chrome_model["meshes"][0]["actual_tex_idx"], len(parsed_result["textures"]) - 1)
            self.assertGreater(chrome_model["meshes"][0]["numtris"], 0)
            # Mesh 1 is non-skin mesh -> emptied
            self.assertEqual(chrome_model["meshes"][1]["numtris"], 0)
            self.assertEqual(len(chrome_model["meshes"][1]["tri_commands"]), 0)

        finally:
            shutil.rmtree(temp_dir, ignore_errors=True)

    def test_non_glove_weapon_parts_not_excluded(self):
        """Verifies that weapon parts containing 'arm' or 'hand' substrings are not falsely excluded."""
        weapon_part_names = (
            "knife_handle",
            "m4a1_handguard",
            "sidearm_slide",
            "firearm_body",
            "weapon_charm",
            "armor_plate",
        )
        for name in weapon_part_names:
            self.assertFalse(
                is_excluded_geometry(name),
                f"Weapon part '{name}' should NOT be excluded by is_excluded_geometry",
            )

        # Actual glove and arm keywords must still be excluded
        glove_arm_names = (
            "sport_hand",
            "view_skin",
            "arms_mesh",
            "glove_left",
            "sleeve_ct",
            "finger_mesh",
        )
        for name in glove_arm_names:
            self.assertTrue(
                is_excluded_geometry(name),
                f"Glove/arm part '{name}' MUST be excluded by is_excluded_geometry",
            )

    def test_multi_skin_families_preservation(self):
        """
        Verifies that models with multiple skin families (numskinfamilies > 1)
        preserve all family slots and mesh skin references through injection and removal.
        """
        temp_dir = tempfile.mkdtemp(prefix="cs16_skinfam_test_")
        try:
            test_mdl = Path(temp_dir) / "skinfam.mdl"
            src = Path("cstrike/models/custom_skins/ct/v_usp.orig.mdl")
            if not src.is_file():
                src = Path("cstrike/models/custom_skins/ct/v_usp.mdl")
            shutil.copy2(src, test_mdl)

            with open(test_mdl, "rb") as f:
                parsed = parse_model_geometry(f.read())

            # Synthesize 2 skin families
            num_tex = len(parsed["textures"])
            orig_skin_table = list(range(num_tex)) + list(range(num_tex))  # 2 families
            synth_buf = serialize_model_binary(
                header_block1=parsed["header_block1"],
                bodyparts=parsed["bodyparts"],
                textures=parsed["textures"],
                skin_table=orig_skin_table,
                numskinfamilies=2,
            )
            with open(test_mdl, "wb") as f:
                f.write(synth_buf)

            # Inject chrome
            res_inj = inject_chrome_overlay(test_mdl, preset="gold")
            self.assertTrue(res_inj["success"])

            with open(test_mdl, "rb") as f:
                p_inj = parse_model_geometry(f.read())
            self.assertEqual(p_inj["numskinfamilies"], 2)
            # Injected skin table should have (num_tex + 1) * 2 entries
            self.assertEqual(len(p_inj["skin_table"]), (num_tex + 1) * 2)

            # Remove chrome
            res_rem = remove_chrome_overlay(test_mdl)
            self.assertTrue(res_rem["success"])
            self.assertTrue(res_rem["removed"])

            with open(test_mdl, "rb") as f:
                p_rem = parse_model_geometry(f.read())
            self.assertEqual(p_rem["numskinfamilies"], 2)
            self.assertEqual(len(p_rem["skin_table"]), num_tex * 2)
            self.assertEqual(p_rem["skin_table"], orig_skin_table)

        finally:
            shutil.rmtree(temp_dir, ignore_errors=True)

    def test_idempotent_re_injection_near_bodypart_limit(self):
        """
        Verifies that re-injecting a model whose total bodyparts is close to 32
        does not falsely double-count existing chrome bodyparts against MAXSTUDIOBODYPARTS.
        """
        temp_dir = tempfile.mkdtemp(prefix="cs16_reinject_limit_test_")
        try:
            test_mdl = Path(temp_dir) / "reinject_limit.mdl"
            src = Path("cstrike/models/custom_skins/ct/v_usp.orig.mdl")
            if not src.is_file():
                src = Path("cstrike/models/custom_skins/ct/v_usp.mdl")
            shutil.copy2(src, test_mdl)

            # First injection: adds 5 chrome bodyparts (14 + 5 = 19 bodyparts)
            inject_chrome_overlay(test_mdl, preset="silver")

            # Modify header in memory to declare 27 bodyparts (27 <= 32)
            # If re-injection naively added 27 + 5, it would exceed 32.
            # But clean count is 27 - 5 = 22, so 22 + 5 = 27 <= 32.
            with open(test_mdl, "rb") as f:
                raw = bytearray(f.read())
            struct.pack_into("<I", raw, 204, 27)
            with open(test_mdl, "wb") as f:
                f.write(raw)

            # Re-injection must succeed without false positive limit error
            res = inject_chrome_overlay(test_mdl, preset="gold", force=True)
            self.assertTrue(res["success"])

        finally:
            shutil.rmtree(temp_dir, ignore_errors=True)

    def test_scaled_uv_coordinates(self):
        """Verifies UVs in duplicated chrome meshes are scaled by 64 / base_dim."""
        temp_dir = tempfile.mkdtemp(prefix="cs16_uv_test_")
        try:
            test_mdl = Path(temp_dir) / "uv_test.mdl"
            src = Path("cstrike/models/custom_skins/ct/v_usp.orig.mdl")
            if not src.is_file():
                src = Path("cstrike/models/custom_skins/ct/v_usp.mdl")
            shutil.copy2(src, test_mdl)

            inject_chrome_overlay(test_mdl, preset="silver")

            with open(test_mdl, "rb") as f:
                data = f.read()
            parsed = parse_model_geometry(data)

            chrome_bps = [bp for bp in parsed["bodyparts"] if is_chrome_bodypart(bp["name"])]
            for cbp in chrome_bps:
                for m in cbp["models"]:
                    for mesh in m["meshes"]:
                        if mesh["numtris"] > 0:
                            for strip_len, verts in mesh["tri_commands"]:
                                for v_i, n_i, s, t in verts:
                                    # Coordinates should be scaled to fit 64x64 texture coordinates
                                    self.assertLessEqual(abs(s), 64 + 1)
                                    self.assertLessEqual(abs(t), 64 + 1)
        finally:
            shutil.rmtree(temp_dir, ignore_errors=True)

    def test_selective_component_targeting(self):
        """Verifies target_parts selectively injects chrome only onto chosen submodels."""
        temp_dir = tempfile.mkdtemp(prefix="cs16_selective_test_")
        try:
            test_mdl = Path(temp_dir) / "selective.mdl"
            src = Path("cstrike/models/custom_skins/ct/v_usp.orig.mdl")
            if not src.is_file():
                src = Path("cstrike/models/custom_skins/ct/v_usp.mdl")
            shutil.copy2(src, test_mdl)

            # Target only ref_01 (slide) and ref_05 (silencer)
            res = inject_chrome_overlay(test_mdl, preset="mirror", target_parts=["ref_01", "ref_05"])
            self.assertTrue(res["success"])
            self.assertEqual(res["chrome_bodyparts_added"], 2)

            with open(test_mdl, "rb") as f:
                data = f.read()
            parsed = parse_model_geometry(data)

            chrome_bps = [bp for bp in parsed["bodyparts"] if is_chrome_bodypart(bp["name"])]
            self.assertEqual(len(chrome_bps), 2)
            for cbp in chrome_bps:
                for m in cbp["models"]:
                    for mesh in m["meshes"]:
                        self.assertGreater(mesh["numtris"], 0)

            # Health check on selective model
            health = validate_model_health(test_mdl)
            self.assertTrue(health["healthy"])
            self.assertEqual(health["score"], 100)

            # Invalid target parts should raise ValueError
            with self.assertRaises(ValueError):
                inject_chrome_overlay(test_mdl, target_parts=["nonexistent_part_xyz"], force=True)

        finally:
            shutil.rmtree(temp_dir, ignore_errors=True)


if __name__ == "__main__":
    unittest.main()
