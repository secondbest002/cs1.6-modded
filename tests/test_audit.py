"""
Audit script to verify frontend-backend consistency, CVAR mappings, and edge cases.
"""
import re
from pathlib import Path
import json

import sys
root = Path(__file__).resolve().parent.parent
if str(root) not in sys.path:
    sys.path.insert(0, str(root))

# 1. Check all getElementById in app.js vs index.html
with open(root / "tools" / "cs16_mod_hub" / "web" / "app.js", "r", encoding="utf-8") as f:
    js_text = f.read()

with open(root / "tools" / "cs16_mod_hub" / "web" / "index.html", "r", encoding="utf-8") as f:
    html_text = f.read()

ids_in_js = set(re.findall(r'document\.getElementById\(["\']([^"\']+)["\']\)', js_text))
print(f"Total IDs accessed by getElementById in JS: {len(ids_in_js)}")

missing_ids = []
for el_id in sorted(ids_in_js):
    pattern1 = f'id="{el_id}"'
    pattern2 = f"id='{el_id}'"
    if pattern1 not in html_text and pattern2 not in html_text:
        missing_ids.append(el_id)

print(f"Missing IDs in HTML: {missing_ids}")

# 2. Check all data-engine-cvar in index.html
engine_cvars_in_html = set(re.findall(r'data-engine-cvar=["\']([^"\']+)["\']', html_text))
print(f"data-engine-cvar in index.html: {len(engine_cvars_in_html)}")

# 3. Check all data-savage-cvar in index.html
savage_cvars_in_html = set(re.findall(r'data-savage-cvar=["\']([^"\']+)["\']', html_text))
print(f"data-savage-cvar in index.html: {len(savage_cvars_in_html)}")

# 4. Check all preset names in HTML
preset_buttons = set(re.findall(r'data-preset=["\']([^"\']+)["\']', html_text))
print(f"Presets in HTML: {sorted(preset_buttons)}")

from tools.cs16_mod_hub.core.bot_adapter import PRESET_DEFINITIONS
print(f"Presets in BotAdapter: {sorted(PRESET_DEFINITIONS.keys())}")
assert preset_buttons == set(PRESET_DEFINITIONS.keys()), "Preset definitions mismatch!"

print("Audit passed without assertion errors.")
