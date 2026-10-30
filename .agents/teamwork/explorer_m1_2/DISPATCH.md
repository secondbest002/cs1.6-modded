# Dispatch for Explorer M1-2 (Vibrance, Stickers, and Palette Preview)

## Mission
Design the concrete implementation plan and code specifications for:
1. `tools/cs16_mod_hub/core/vibrance_adapter.py`:
   - Wrapping `.agents/skills/cs16-color-vibrance/scripts/adjust_vibrance.py` (`apply_vibrance`, `reset_vibrance`).
   - Preset mapping (`vivid`, `punchy`, `soft`, `grayscale`) and custom sliders (`sat`, `contrast`, `brightness`).
   - Target group choices (`weapon`, `gloves`, `all`).
   - Factory palette reset using `.original_palettes.dat`.
2. `tools/cs16_mod_hub/core/sticker_adapter.py`:
   - Wrapping `.agents/skills/cs16-sticker-fx/scripts/toggle_sticker_fx.py` (`set_sticker_fx`).
   - Effect modes: `foil` (0x42), `matte` (0x40), `glow` (0x60), `hide`, `restore`.
   - Weapon sticker slot scanner: `scan_model_stickers(mdl_path)`.
3. `tools/cs16_mod_hub/core/palette_preview.py`:
   - Direct GoldSrc MDL texture and palette extractor without running external tools (`extract_weapon_texture`).
   - Real-time HSV calculation and Pillow thumbnail generator (`generate_preview_images`).
   - Respecting masked texture transparency index 255 (`flags & 0x40`).

## Working Directory
`d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\explorer_m1_2`

## Authoritative Inputs
- `d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\ORIGINAL_REQUEST.md`
- `d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\orchestrator_1\PROJECT.md`
- `d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\explorer_survey_1\handoff.md`
- `d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\explorer_survey_3\handoff.md`

Deliver complete implementation specifications and fix strategies in `handoff.md` and send a message.


## 2026-10-18T04:09:58Z
You are Explorer M1-2 (Vibrance, Stickers, and Palette Preview).
Your working directory is:
d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\explorer_m1_2
Authoritative request:
d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\ORIGINAL_REQUEST.md
Project plan:
d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\orchestrator_1\PROJECT.md
Your dispatch instructions:
d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\explorer_m1_2\DISPATCH.md

Design concrete code specifications and test strategies for tools/cs16_mod_hub/core/vibrance_adapter.py, sticker_adapter.py, and palette_preview.py.
Write your report in handoff.md and send a message.
