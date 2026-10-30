"""
tests/test_sync_release.py - Unit tests for tools/sync_release.py
Counter-Strike 1.6 Portable & Modular Hub
Zero Unicode Emojis - Standard ASCII output only.
"""

from io import StringIO
import os
from pathlib import Path
import re
import subprocess
import sys
import unittest

from tools.sync_release import (
    find_git,
    get_repo_root,
    get_worktree_info,
    show_status
)


class TestSyncRelease(unittest.TestCase):

    def setUp(self):
        self.root = get_repo_root()

    def test_find_git(self):
        git_bin = find_git()
        self.assertIsInstance(git_bin, str)
        self.assertTrue(len(git_bin) > 0)

    def test_get_repo_root(self):
        root = get_repo_root()
        self.assertTrue(root.exists())
        self.assertTrue((root / ".git").exists())

    def test_get_worktree_info_real(self):
        info = get_worktree_info(self.root)
        self.assertTrue(info["exists"])
        self.assertIn("branch", info)
        self.assertIn("sha", info)
        self.assertIn("dirty", info)
        self.assertIn("untracked", info)
        self.assertEqual(info["branch"], "release/complete")

    def test_get_worktree_info_nonexistent(self):
        fake_path = self.root / ".worktrees" / "nonexistent_wt_test_xyz"
        info = get_worktree_info(fake_path)
        self.assertFalse(info["exists"])
        self.assertEqual(info["branch"], "N/A")
        self.assertEqual(info["sha"], "N/A")
        self.assertFalse(info["dirty"])

    def test_show_status_runs(self):
        old_stdout = sys.stdout
        buf = StringIO()
        try:
            sys.stdout = buf
            show_status(self.root)
        finally:
            sys.stdout = old_stdout

        output = buf.getvalue()
        self.assertIn("GIT MULTI-WORKTREE ARCHITECTURE STATUS", output)
        self.assertIn("Root Integration", output)
        self.assertIn("Studio & Mod Hub", output)
        self.assertIn("AMXX Mechanics", output)
        self.assertIn("[OK]", output)

    def test_cli_help(self):
        script_path = self.root / "tools" / "sync_release.py"
        res = subprocess.run(
            [sys.executable, str(script_path), "--help"],
            capture_output=True,
            text=True
        )
        self.assertEqual(res.returncode, 0)
        self.assertIn("--status", res.stdout)
        self.assertIn("--sync", res.stdout)
        self.assertIn("--push", res.stdout)

    def test_cli_status(self):
        script_path = self.root / "tools" / "sync_release.py"
        res = subprocess.run(
            [sys.executable, str(script_path), "--status"],
            capture_output=True,
            text=True
        )
        self.assertEqual(res.returncode, 0)
        self.assertIn("GIT MULTI-WORKTREE ARCHITECTURE STATUS", res.stdout)


if __name__ == "__main__":
    unittest.main()
