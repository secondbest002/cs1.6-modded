# Original User Request

## Initial Request — 2026-10-18T03:57:43Z

A unified desktop GUI manager for Counter-Strike 1.6 built with CustomTkinter, featuring a modern dark-slate aesthetic with clean minimalist glyphs (no emojis), integrating model skin transfer, glove injection, sticker FX flags, palette color vibrance/contrast tuning, and AMX Mod X plugin/competitive gameplay configuration.

Working directory: d:\Games\Counter-Strike\Counter-Strike 1.6 Original
Integrity mode: development

## Requirements

### R1. Backend Core Adapters
- Build unified Python adapter modules in tools/cs16_mod_hub/core/ that wrap and orchestrate the existing verified scripts from .agents/skills/ without code breakage:
  - adjust_vibrance.py (Color saturation, contrast, brightness, presets, target weapon/gloves/all, palette reset).
  - inject_gloves.py (In-place glove/arm texture injection with .bak backup).
  - toggle_sticker_fx.py (Sticker flags: Chrome/Foil 0x42, Matte 0x40, Glow 0x60, Hide/Restore).
  - transfer_weapon_skin.py (Skin transfer preserving animations, gloves, StatTrak, with optional P & W sync).
  - bake_and_inject_pw.py (Composites decals/stickers and bakes to p_*.mdl and w_*.mdl).
  - AMXX adapter to toggle plugins in cstrike/addons/amxmodx/configs/plugins.ini and edit competitive CVARs in csgo_competitive.cfg.

### R2. Modern Desktop GUI Architecture (CustomTkinter)
- Implement a multi-tab desktop application using customtkinter with modular tab views:
  1. Skin & Model Studio: Weapon selector, source donor skin selector, glove injector, and P/W sync toggle.
  2. Color & Vibrance Tuner: Precision sliders (Saturation, Contrast, Brightness), presets (Vivid, Punchy, Soft, Grayscale), factory palette reset, and a real-time live BMP preview thumbnail using Pillow.
  3. Sticker FX Lab: Per-weapon sticker slot selector, effect toggles (Foil/Chrome, Matte, Glow, Hide, Restore).
  4. Plugin & Gameplay Manager: Live toggle switches for AMX Mod X plugins (team_weapon_skins, csgo_knife_sound_manager, csgo_m4_loadout, csgo_usps_silencer, csgo_competitive, csgo_ammo_refill, bot_savage_ai), plus competitive mode tuner (MR12/MR15, overtime, warmup).
  5. Backup & Safety Center: One-click restore for .bak model files and a live log output console.

### R3. Visual Aesthetics & Design Standard
- Modern CS:GO/CS2 Dark Slate UI theme (dark slate grey #1a1e24, card background #222831, accent gold/cyan/orange).
- Strictly NO colorful or childish emojis (no colorful emojis).
- Use clean typographic layout and subtle minimalist monochrome glyphs (e.g. ◆, ◈, ▸, ⚙, ✦, ⟲, ✓, ✕, ⇄, [+], [-]) for an authentic, premium gaming utility feel.

### R4. Launcher & Setup Automation
- Provide CS16_Mod_Manager.bat in the game root that auto-checks/installs customtkinter if missing and launches tools/cs16_mod_hub/main.py.

---

## Acceptance Criteria

### Adapter & Engine Verification
- [ ] Automated import test passes for all adapter modules (model_adapter.py, amxx_adapter.py, palette_preview.py).
- [ ] Safe non-destructive operation verified: all model operations produce .bak safety backups.
- [ ] AMXX configuration parser correctly comments/uncomments plugin lines with ; without corrupting other entries.

### GUI & Usability Verification
- [ ] Application window launches with CustomTkinter dark theme, proper dimensions, and responsive layout.
- [ ] Zero emojis in UI labels, buttons, or window titles; glyphs and clean typography are verified throughout.
- [ ] Live palette preview displays the weapon texture bitmap before and after applying vibrance adjustments.
- [ ] Batch script CS16_Mod_Manager.bat successfully launches the application from root directory.
