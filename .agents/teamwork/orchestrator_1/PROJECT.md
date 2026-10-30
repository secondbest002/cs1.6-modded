# Project: CS 1.6 Unified Desktop GUI Manager (Mod Hub)

## Architecture
- **Language / Runtime**: Python 3.14.3 (64-bit AMD64) on Windows host.
- **GUI Engine**: CustomTkinter 6.0.0 (`customtkinter`) + Tcl/Tk 8.6 + Pillow 12.2.0 (`PIL.Image`, `PIL.ImageTk`).
- **Styling Standards**: Modern CS:GO / CS2 Dark Slate theme (`#1a1e24` app background, `#222831` card background, CS Gold `#e5a93c`, Cyan `#00adb5`, Orange `#ff7043`). STRICTLY ZERO EMOJIS. Monochrome clean Unicode glyphs (`◆`, `◈`, `▸`, `⚙`, `✦`, `⟲`, `✓`, `✕`, `⇄`, `[+]`, `[-]`).
- **Backend Architecture**: Process-isolated adapters in `tools/cs16_mod_hub/core/` wrapping existing verified scripts in `.agents/skills/` via streaming subprocesses with real-time GUI console logging.
- **Model Safety**: 100% non-destructive with guarded `.bak` backup creation before any binary modification, and GoldSrc `b'IDST'` ver 10 verification prior to restore.
- **AMXX Engine**: Line-preserving parser for `cstrike/addons/amxmodx/configs/plugins.ini` and regex-based CVAR editor for `csgo_competitive.cfg`.
- **Live Preview Pipeline**: In-memory GoldSrc texture & palette extraction via Pillow (`Image.frombytes('P', ...)` + `putpalette()`) with real-time HSV adjustment in under 2ms.

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | Common Adapter Runner | `tools/cs16_mod_hub/core/common.py`: path resolver, `AdapterResult` dataclass, subprocess streaming runner | M1 | R1 |
| 2 | Model Skin Transfer Adapter | `tools/cs16_mod_hub/core/model_adapter.py`: wraps `transfer_weapon_skin.py`, handles donor selection & P/W sync | M1 | R1, R2.1 |
| 3 | Glove Injection Adapter | `tools/cs16_mod_hub/core/model_adapter.py`: wraps `inject_gloves.py`, preserves animations & meshes | M1 | R1, R2.1 |
| 4 | P/W Sync Decal Baking Adapter | `tools/cs16_mod_hub/core/model_adapter.py`: wraps `bake_and_inject_pw.py`, composites decals to p_/w_ models | M1 | R1, R2.1 |
| 5 | Vibrance & Palette Adapter | `tools/cs16_mod_hub/core/vibrance_adapter.py`: wraps `adjust_vibrance.py`, supports presets & custom sliders | M1 | R1, R2.2 |
| 6 | Factory Palette Reset | `tools/cs16_mod_hub/core/vibrance_adapter.py`: restores pristine palette from `.original_palettes.dat` | M1 | R1, R2.2 |
| 7 | Sticker FX Adapter | `tools/cs16_mod_hub/core/sticker_adapter.py`: wraps `toggle_sticker_fx.py` (foil 0x42, matte 0x40, glow 0x60, hide, restore) | M1 | R1, R2.3 |
| 8 | In-Memory Live BMP Preview | `tools/cs16_mod_hub/core/palette_preview.py`: extracts texture/palette directly from MDL header and renders live PIL preview | M1 | R1, R2.2 |
| 9 | AMXX Plugin Manager Adapter | `tools/cs16_mod_hub/core/amxx_adapter.py`: line-preserving `;` comment/uncomment for target plugins in `plugins.ini` | M1 | R1, R2.4 |
| 10 | Competitive CVAR Tuner Adapter | `tools/cs16_mod_hub/core/amxx_adapter.py`: parses and updates MR12/MR15, warmup, kniferound in `csgo_competitive.cfg` | M1 | R1, R2.4 |
| 11 | Backup & Safety Center Adapter | `tools/cs16_mod_hub/core/model_adapter.py`: scans `.bak` files, checks IDST header, performs single & batch restores | M1 | R1, R2.5 |
| 12 | Dark Slate UI Theme & Glyphs | `tools/cs16_mod_hub/gui/theme.py`: color tokens, fonts, zero emojis enforcement, monochrome glyphs | M2 | R3 |
| 13 | Card Container & UI Components | `tools/cs16_mod_hub/gui/components/card_frame.py`, `log_console.py`, `preview_canvas.py` | M2 | R2, R3 |
| 14 | Main Application Window | `tools/cs16_mod_hub/gui/app.py` & `tools/cs16_mod_hub/main.py`: multi-tab container, responsive layout, crash handling | M2 | R2 |
| 15 | Skin & Model Studio Tab | `tools/cs16_mod_hub/gui/tabs/model_studio_tab.py`: weapon selector, donor skin picker, glove injection, P/W sync | M3 | R2.1 |
| 16 | Color & Vibrance Tuner Tab | `tools/cs16_mod_hub/gui/tabs/vibrance_tab.py`: precision sliders, preset buttons, live BMP side-by-side preview | M3 | R2.2 |
| 17 | Sticker FX Lab Tab | `tools/cs16_mod_hub/gui/tabs/sticker_fx_tab.py`: sticker slot selector, Chrome/Foil/Matte/Glow buttons, hide/restore | M3 | R2.3 |
| 18 | Plugin & Gameplay Manager Tab | `tools/cs16_mod_hub/gui/tabs/amxx_tab.py`: 7 live toggle switches, competitive format selector (MR12/MR15), warmup | M3 | R2.4 |
| 19 | Backup & Safety Center Tab | `tools/cs16_mod_hub/gui/tabs/safety_tab.py`: backup table, one-click restore all / selected, live streaming log console | M3 | R2.5 |
| 20 | Batch Launcher & Auto-Setup | `CS16_Mod_Manager.bat` in game root: directory anchor, python verification, pip auto-install of customtkinter, pythonw launch | M4 | R4 |
| 21 | Automated Adapter Import Verification | Unit & import tests verifying clean loading of all adapter modules without error | M5 | AC 1 |
| 22 | Non-Destructive Backup Verification | Automated test verifying all model operations create `.bak` backups before modifying | M5 | AC 2 |
| 23 | AMXX Config Roundtrip Verification | Automated test verifying plugins.ini and csgo_competitive.cfg roundtrip editing without corrupting comments | M5 | AC 3 |
| 24 | Zero Emoji Compliance Verification | Static scanner verifying 100% emoji-free codebase and UI labels | M5 | AC 5 |
| 25 | Live Palette Preview Verification | Automated & visual verification of before/after texture bitmap generation | M5 | AC 6 |
| 26 | Batch Script Launcher Verification | Script verification ensuring `CS16_Mod_Manager.bat` launches GUI cleanly | M5 | AC 7 |
| 27 | Phase 2 Adversarial Coverage Hardening | White-box edge-case stress testing with Challengers & Forensic Auditor | M5 | Dual Track |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Backend Core Adapters & Safety Engine | `tools/cs16_mod_hub/core/` (common, model, vibrance, sticker, amxx, palette_preview) + tests | none | DONE |
| M2 | GUI Framework, Theme & Core Components | `tools/cs16_mod_hub/gui/` (theme, card_frame, log_console, preview_canvas, app.py, main.py) | M1 | DONE |
| M3 | Modular Tabs & Interactive Business Logic | `tools/cs16_mod_hub/gui/tabs/` (5 tabs: model studio, vibrance, sticker, amxx, safety) | M2 | DONE |
| M4 | Batch Launcher & Setup Automation | `CS16_Mod_Manager.bat` in root workspace + end-to-end launcher test | M3 | DONE |
| M5 | E2E Testing Suite Validation & Adversarial Hardening | Phase 1 (100% pass Tiers 1-4) & Phase 2 (Tier 5 Adversarial Hardening + Audit) | M4 | DONE |

