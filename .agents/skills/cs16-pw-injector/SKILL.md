---
name: cs16-pw-injector
description: >-
  Use this skill when the user wants to bake and inject weapon skins and decals
  from a Counter-Strike 1.6 viewmodel (v_*.mdl) into its corresponding player model
  (p_*.mdl) and world model (w_*.mdl).
---

# CS 1.6 P & W Model Injector

This skill provides procedures and an automated script to bake viewmodel skins (including transparent decal layers like decals or stickers) into a single 256-color GoldSrc texture and inject it into the third-person player model (`p_*.mdl`) and dropped world model (`w_*.mdl`).

## Quick Command Usage

Run the bundled script [bake_and_inject_pw.py](./scripts/bake_and_inject_pw.py) using PowerShell or Command Prompt:

```powershell
# Bake and inject by weapon name (looks in cstrike_hd/models by default)
python .agents/skills/cs16-pw-injector/scripts/bake_and_inject_pw.py --weapon deagle

# Target a different models directory (e.g., standard cstrike/models)
python .agents/skills/cs16-pw-injector/scripts/bake_and_inject_pw.py --weapon ak47 --dir "cstrike/models"

# Specify explicit file paths
python .agents/skills/cs16-pw-injector/scripts/bake_and_inject_pw.py --v-model "cstrike_hd/models/v_deagle.mdl" --p-model "cstrike_hd/models/p_deagle.mdl" --w-model "cstrike_hd/models/w_deagle.mdl"
```

## How It Works
1. **Reads View Model Textures:** Extracts the base weapon texture (e.g. `pist_deagle.bmp`).
2. **Bakes Decals / Stickers:** Automatically detects any transparent decal layers (`decal_*.bmp` or masked flags `0x40`) and composites them over the base weapon texture.
3. **Quantizes to 256 Colors:** Converts the composited full RGB image into standard 8-bit indexed BMP with an optimized palette.
4. **Safety Backup:** Automatically creates `.bak` backups of `p_*.mdl` and `w_*.mdl`.
5. **In-Place Injection:** Injects the new texture bytes directly into both player and world models.
