# TEST_INFRA — CS 1.6 Unified Desktop GUI Manager (Mod Hub)

## 1. Test Architecture Overview

The testing infrastructure for the **Counter-Strike 1.6 Unified Desktop GUI Manager** is an independent, opaque-box, requirement-driven test framework designed to validate all backend adapters, file modifications, live texture rendering pipelines, AMXX configuration parsers, and operational safety guarantees.

### 1.1 Guiding Principles
1. **Opaque-Box Requirement Verification**: Tests validate observable behaviors, contract outputs, and file system mutations without relying on internal private implementations.
2. **Progressive Testability**: Each tier is verifiable against defined interface contracts. Tests handle staged availability gracefully with structured reporting.
3. **100% Non-Destructive Safety Isolation**: Tests operating on binary models (`.mdl`), palette caches, and AMXX configurations run in isolated synthetic sandboxes (`tempfile.TemporaryDirectory`) using generated valid GoldSrc binary fixtures, preventing any accidental modification or corruption of the user's live game files.
4. **Adversarial & Boundary Verification**: Tests actively feed malformed headers, non-existent paths, edge-case multipliers (0.0, negative, extreme values), corrupted backups, and invalid AMXX syntax to ensure resilience.
5. **Aesthetic & Static Compliance**: Automated static audits enforce project-wide visual invariants: strictly ZERO emojis in `.py` and `.bat` files, with full support for designated monochrome glyphs (`◆`, `◈`, `▸`, `⚙`, `✦`, `⟲`, `✓`, `✕`, `⇄`, `[+]`, `[-]`).

---

## 2. Test Tier Hierarchy

```
+---------------------------------------------------------------------------------+
| Tier 4: Real-World Scenarios & Compliance                                      |
| - Zero Emoji Compliance Static Audit (test_emoji_cleanliness.py)                |
| - Root Batch Launcher & Auto-Install Verification (test_launcher.py)             |
+---------------------------------------------------------------------------------+
                                      ^
                                      |
+---------------------------------------------------------------------------------+
| Tier 3: Cross-Feature Integration & Live Rendering                              |
| - Live Texture & Palette Extraction + Real-time HSV Generation (test_preview.py)|
| - Skin Transfer + P/W Model Synchronization Interoperability                    |
+---------------------------------------------------------------------------------+
                                      ^
                                      |
+---------------------------------------------------------------------------------+
| Tier 2: Boundary Conditions, Safety Invariants & Roundtrip Parsers              |
| - Non-destructive .bak Safety Backup & IDST Header Checks (test_backups.py)    |
| - Line-preserving AMXX plugins.ini & csgo_competitive.cfg (test_amxx.py)       |
+---------------------------------------------------------------------------------+
                                      ^
                                      |
+---------------------------------------------------------------------------------+
| Tier 1: Feature Coverage & Interface Contracts                                  |
| - Backend Core Adapters: common, model, vibrance, sticker, amxx (test_adapters) |
+---------------------------------------------------------------------------------+
```

---

## 3. Test Feature Matrix & Inventory