## Code Layout
```
d:/Games/Counter-Strike/Counter-Strike 1.6 Original/
├── CS16_Mod_Manager.bat                        # Game root automated launcher
├── tools/
│   └── cs16_mod_hub/
│       ├── __init__.py
│       ├── main.py                             # GUI launcher entry point
│       ├── core/                               # Core backend adapter package
│       │   ├── __init__.py
│       │   ├── common.py                       # Subprocess streaming runner & paths
│       │   ├── model_adapter.py                # Skin transfer, glove injection, P/W, backups
│       │   ├── vibrance_adapter.py             # Palette saturation/contrast/brightness runner
│       │   ├── sticker_adapter.py              # Sticker FX flag controller
│       │   ├── palette_preview.py              # In-memory texture & palette preview generator
│       │   └── amxx_adapter.py                 # AMXX plugins.ini & competitive CVAR manager
│       └── gui/                                # CustomTkinter GUI package
│           ├── __init__.py
│           ├── theme.py                        # Dark Slate theme, color tokens, glyphs
│           ├── app.py                          # Main CTk window layout & tabview
│           ├── components/                     # Reusable GUI components
│           │   ├── __init__.py
│           │   ├── card_frame.py               # Dark Slate container panel (#222831)
│           │   ├── log_console.py              # Streaming log console viewer
│           │   └── preview_canvas.py           # Live Pillow preview canvas
│           └── tabs/                           # Modular Tab views
│               ├── __init__.py
│               ├── model_studio_tab.py         # Tab 1: Skin & Model Studio
│               ├── vibrance_tab.py             # Tab 2: Color & Vibrance Tuner
│               ├── sticker_fx_tab.py           # Tab 3: Sticker FX Lab
│               ├── amxx_tab.py                 # Tab 4: Plugin & Gameplay Manager
│               └── safety_tab.py               # Tab 5: Backup & Safety Center
└── tests/                                      # Automated testing suite (Dual Track)
    ├── test_adapters.py                        # Tier 1 adapter unit & import tests
    ├── test_backups.py                         # Tier 2 non-destructive .bak tests
    ├── test_amxx.py                            # Tier 2 AMXX parser roundtrip tests
    ├── test_preview.py                         # Tier 3 live preview extraction tests
    ├── test_emoji_cleanliness.py               # Tier 4 zero emoji compliance static audit
    └── test_launcher.py                        # Tier 4 batch launcher verification
```

