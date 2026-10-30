# Dispatch for E2E Testing Orchestrator

## Mission
Design and implement the comprehensive, opaque-box, requirement-driven E2E test suite for the Counter-Strike 1.6 Unified Desktop GUI Manager project (Mod Hub).

## Working Directory
`d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\e2e_testing_orchestrator`

## Authoritative Inputs
- `d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\ORIGINAL_REQUEST.md`
- `d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\orchestrator_1\PROJECT.md`

## Mandate & Dual Track Protocol
1. Act as the independent E2E Testing Orchestrator.
2. Create `TEST_INFRA.md` in `.agents/teamwork/TEST_INFRA.md` (and summary at project root if needed).
3. Design test cases across 4 tiers:
   - Tier 1: Feature Coverage (>=5 per feature)
   - Tier 2: Boundary & Corner Cases (>=5 per feature)
   - Tier 3: Cross-Feature Combinations (pairwise interactions)
   - Tier 4: Real-World Scenarios (>=5 end-to-end user workflows)
4. Use `tests/` directory to write test runner and test scripts (`tests/test_adapters.py`, `tests/test_backups.py`, `tests/test_amxx.py`, `tests/test_preview.py`, `tests/test_emoji_cleanliness.py`, `tests/test_launcher.py`).
   Ensure tests are runnable via Python standard `unittest` or direct runner script.
5. Create and publish `TEST_READY.md` in `.agents/teamwork/TEST_READY.md` (and at project root if appropriate) once the test suite is ready.
6. Dispatch subagents (Explorers, Test Writers, Reviewers) as needed to construct the test infrastructure.
