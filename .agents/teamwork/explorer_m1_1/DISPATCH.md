# Dispatch for Explorer M1-1 (Model & Common Adapters)

## Mission
Design the concrete implementation plan and code specifications for:
1. `tools/cs16_mod_hub/core/common.py`:
   - Subprocess streaming runner (`run_script_streaming`) capturing stdout/stderr and calling optional `log_callback`.
   - `AdapterResult` dataclass (`success`, `message`, `stdout`, `stderr`, `returncode`).
   - Project root resolution (`get_project_root()`).
2. `tools/cs16_mod_hub/core/model_adapter.py`:
   - Wrapping `.agents/skills/cs16-skin-transfer/scripts/transfer_weapon_skin.py` (`transfer_skin`).
   - Wrapping `.agents/skills/cs16-glove-injector/scripts/inject_gloves.py` (`inject_gloves`).
   - Wrapping `.agents/skills/cs16-pw-injector/scripts/bake_and_inject_pw.py` (`inject_pw`).
   - Model file scanning: `list_viewmodels`, `list_donor_models`.
   - Backup management: `list_backups`, `restore_model_backup`, `restore_all_backups` with GoldSrc `b'IDST'` ver 10 verification.

## Working Directory
`d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\explorer_m1_1`

## Authoritative Inputs
- `d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\ORIGINAL_REQUEST.md`
- `d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\orchestrator_1\PROJECT.md`
- `d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\explorer_survey_1\handoff.md`
- `d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\explorer_survey_2\handoff.md`

Deliver complete implementation specifications and fix strategies in `handoff.md` and send a message.


## 2026-10-18T04:09:58Z
You are Explorer M1-1 (Model & Common Adapters).
Your working directory is:
d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\explorer_m1_1
Authoritative request:
d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\ORIGINAL_REQUEST.md
Project plan:
d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\orchestrator_1\PROJECT.md
Your dispatch instructions:
d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\explorer_m1_1\DISPATCH.md

Design concrete code specifications and test strategies for tools/cs16_mod_hub/core/common.py and model_adapter.py.
Write your report in handoff.md and send a message.
