---
name: cs16-glove-injector
description: >-
  Use this skill when the user wants to copy, swap, or inject glove/hand textures
  from one Counter-Strike 1.6 viewmodel (v_*.mdl) to another viewmodel to keep gloves consistent.
---

# CS 1.6 Glove Injector

This skill provides the procedure and executable CLI helper to transfer glove and hand textures from a reference weapon model (like `v_ak47.mdl`) into any target viewmodel (like `v_deagle.mdl`, `v_m4a1.mdl`, etc.) without altering the weapon geometry, animations, or sound triggers.

## Quick Command Usage

Run the bundled script [inject_gloves.py](./scripts/inject_gloves.py) using PowerShell or Command Prompt:

```powershell
# Transfer gloves by weapon name (uses cstrike_hd/models by default, source defaults to ak47)
python .agents/skills/cs16-glove-injector/scripts/inject_gloves.py --target deagle

# Specify explicit source weapon
python .agents/skills/cs16-glove-injector/scripts/inject_gloves.py --target deagle --source ak47

# Specify full paths
python .agents/skills/cs16-glove-injector/scripts/inject_gloves.py --target "cstrike_hd/models/v_m4a1.mdl" --source "cstrike_hd/models/v_ak47.mdl"
```

## How It Works
1. **Reads MDL Headers:** Parses the GoldSrc StudioModel format (`IDST`, version 10).
2. **Finds Glove Textures:** Detects glove/arm textures (`sport_right.bmp`, `sport_left.bmp`, `bare_arm_133.bmp`, etc.).
3. **Safety Backup:** Automatically creates a `.bak` backup copy of the target model before modifying.
4. **Lossless Injection:** Swaps the exact 8-bit indexed pixel data and 256-color RGB palette bytes in-place.
