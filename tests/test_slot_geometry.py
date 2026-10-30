"""
tests/test_slot_geometry.py - Comprehensive Unit and Integration Test Suite
for CS 1.6 Asset Studio 3D Geometry Engine (Solusi A & Solusi B).
"""

import io
import json
import math
import os
from pathlib import Path
import shutil
import struct
import tempfile
import unittest
import numpy as np
from PIL import Image

from scripts.cs16_studio.mdl_core import (
    MdlModel,
    ROLE_STICKER,
    STUDIO_MAGIC,
    STUDIO_VERSION,
    STUDIO_NF_CHROME,
    STUDIO_NF_MASKED,
    extract_model_3d,
    resolve_model_path,
)
from scripts.cs16_studio.slot_geometry import (
    threejs_to_goldsrc_world,
    goldsrc_world_to_threejs,
    compute_tangent_basis,
    compute_bone_world_matrices,
    world_to_local_bone,
    local_bone_to_world,
    find_weapon_root_bone,
    reposition_slot_quad,
    inject_new_slot_quad,
    save_geometry_snapshot,
    restore_geometry_snapshot,
    validate_model_health,
)


class TestCoordinateAndMatrixSolvers(unittest.TestCase):
    """Verifies coordinate conversion and bone matrix inversion solvers."""

    def test_threejs_to_goldsrc_roundtrip(self):
        """Validates round-trip conversion between Three.js and GoldSrc world spaces."""
        test_points = [
            ([10.0, 20.0, 30.0], [0.0, 1.0, 0.0]),
            ([-15.5, 3.2, -42.8], [0.7071, 0.0, -0.7071]),
            ([0.0, 0.0, 0.0], [0.0, 0.0, 1.0]),
            ([100.25, -50.12, 12.34], [-0.577, 0.577, 0.577]),
        ]

        for p_three, n_three in test_points:
            p_arr = np.array(p_three, dtype=np.float32)
            n_arr = np.array(n_three, dtype=np.float32)
            n_arr /= np.linalg.norm(n_arr)

            gw_p, gw_n = threejs_to_goldsrc_world(p_arr, n_arr)
            restored_p, restored_n = goldsrc_world_to_threejs(gw_p, gw_n)

            p_err = np.max(np.abs(p_arr - restored_p))
            n_err = np.max(np.abs(n_arr - restored_n))

            self.assertLess(p_err, 1e-6, f"Position roundtrip error too high: {p_err}")
            self.assertLess(n_err, 1e-6, f"Normal roundtrip error too high: {n_err}")

    def test_bone_matrix_inversion_roundtrip(self):
        """Validates local bone coordinate transformation roundtrip."""
        usp_path = resolve_model_path("usp", team="ct")
        with open(usp_path, "rb") as f:
            data = f.read()

        world_matrices = compute_bone_world_matrices(data)
        self.assertGreater(len(world_matrices), 0)

        # Test with bone 36 (v_weapon.223_parent) and bone 0
        test_bone_indices = [0, min(36, len(world_matrices) - 1)]
        test_local_pts = [
            np.array([5.0, 10.0, -2.0], dtype=np.float32),
            np.array([-1.2, 0.0, 14.5], dtype=np.float32),
        ]
        test_local_norms = [
            np.array([0.0, 1.0, 0.0], dtype=np.float32),
            np.array([0.577, -0.577, 0.577], dtype=np.float32),
        ]

        for b_idx in test_bone_indices:
            m_bone = world_matrices[b_idx]
            for loc_p, loc_n in zip(test_local_pts, test_local_norms):
                gw_p, gw_n = local_bone_to_world(loc_p, loc_n, m_bone)
                restored_loc_p, restored_loc_n = world_to_local_bone(gw_p, gw_n, m_bone)

                p_err = np.max(np.abs(loc_p - restored_loc_p))
                n_err = np.max(np.abs(loc_n - restored_loc_n))

                self.assertLess(p_err, 1e-5, f"Bone pos error too high on bone {b_idx}: {p_err}")
                self.assertLess(n_err, 1e-3, f"Bone norm error too high on bone {b_idx}: {n_err}")

    def test_tangent_basis_orthonormality(self):
        """Verifies that compute_tangent_basis produces an orthonormal coordinate system."""
        test_normals = [
            [0.0, 1.0, 0.0],
            [1.0, 0.0, 0.0],
            [0.0, 0.0, 1.0],
            [-0.7071, 0.7071, 0.0],
        ]

        for normal in test_normals:
            for rot in [0.0, 30.0, 45.0, 90.0, 180.0]:
                u, v, n = compute_tangent_basis(normal, rotation_deg=rot)

                # Lengths must be 1.0
                self.assertAlmostEqual(float(np.linalg.norm(u)), 1.0, places=5)
                self.assertAlmostEqual(float(np.linalg.norm(v)), 1.0, places=5)
                self.assertAlmostEqual(float(np.linalg.norm(n)), 1.0, places=5)

                # Dot products must be 0 (mutually perpendicular)
                self.assertAlmostEqual(float(np.dot(u, v)), 0.0, places=5)
                self.assertAlmostEqual(float(np.dot(u, n)), 0.0, places=5)
                self.assertAlmostEqual(float(np.dot(v, n)), 0.0, places=5)

    def test_find_weapon_root_bone(self):
        """Tests finding the weapon root bone on real models."""
        usp_path = resolve_model_path("usp", team="ct")
        with open(usp_path, "rb") as f:
            data = f.read()

        root_bone = find_weapon_root_bone(data)
        # USP weapon root bone is bone 36 (v_weapon.223_parent)
        self.assertEqual(root_bone, 36)