## Interface Contracts

### `tools.cs16_mod_hub.core.common`
- `AdapterResult(success: bool, message: str, stdout: str = "", stderr: str = "", returncode: int = 0)`
- `get_project_root() -> Path`
- `run_script_streaming(script_rel_path: str, args: List[str], log_callback: Optional[Callable[[str], None]] = None) -> AdapterResult`

### `tools.cs16_mod_hub.core.model_adapter`
- `transfer_skin(source: str, target: str, dir_path: str = "cstrike/models", sync_pw: bool = False, no_backup: bool = False, log_callback: Optional[Callable[[str], None]] = None) -> AdapterResult`
- `inject_gloves(target: str, source: str = "awp", dir_path: str = "cstrike/models", no_backup: bool = False, log_callback: Optional[Callable[[str], None]] = None) -> AdapterResult`
- `inject_pw(weapon: Optional[str] = None, v_model: Optional[str] = None, p_model: Optional[str] = None, w_model: Optional[str] = None, dir_path: str = "cstrike/models", no_backup: bool = False, log_callback: Optional[Callable[[str], None]] = None) -> AdapterResult`
- `list_viewmodels(dir_path: str = "cstrike/models") -> List[str]`
- `list_donor_models(search_dirs: Optional[List[str]] = None) -> List[str]`
- `list_backups(search_dirs: Optional[List[str]] = None) -> List[dict]`
- `restore_model_backup(model_name_or_path: str) -> AdapterResult`
- `restore_all_backups() -> AdapterResult`

### `tools.cs16_mod_hub.core.vibrance_adapter`
- `apply_vibrance(weapon: str, target: str = "weapon", preset: Optional[str] = None, sat: Optional[float] = None, contrast: Optional[float] = None, brightness: Optional[float] = None, reset: bool = False, dir_path: str = "cstrike/models", no_backup: bool = False, log_callback: Optional[Callable[[str], None]] = None) -> AdapterResult`
- `reset_vibrance(weapon: str, target: str = "weapon", dir_path: str = "cstrike/models", log_callback: Optional[Callable[[str], None]] = None) -> AdapterResult`

### `tools.cs16_mod_hub.core.sticker_adapter`
- `set_sticker_fx(weapon: str, mode: str, sticker_id: str = "all", dir_path: str = "cstrike/models", no_backup: bool = False, log_callback: Optional[Callable[[str], None]] = None) -> AdapterResult`
- `scan_model_stickers(mdl_path: str) -> List[dict]`

### `tools.cs16_mod_hub.core.palette_preview`
- `extract_weapon_texture(mdl_path: str, prefer_weapon: bool = True) -> tuple[str, int, int, int, bytes, bytes]`
- `generate_preview_images(mdl_path: str, sat: float, contrast: float, brightness: float, thumb_size: tuple[int, int] = (256, 256)) -> tuple[Image.Image, Image.Image, str]`

### `tools.cs16_mod_hub.core.amxx_adapter`
- `get_plugin_status(plugin_name: str) -> Optional[bool]`
- `set_plugin_status(plugin_name: str, enabled: bool) -> bool`
- `list_custom_plugins() -> Dict[str, dict]`
- `get_cvar(cvar_name: str) -> Optional[str]`
- `set_cvar(cvar_name: str, value: str) -> bool`
- `get_competitive_settings() -> Dict[str, str]`
- `set_competitive_settings(settings: Dict[str, str]) -> bool`
