# Project: CS 1.6 Unified Desktop GUI Manager (Mod Hub)

See authoritative scope and design details at `.agents/teamwork/orchestrator_1/PROJECT.md`.

## Architecture Summary
- **Language / Runtime**: Python 3.14.3 (64-bit AMD64) on Windows host.
- **GUI Engine**: CustomTkinter 6.0.0 (`customtkinter`) + Tcl/Tk 8.6 + Pillow 12.2.0 (`PIL.Image`, `PIL.ImageTk`).
- **Styling Standards**: Modern CS:GO / CS2 Dark Slate theme (`#1a1e24` app background, `#222831` card background, CS Gold `#e5a93c`, Cyan `#00adb5`, Orange `#ff7043`). STRICTLY ZERO EMOJIS. Monochrome clean Unicode glyphs (`◆`, `◈`, `▸`, `⚙`, `✦`, `⟲`, `✓`, `✕`, `⇄`, `[+]`, `[-]`).
- **Backend Architecture**: Process-isolated adapters in `tools/cs16_mod_hub/core/` wrapping existing verified scripts in `.agents/skills/` via streaming subprocesses with real-time GUI console logging.
- **Model Safety**: 100% non-destructive with guarded `.bak` backup creation before any binary modification, and GoldSrc `b'IDST'` ver 10 verification prior to restore.
- **AMXX Engine**: Line-preserving parser for `cstrike/addons/amxmodx/configs/plugins.ini` and regex-based CVAR editor for `csgo_competitive.cfg`.
- **Live Preview Pipeline**: In-memory GoldSrc texture & palette extraction via Pillow (`Image.frombytes('P', ...)` + `putpalette()`) with real-time HSV adjustment in under 2ms.

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M1 | Backend Core Adapters & Safety Engine | `tools/cs16_mod_hub/core/` (common, model, vibrance, sticker, amxx, palette_preview) + tests | none | DONE |
| M2 | GUI Framework, Theme & Core Components | `tools/cs16_mod_hub/gui/` (theme, card_frame, log_console, preview_canvas, app.py, main.py) | M1 | DONE |
| M3 | Modular Tabs & Interactive Business Logic | `tools/cs16_mod_hub/gui/tabs/` (5 tabs: model studio, vibrance, sticker, amxx, safety) | M2 | DONE |
| M4 | Batch Launcher & Setup Automation | `CS16_Mod_Manager.bat` in root workspace + end-to-end launcher test | M3 | DONE |
| M5 | E2E Testing Suite Validation & Adversarial Hardening | Phase 1 (100% pass Tiers 1-4) & Phase 2 (Tier 5 Adversarial Hardening + Audit) | M4 | DONE |