class TestSlotRepositioning(unittest.TestCase):
    """Verifies in-place slot quad repositioning (Solusi B)."""

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
        self.usp_path = resolve_model_path("usp", team="ct")
        self.test_mdl = Path(self.temp_dir) / "v_usp_reposition.mdl"
        shutil.copy2(self.usp_path, self.test_mdl)

    def tearDown(self):
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_reposition_slot_quad_zero_byte_change(self):
        """Ensures repositioning modifies the file in-place with exactly 0 byte difference."""
        orig_size = self.test_mdl.stat().st_size

        res = reposition_slot_quad(
            self.test_mdl,
            slot_identifier="4",
            target_pos_three=[-12.0, -10.0, -50.0],
            target_normal_three=[0.0, 1.0, 0.0],
            scale=1.5,
            rotation=30.0,
        )

        self.assertTrue(res["success"])
        self.assertEqual(res["slot_name"], "4.bmp")

        new_size = self.test_mdl.stat().st_size
        self.assertEqual(
            new_size,
            orig_size,
            f"File size changed! Before: {orig_size}, After: {new_size} (diff: {new_size - orig_size})",
        )

        # Ensure valid GoldSrc header
        with open(self.test_mdl, "rb") as f:
            magic, ver = struct.unpack_from("<4sI", f.read(8), 0)
        self.assertEqual(magic, STUDIO_MAGIC)
        self.assertEqual(ver, STUDIO_VERSION)

    def test_reposition_slot_coordinates_updated(self):
        """Verifies that vertices in the 3D representation actually move to the target location."""
        res_3d_before = extract_model_3d(self.test_mdl)
        slot4_mesh_before = next(m for m in res_3d_before["meshes"] if m["texture_name"] == "4.bmp")
        orig_positions = list(slot4_mesh_before["positions"])

        # Target silencer area
        target_pos = [-12.0, -10.0, -50.0]
        reposition_slot_quad(
            self.test_mdl,
            slot_identifier="4.bmp",
            target_pos_three=target_pos,
            target_normal_three=[0.0, 1.0, 0.0],
            scale=1.0,
            rotation=0.0,
        )

        res_3d_after = extract_model_3d(self.test_mdl)
        slot4_mesh_after = next(m for m in res_3d_after["meshes"] if m["texture_name"] == "4.bmp")
        new_positions = list(slot4_mesh_after["positions"])

        # Coordinates should have changed
        self.assertNotEqual(orig_positions, new_positions)

        # Average position of the new quad should be close to target_pos
        avg_x = np.mean(new_positions[0::3])
        avg_y = np.mean(new_positions[1::3])
        avg_z = np.mean(new_positions[2::3])

        self.assertAlmostEqual(avg_x, target_pos[0], delta=2.5)
        self.assertAlmostEqual(avg_y, target_pos[1], delta=2.5)
        self.assertAlmostEqual(avg_z, target_pos[2], delta=2.5)

    def test_reposition_slot_undo(self):
        """Tests that restore_geometry_snapshot safely reverts repositioned slots."""
        orig_size = self.test_mdl.stat().st_size
        res_3d_orig = extract_model_3d(self.test_mdl)
        slot4_orig = next(m for m in res_3d_orig["meshes"] if m["texture_name"] == "4.bmp")["positions"]

        repo_res = reposition_slot_quad(
            self.test_mdl,
            slot_identifier="4",
            target_pos_three=[-12.0, -10.0, -50.0],
            target_normal_three=[0.0, 1.0, 0.0],
        )

        # Undo using snapshot
        undo_ok = restore_geometry_snapshot(self.test_mdl, snapshot_id=repo_res["snapshot_id"])
        self.assertTrue(undo_ok)
        self.assertEqual(self.test_mdl.stat().st_size, orig_size)

        res_3d_restored = extract_model_3d(self.test_mdl)
        slot4_restored = next(m for m in res_3d_restored["meshes"] if m["texture_name"] == "4.bmp")["positions"]
        self.assertEqual(slot4_orig, slot4_restored)


