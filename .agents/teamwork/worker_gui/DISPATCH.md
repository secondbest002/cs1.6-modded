# Dispatch for Worker GUI: CustomTkinter GUI Framework, Dark Slate Theme, and 5 Modular Tabs

## Mandatory Integrity Warning
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

## Mission
Implement the complete modern CustomTkinter Desktop GUI for the Counter-Strike 1.6 Unified Mod Hub in `tools/cs16_mod_hub/gui/` and `tools/cs16_mod_hub/main.py`:
1. Ensure `customtkinter` and `pillow` are installed in the Python environment (run `pip install customtkinter pillow` if needed).
2. `tools/cs16_mod_hub/gui/theme.py`:
   - Dark Slate theme (#1a1e24 main bg, #222831 card bg, #2b303a input bg, #15181c console bg, CS Gold #e5a93c primary accent, Cyan #00adb5 secondary, Orange #ff7043 warn).
   - STRICTLY ZERO EMOJIS anywhere.
   - Clean monochrome Unicode glyphs (`◆`, `◈`, `▸`, `⚙`, `✦`, `⟲`, `✓`, `✕`, `⇄`, `[+]`, `[-]`).
   - Standard font configurations.
3. `tools/cs16_mod_hub/gui/components/`:
   - `card_frame.py`: Dark slate container frame (`#222831`) with optional title header and border.
   - `log_console.py`: Monospace streaming console log viewer with auto-scroll, thread-safe message posting (`widget.after`), clear button, and status indicators.
   - `preview_canvas.py`: Live Pillow preview thumbnail display component for side-by-side or before/after display using `CTkImage`.
4. `tools/cs16_mod_hub/gui/tabs/`:
   - `model_studio_tab.py` (Tab 1: Skin & Model Studio):
     - Weapon viewmodel dropdown (scanned via `list_viewmodels`).
     - Donor skin model picker (scanned via `list_donor_models` or file dialog browse).
     - Glove injector target and source selector.
     - P/W sync toggle switch.
     - Action buttons: "⇄ Transfer Skin", "▸ Inject Gloves", "✦ Bake P/W".
     - Connecting to `model_adapter.py` with real-time log callback streaming to log console.
   - `vibrance_tab.py` (Tab 2: Color & Vibrance Tuner):
     - Weapon selector dropdown.
     - Target group radio/segmented button: `[ Weapon ]`, `[ Gloves ]`, `[ All ]`.
     - Preset buttons: `[ Vivid ]`, `[ Punchy ]`, `[ Soft ]`, `[ Grayscale ]`.
     - Precision sliders: Saturation (0.0 to 2.5), Contrast (0.5 to 2.0), Brightness (0.5 to 1.5) with real-time numerical display.
     - Live side-by-side BMP thumbnail preview canvas showing Original vs Adjusted texture in real time using `palette_preview.TexturePreviewCache` (<2ms response).
     - Action buttons: "✓ Apply Vibrance", "⟲ Factory Palette Reset".
   - `sticker_fx_tab.py` (Tab 3: Sticker FX Lab):
     - Weapon selector dropdown.
     - Sticker slot selector dropdown (scanned via `scan_model_stickers` or "All Stickers").
     - Effect mode buttons/radio: `[ Foil / Chrome (0x42) ]`, `[ Matte (0x40) ]`, `[ Additive Glow (0x60) ]`, `[ Hide Sticker ]`, `[ Restore Sticker ]`.
     - Mode description card explaining visual behavior in GoldSrc engine.
     - Action button: "✓ Apply Sticker FX".
   - `amxx_tab.py` (Tab 4: Plugin & Gameplay Manager):
     - 7 live toggle switches for AMX Mod X plugins:
       1. `team_weapon_skins.amxx` (Per-team weapon skins)
       2. `csgo_knife_sound_manager.amxx` (Knife sound engine)
       3. `csgo_m4_loadout.amxx` (M4A4/M4A1-S loadout switcher)
       4. `csgo_usps_silencer.amxx` (USP-S permanent silencer lock)
       5. `csgo_competitive.amxx` (CS:GO competitive match mod)
       6. `csgo_ammo_refill.amxx` (Auto ammo & round refill)
       7. `bot_savage_ai.amxx` (Bot Savage & Predator AI)
     - Competitive format tuner card:
       - Match format: MR12 (First to 13) vs MR15 (First to 16) segmented button.
       - Knife round toggle switch (`amx_csgo_kniferound`).
       - Warmup Deathmatch toggle switch (`amx_csgo_warmup`).
       - Overtime money selector ($10,000 / $16,000).
       - CS:GO HUD Style toggle switch (`amx_csgo_hud_style`).
       - Damage card & MVP card toggle switches.
     - Action button: "✓ Save Competitive Config".
   - `safety_tab.py` (Tab 5: Backup & Safety Center):
     - Table / scrollable list of all `.bak` backup files with model name, backup size, active size, status (`[ Clean ]` or `[ Modified ]`), and timestamp.
     - Action buttons: "⟲ Restore Selected Model", "⟲ Restore All Models".
     - Confirmation dialog before restoring.
     - Integrated live log output console.
5. `tools/cs16_mod_hub/gui/app.py`:
   - `AppWindow(customtkinter.CTk)`:
     - Geometry: `1100x750`, minimum size `960x650`.
     - Header bar with title "COUNTER-STRIKE 1.6 MOD HUB", tactical subtitle, and status indicators.
     - Modern CustomTkinter `CTkTabview` with the 5 tabs.
     - Bottom status bar showing active game root path and engine status.
6. `tools/cs16_mod_hub/main.py`:
   - CLI arguments: `--console`, `--debug`, `--tab <tab_name>`.
   - Top-level exception handling with `tkinter.messagebox.showerror` fallback if startup fails.
7. Verification Requirements:
   - Run tests:
     - Automated headless GUI test: verify `tools/cs16_mod_hub/main.py` can initialize, build tabs, and destroy cleanly without exceptions (`python -c "import os; os.environ['CI']='1'; from tools.cs16_mod_hub.gui.app import AppWindow; app = AppWindow(); app.update(); app.destroy(); print('GUI INITIALIZES CLEANLY')"`).
     - Static audit: `python -m unittest tests/test_emoji_cleanliness.py` (0 emojis across all new GUI files).
     - Full test runner: `python tests/run_all_tests.py`.
   - Document commands, results, and write `handoff.md`.


## 2026-10-18T05:13:48Z
You are Worker GUI.
Your working directory is:
d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\worker_gui
Authoritative request:
d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\ORIGINAL_REQUEST.md
Project plan:
d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\orchestrator_1\PROJECT.md
Your dispatch instructions:
d:\Games\Counter-Strike\Counter-Strike 1.6 Original\.agents\teamwork\worker_gui\DISPATCH.md

DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A teamwork_preview_auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

Implement the CustomTkinter GUI package under tools/cs16_mod_hub/gui/ and tools/cs16_mod_hub/main.py.
Ensure customtkinter and pillow are installed. Build theme, components, 5 tabs, and main app window.
Run tests and headless GUI validation, verify zero emojis, write handoff.md, and send a message.
