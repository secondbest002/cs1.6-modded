# Dispatch for Explorer M1-3 (AMXX Adapter & Test Strategy)

## Mission
Design the concrete implementation plan and code specifications for:
1. `tools/cs16_mod_hub/core/amxx_adapter.py`:
   - Safe parsing and toggling of plugins in `cstrike/addons/amxmodx/configs/plugins.ini`.
   - Commenting/uncommenting target plugins (`team_weapon_skins.amxx`, `csgo_knife_sound_manager.amxx`, `csgo_m4_loadout.amxx`, `csgo_usps_silencer.amxx`, `csgo_competitive.amxx`, `csgo_ammo_refill.amxx`, `bot_savage_ai.amxx`) with `;`.
   - Preserving empty lines, section comments, and line order.
   - Parsing and modifying competitive CVARs in `cstrike/addons/amxmodx/configs/csgo_competitive.cfg` (MR12/MR15, warmup, overtime, kniferound, HUD, etc.) preserving inline comments.
   - Atomic file writing with `tempfile` and `os.replace` to prevent file corruption.
2. Verification strategy:
   - Automated import test script to verify all core modules import cleanly.
   - Roundtrip test fixtures for `plugins.ini` and `csgo_competitive.cfg`.

## Working Directory
`d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\explorer_m1_3`

## Authoritative Inputs
- `d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\ORIGINAL_REQUEST.md`
- `d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\orchestrator_1\PROJECT.md`
- `d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\explorer_survey_1\handoff.md`
- `d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\explorer_survey_2\handoff.md`

Deliver complete implementation specifications and fix strategies in `handoff.md` and send a message.


## 2026-10-18T04:09:58Z
You are Explorer M1-3 (AMXX Adapter & Test Strategy).
Your working directory is:
d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\explorer_m1_3
Authoritative request:
d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\ORIGINAL_REQUEST.md
Project plan:
d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\orchestrator_1\PROJECT.md
Your dispatch instructions:
d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\explorer_m1_3\DISPATCH.md

Design concrete code specifications and test strategies for tools/cs16_mod_hub/core/amxx_adapter.py and automated import verification.
Write your report in handoff.md and send a message.