| ID | Module / Feature | Test File | Target Coverage | Key Assertions / Verifications |
| :--- | :--- | :--- | :--- | :--- |
| **T1.1** | `core.common` | `tests/test_adapters.py` | Path resolver & runner | `AdapterResult` schema, `get_project_root()`, process streaming, callbacks |
| **T1.2** | `core.model_adapter` | `tests/test_adapters.py` | Skin transfer & gloves | `transfer_skin`, `inject_gloves`, `inject_pw`, model inventory listings |
| **T1.3** | `core.vibrance_adapter`| `tests/test_adapters.py` | Palette tuning | Presets (`vivid`, `punchy`, `soft`, `grayscale`), custom float multipliers |
| **T1.4** | `core.sticker_adapter` | `tests/test_adapters.py` | Sticker FX flags | Modes (`foil 0x42`, `matte 0x40`, `glow 0x60`, `hide`, `restore`) |
| **T1.5** | `core.amxx_adapter` | `tests/test_adapters.py` | AMXX manager | `get_plugin_status`, `set_plugin_status`, `get_cvar`, `set_cvar` |
| **T2.1** | Backup Creation | `tests/test_backups.py` | Model safety | `.bak` creation before binary modification; existing `.bak` not overwritten |
| **T2.2** | Header Validation | `tests/test_backups.py` | Binary integrity | Rejection of non-GoldSrc files (missing `IDST` magic or ver != 10) on restore |
| **T2.3** | Single/Batch Restore | `tests/test_backups.py` | Safety center | `restore_model_backup()` and `restore_all_backups()` atomic file recovery |
| **T2.4** | AMXX Line Preserving | `tests/test_amxx.py` | Parser fidelity | Commenting `;` and uncommenting without altering indentation or inline comments |
| **T2.5** | Competitive CVARs | `tests/test_amxx.py` | Config roundtrip | MR12/MR15 round adjustments, section comments preserved, footer intact |
| **T3.1** | Texture Extraction | `tests/test_preview.py` | Live preview | GoldSrc texture struct reading: name, dimensions, 8-bit index, 768B palette |
| **T3.2** | Live HSV Math | `tests/test_preview.py` | Color engine | Saturation, contrast around 128 mid-gray, brightness, key 255 alpha preservation |
| **T3.3** | PIL Preview Render | `tests/test_preview.py` | GUI rendering | Dual thumbnail generation (original vs adjusted), thumbnail size constraints |
| **T4.1** | Zero Emoji Audit | `tests/test_emoji_cleanliness.py` | Aesthetics | Static scanner asserting 0 emojis across all `.py` and `.bat` files |
| **T4.2** | Launcher Automation | `tests/test_launcher.py` | Setup & boot | `CS16_Mod_Manager.bat` anchor, Python check, `customtkinter` auto-install |
| **T4.3** | Master Test Runner | `tests/run_all_tests.py` | Suite execution | Structured tiered test execution, execution timing, status reporting |

---

## 4. Test Suite Structure & Files

```
d:/Games/Counter-Strike/Counter-Strike 1.6 Original/
└── tests/
    ├── __init__.py                     # Test package initializer
    ├── fixtures.py                     # Synthetic GoldSrc MDL & AMXX test fixture generator
    ├── test_adapters.py                # Tier 1: Core adapter contract tests
    ├── test_backups.py                 # Tier 2: Non-destructive .bak & restore tests
    ├── test_amxx.py                    # Tier 2: Line-preserving AMXX parser tests
    ├── test_preview.py                 # Tier 3: In-memory live preview & HSV math tests
    ├── test_emoji_cleanliness.py       # Tier 4: Zero-emoji static compliance audit
    ├── test_launcher.py                # Tier 4: CS16_Mod_Manager.bat launcher verification
    └── run_all_tests.py                # Master test runner with tiered execution
```

---

## 5. Execution & Verification Guide

### 5.1 Running the Full Suite
To execute all test tiers:
```powershell
python tests/run_all_tests.py
```

### 5.2 Running Individual Test Suites
```powershell
python -m unittest tests/test_adapters.py
python -m unittest tests/test_backups.py
python -m unittest tests/test_amxx.py
python -m unittest tests/test_preview.py
python -m unittest tests/test_emoji_cleanliness.py
python -m unittest tests/test_launcher.py
```

### 5.3 Filter by Tier
```powershell
python tests/run_all_tests.py --tier 1
python tests/run_all_tests.py --tier 2
python tests/run_all_tests.py --tier 3
python tests/run_all_tests.py --tier 4
```

---

## 6. Pass / Fail Semantics & Thresholds

1. **Assertion Threshold**: 100% of defined tests in active suites must pass. 0 unhandled exceptions.
2. **Safety Threshold**: Any test scenario where a model file is modified without an accompanying `.bak` (or when `--no-backup` is not provided) constitutes an immediate test failure.
3. **Emoji Cleanliness Threshold**: Exactly 0 emojis permitted across all scanned `.py` and `.bat` files. Any detected emoji character fails `test_emoji_cleanliness.py`.
4. **Performance Threshold**: Palette extraction and live HSV preview image generation must execute in under 100ms per frame.