class TestSlotInjectionDisabled(unittest.TestCase):
    """Verifies that dynamic slot injection is disabled to prevent GoldSrc heap crashes."""

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
        self.usp_path = resolve_model_path("usp", team="ct")
        self.test_mdl = Path(self.temp_dir) / "v_usp_inject.mdl"
        shutil.copy2(self.usp_path, self.test_mdl)

    def tearDown(self):
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_inject_new_slot_quad_raises_runtime_error(self):
        """Ensures calling inject_new_slot_quad raises RuntimeError explaining safety rationale."""
        with self.assertRaises(RuntimeError) as ctx:
            inject_new_slot_quad(
                self.test_mdl,
                slot_name="5.bmp",
                target_pos_three=[-12.0, -10.0, -55.0],
                target_normal_three=[0.0, 1.0, 0.0],
            )
        self.assertIn("disabled", str(ctx.exception).lower())

    def test_model_inject_new_slot_raises_runtime_error(self):
        """Ensures calling model.inject_new_slot raises RuntimeError."""
        model = MdlModel(self.test_mdl)
        with self.assertRaises(RuntimeError) as ctx:
            model.inject_new_slot(
                slot_name="5.bmp",
                target_pos_three=[-12.0, -10.0, -55.0],
                target_normal_three=[0.0, 1.0, 0.0],
            )
        self.assertIn("disabled", str(ctx.exception).lower())


class TestMdlCoreIntegration(unittest.TestCase):
    """Verifies that MdlModel exposes clean helper methods delegating to slot_geometry."""

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
        self.usp_path = resolve_model_path("usp", team="ct")
        self.test_mdl = Path(self.temp_dir) / "v_usp_core.mdl"
        shutil.copy2(self.usp_path, self.test_mdl)

    def tearDown(self):
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_model_reposition_slot(self):
        """Verifies model.reposition_slot() modifies the model in-place and re-parses."""
        model = MdlModel(self.test_mdl)
        res = model.reposition_slot(
            slot_identifier="4",
            target_pos_three=[-12.0, -10.0, -50.0],
            target_normal_three=[0.0, 1.0, 0.0],
            scale=1.1,
            rotation=15.0,
        )
        self.assertTrue(res["success"])
        # Verify model has re-parsed
        self.assertGreaterEqual(len(model.textures), 10)

    def test_reposition_slot_with_slot_label_and_robustness(self):
        """Tests that slot labels like 'Slot 4' or 'slot_1' and NaN scale are handled robustly."""
        model = MdlModel(self.test_mdl)
        # Should cleanly resolve "Slot 4"
        res = model.reposition_slot(
            slot_identifier="Slot 4",
            target_pos_three=[-12.0, -10.0, -50.0],
            target_normal_three=[0.0, 0.0, 0.0],  # zero normal should fallback gracefully
            scale=float("nan"),  # NaN scale should fallback safely
            rotation=0.0,
        )
        self.assertTrue(res["success"])
        self.assertEqual(res["slot_name"], "4.bmp")


class TestModelHealthValidation(unittest.TestCase):
    """Verifies model health check and GoldSrc stability validator."""

    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
        self.usp_path = resolve_model_path("usp", team="ct")

    def tearDown(self):
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_healthy_original_model(self):
        """Original USP model should report 100% Clean with 0 issues."""
        res = validate_model_health(self.usp_path)
        self.assertTrue(res["healthy"])
        self.assertEqual(res["status"], "100% Clean")
        self.assertEqual(len(res["issues"]), 0)
        self.assertEqual(res["score"], 100)
        self.assertEqual(res["num_textures"], 10)

    def test_corrupted_model_detection(self):
        """Corrupted/truncated models should be detected as Unhealthy / Corrupt."""
        bad_mdl = Path(self.temp_dir) / "corrupt.mdl"
        with open(bad_mdl, "wb") as f:
            f.write(b"IDST\x0a\x00\x00\x00truncated_header")
        res = validate_model_health(bad_mdl)
        self.assertFalse(res["healthy"])
        self.assertEqual(res["status"], "Corrupt")
        self.assertGreater(len(res["issues"]), 0)

    def test_model_validate_health_method(self):
        """MdlModel.validate_health() method delegates properly."""
        model = MdlModel(self.usp_path)
        res = model.validate_health()
        self.assertTrue(res["healthy"])
        self.assertEqual(res["status"], "100% Clean")

    def test_player_model_health_multi_submodels(self):
        """Validates that player StudioModels with multi-model bodyparts (base > 1) validate cleanly."""
        for p_name in ["leet", "urban"]:
            p_path = Path(f"cstrike/models/player/{p_name}/{p_name}.mdl")
            if p_path.is_file():
                res = validate_model_health(p_path)
                self.assertTrue(res["healthy"], f"Player model {p_name} failed health check: {res['issues']}")
                self.assertEqual(res["status"], "100% Clean")
                self.assertLessEqual(res["max_verts_submodel"], 2048)


if __name__ == "__main__":
    unittest.main()
