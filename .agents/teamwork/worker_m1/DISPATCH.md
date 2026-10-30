# Dispatch for Worker M1: Core Backend Adapters Implementation

## Mandatory Integrity Warning
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

## Mission
Implement all core backend adapter modules for Milestone 1 in `tools/cs16_mod_hub/core/` and verify with automated unit and roundtrip tests.

## Working Directory
`d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\worker_m1`

## Authoritative Inputs & Specifications
Subagents MUST read `ORIGINAL_REQUEST.md` before starting work:
- `d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\ORIGINAL_REQUEST.md`
- `d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\orchestrator_1\PROJECT.md`
- Detailed specifications and code designs in:
  - `d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\explorer_m1_1\handoff.md` (`common.py`, `model_adapter.py`)
  - `d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\explorer_m1_2\handoff.md` (`vibrance_adapter.py`, `sticker_adapter.py`, `palette_preview.py`)
  - `d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\explorer_m1_3\handoff.md` (`amxx_adapter.py`, `test_adapters.py`, `test_amxx.py`)

## Exclusively Owned Files
- `tools/cs16_mod_hub/__init__.py`
- `tools/cs16_mod_hub/core/__init__.py`
- `tools/cs16_mod_hub/core/common.py`
- `tools/cs16_mod_hub/core/model_adapter.py`
- `tools/cs16_mod_hub/core/vibrance_adapter.py`
- `tools/cs16_mod_hub/core/sticker_adapter.py`
- `tools/cs16_mod_hub/core/palette_preview.py`
- `tools/cs16_mod_hub/core/amxx_adapter.py`
- `tests/test_adapters.py`
- `tests/test_backups.py`
- `tests/test_amxx.py`
- `tests/test_preview.py`

## Verification Requirements
1. Implement all modules according to the exact specifications in the explorer handoff reports.
2. Run test execution commands:
   - `python -m unittest tests/test_adapters.py`
   - `python -m unittest tests/test_backups.py`
   - `python -m unittest tests/test_amxx.py`
   - `python -m unittest tests/test_preview.py`
3. Document commands executed, output logs, and test results in `handoff.md`.
4. Ensure zero emojis anywhere in code or comments.
5. Report completion in `handoff.md` and send a message.


## 2026-10-18T04:18:27Z
You are Worker M1.
Your working directory is:
d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\worker_m1
Authoritative request:
d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\ORIGINAL_REQUEST.md
Your dispatch instructions:
d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\worker_m1\DISPATCH.md

DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Implement tools/cs16_mod_hub/core/ (common.py, model_adapter.py, vibrance_adapter.py, sticker_adapter.py, palette_preview.py, amxx_adapter.py) and test suites in tests/ according to the Explorer handoff reports.
Run the tests, verify passing status, write handoff.md, and send a message.
