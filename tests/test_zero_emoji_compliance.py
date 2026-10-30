"""
tests/test_zero_emoji_compliance.py - Verification that zero unicode emojis exist in UI code or python scripts.
"""

import html
from pathlib import Path
import re
import unittest

# Standard unicode emoji regex range
EMOJI_REGEX = re.compile(
    r"[\U00010000-\U0010ffff]|[\u2600-\u27bf]|[\u2300-\u23ff]|[\u2b50-\u2b55]|[\u203c-\u2049]|[\u25aa-\u25fe]"
)

TARGET_FILES = [
    "scripts/cs16_studio/mdl_core.py",
    "scripts/cs16_studio/asset_library.py",
    "scripts/cs16_studio/color_adjuster.py",
    "scripts/cs16_studio/stattrak_customizer.py",
    "scripts/cs16_studio/web/server.py",
    "scripts/cs16_studio/web/static/index.html",
    "scripts/cs16_studio/web/static/style.css",
    "scripts/cs16_studio/web/static/js/modules/color_studio.js",
    "scripts/cs16_studio/web/static/js/modules/library.js",
    "scripts/cs16_studio/web/static/js/modules/viewer3d.js",
    "tools/cs16_mod_hub/web/index.html",
    "tools/cs16_mod_hub/web/style.css",
    "tools/cs16_mod_hub/web/app.js",
    "tools/cs16_mod_hub/server.py",
    "tools/cs16_mod_hub/core/api.py",
    "tools/cs16_mod_hub/core/amxx_adapter.py",
    "tools/cs16_mod_hub/core/bot_adapter.py",
    "tools/cs16_mod_hub/core/model_adapter.py",
    "tools/cs16_mod_hub/core/cfg_utils.py",
    "tools/cs16_mod_hub/test_api_runner.py",
    "tests/test_mod_hub_modern.py",
    "tools/sync_release.py",
    "tools/sync_release.bat",
    ".agents/GIT_WORKTREE_GUIDE.md",
    "README.md",
    "tests/test_sync_release.py",
]


class TestZeroEmojiCompliance(unittest.TestCase):

    def test_zero_emojis_in_modified_files(self):
        root = Path(__file__).resolve().parent.parent
        violations = []

        for rel_path in TARGET_FILES:
            full_path = root / rel_path
            if not full_path.is_file():
                continue
            with open(full_path, "r", encoding="utf-8", errors="ignore") as f:
                lines = f.readlines()

            for line_idx, line in enumerate(lines, 1):
                # Unescape HTML entities (e.g. &#9733;) so escaped emojis/symbols cannot bypass check
                decoded = html.unescape(line)
                matches = EMOJI_REGEX.findall(decoded)
                if matches:
                    violations.append(f"{rel_path}:{line_idx}: found emojis {matches} in line: {line.strip()[:60]}")

        self.assertEqual(violations, [], "Unicode emojis detected in codebase! Only SVG glyphs allowed.")


if __name__ == "__main__":
    unittest.main()
