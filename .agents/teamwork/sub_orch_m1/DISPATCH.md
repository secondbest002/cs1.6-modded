# Dispatch for Sub-Orchestrator Milestone 1: Backend Core Adapters & Safety Engine

## Mission
Orchestrate and execute Milestone 1: Build and verify the complete backend core adapters and safety engine in `tools/cs16_mod_hub/core/` wrapping existing skills scripts and AMXX configs.

## Working Directory
`d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\sub_orch_m1`

## Authoritative Inputs
- `d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\ORIGINAL_REQUEST.md`
- `d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\orchestrator_1\PROJECT.md`
- Survey Reports:
  - `d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\explorer_survey_1\handoff.md`
  - `d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\explorer_survey_2\handoff.md`
  - `d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\explorer_survey_3\handoff.md`

## Scope of Milestone 1
1. `tools/cs16_mod_hub/__init__.py` and `tools/cs16_mod_hub/core/__init__.py`
2. `tools/cs16_mod_hub/core/common.py`: Path resolution, `AdapterResult` dataclass, subprocess streaming runner with log callbacks.
3. `tools/cs16_mod_hub/core/model_adapter.py`: Skin transfer (`transfer_weapon_skin.py`), glove injection (`inject_gloves.py`), P/W sync & bake (`bake_and_inject_pw.py`), model file scanning, .bak discovery and safe restore.
4. `tools/cs16_mod_hub/core/vibrance_adapter.py`: Color vibrance, contrast, brightness tuning (`adjust_vibrance.py`), presets, factory palette reset.
5. `tools/cs16_mod_hub/core/sticker_adapter.py`: Sticker flags (`toggle_sticker_fx.py`) for Foil (0x42), Matte (0x40), Glow (0x60), Hide, Restore, and model sticker slot scanner.
6. `tools/cs16_mod_hub/core/palette_preview.py`: In-memory GoldSrc texture extraction and Pillow-based live preview generator.
7. `tools/cs16_mod_hub/core/amxx_adapter.py`: Safe line-preserving toggling of plugins in `cstrike/addons/amxmodx/configs/plugins.ini` and CVAR editor for `csgo_competitive.cfg`.

## Execution Protocol
Follow the standard Project Pattern sub-orchestrator cycle:
- Assess scope -> Run Iteration Loop (Explorer -> Worker -> Reviewer x2 -> Challenger x2 -> Forensic Auditor).
- Zero tolerance for cheating or dummy implementations. Ensure all adapters genuinely interact with existing scripts and file formats.
- Verify that automated import tests pass for all adapter modules.
- Maintain your own `SCOPE.md`, `BRIEFING.md`, `progress.md`, and `GATE_STATUS.md`.
- Report completion back to Project Orchestrator with handoff.md.
