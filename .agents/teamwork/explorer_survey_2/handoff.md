# Handoff Report: Counter-Strike 1.6 Filesystem Layout & AMX Mod X Configuration Survey

## 1. Observation

### 1.1 Target Directories and Game Filesystem Layout
We directly examined the game filesystem structure rooted at `d:\Games\Counter-Strike\Counter-Strike 1.6 Original`:

1. **`cstrike/models/`** (14 subdirectories, 162 files):
   - Active weapon viewmodels: 31 files matching `v_*.mdl` (e.g., `v_ak47.mdl` [1,509,940 bytes], `v_m4a1.mdl` [2,944,364 bytes], `v_awp.mdl` [315,892 bytes], `v_deagle.mdl` [1,935,352 bytes], `v_usp.mdl` [3,554,732 bytes], `v_knife.mdl` [1,806,936 bytes]).
   - Active player models: 31 files matching `p_*.mdl` (e.g., `p_ak47.mdl` [39,244 bytes], `p_m4a1.mdl` [23,372 bytes], `p_awp.mdl` [23,356 bytes]).
   - Active world models: 32 files matching `w_*.mdl` (e.g., `w_ak47.mdl` [37,636 bytes], `w_m4a1.mdl` [21,820 bytes], `w_awp.mdl` [21,716 bytes]).
   - Equipment and grenade models: `v_c4.mdl`, `v_flashbang.mdl`, `v_hegrenade.mdl`, `v_smokegrenade.mdl`, `v_shield_r.mdl`, `p_shield.mdl`, `w_shield.mdl`.

2. **`cstrike/models/custom_skins/`**:
   - Configured specifically for the custom AMX Mod X plugin `team_weapon_skins.amxx`.
   - `ct/` (65 files): Contains 31 CT custom viewmodels (`v_*.mdl`), 31 `.bak` safety backup files, plus `v_knife_m9.mdl` [1,798,888 bytes] and `v_ak47_usethis_sleeve.mdl` [1,586,116 bytes].
   - `t/` (33 files): Contains 30 Terrorist custom viewmodels (`v_*.mdl`), 3 `.bak` files, plus `v_knife_butterfly.mdl` [1,536,060 bytes].
   - Documentation in directory:
     - `CARA_PASANG_CUSTOM_SKIN.txt`: Confirms custom skins are loaded per-team by `team_weapon_skins.amxx`, falling back to `csgo_skins/` if empty or missing.
     - `README_KNIFE_SOUNDS.md`: Documents dynamic knife naming conventions (`v_knife_<knife_type>.mdl`, e.g. `ct/v_knife_m9.mdl`, `t/v_knife_butterfly.mdl`, `v_knife_karambit.mdl`, etc.), integrated with `csgo_knife_sound_manager.amxx`.

3. **`cstrike/models/csgo_skins/`**:
   - `ct/` (32 files): CS:GO style viewmodels with CT gloves/sleeves, plus `p_m4a4.mdl` [582,660 bytes] and `w_m4a4.mdl` [581,016 bytes].
   - `t/` (29 files): CS:GO style viewmodels with Terrorist gloves/sleeves.
   - Acts as the automatic fallback collection if a weapon model is not present in `custom_skins/`.

4. **`CSGO Weapon Pack - Update #4/`** (Root directory donor collection):
   - `cstrike/models/` (89 files): Complete donor weapon pack with `p_*`, `w_*`, and `v_*` models.
   - `cstrike/models/alt/` (29 files): Alternative skin viewmodels (e.g. `alt/v_ak47.mdl` [4,215,396 bytes]).
   - Serves as the primary external donor library for `transfer_weapon_skin.py` and `inject_gloves.py`.

5. **`cstrike_hd/models/`** (101 files):
   - High-definition model pack containing 32 `v_*.mdl`, 33 `p_*.mdl`, 33 `w_*.mdl`.
   - Existing backups: 11 `.bak` files (e.g., `v_ak47.mdl.bak`, `p_ak47.mdl.bak`, `w_ak47.mdl.bak`).
   - Palette caches: 4 `.original_palettes.dat` files (e.g., `v_ak47.mdl.original_palettes.dat` [7,928 bytes]).
   - Sticker backups: `.sticker_backups/` directory for hidden raw texture pixels.

---

### 1.2 Inspection of `cstrike/addons/amxmodx/configs/plugins.ini`
- **Location**: `d:\Games\Counter-Strike\Counter-Strike 1.6 Original\cstrike\addons\amxmodx\configs\plugins.ini`
- **Size**: 52 lines, 2,269 bytes.
- **Structure**:
  - Lines 1-42: Core AMX Mod X plugins (Admin base, Menus, Chat, Maps, Stats, Configuration).
  - Lines 44-51: Verbatim quote of custom 3rd party plugins section:
```ini
; Custom - Add 3rd party plugins here
team_weapon_skins.amxx	; Per-team weapon skin switcher (CT vs T viewmodels)
csgo_knife_sound_manager.amxx	; Smart knife sound engine (Auto-detects knife & plays deploy/inspect/stab sounds)
csgo_m4_loadout.amxx	; CS:GO M4A4 & M4A1-S Loadout Switcher (CT Loadout & Silencer Control)
csgo_usps_silencer.amxx	; CS:GO USP-S Permanent Silencer Lock (Auto-silence & blocks detaching)
csgo_competitive.amxx	; CS:GO Competitive Match Mod (MR12, Warmup, Knife, Timeout, Damage)
csgo_ammo_refill.amxx	; CS:GO/CS2 Auto Ammo & Round Refill (Free ammo on buy & instant clip reset)
bot_savage_ai.amxx		; Bot Savage & Predator AI Engine (Counter-strafe, Jiggle, Trade-frag, Anti-flash)
```
- **Syntax and Formatting**:
  - The AMX Mod X comment character is `;`.
  - Leading `;` comments out and disables a plugin (e.g., `;admin_sql.amxx`, `;telemenu.amxx`).
  - Active plugins are written as `<filename.amxx>\t; <description>`.
  - Blank lines and pure comment lines (e.g. `; Menus`, `; Map related`) are present throughout the file and must be preserved verbatim.
  - All 7 custom plugins in Requirement R2.4 are already present and active at lines 45–51.

---

### 1.3 Inspection of `cstrike/addons/amxmodx/configs/csgo_competitive.cfg`
- **Location**: `d:\Games\Counter-Strike\Counter-Strike 1.6 Original\cstrike\addons\amxmodx\configs\csgo_competitive.cfg`
- **Size**: 89 lines, 3,626 bytes.
- **Execution Mechanism**: Verified in `cstrike/addons/amxmodx/scripting/csgo_competitive.sma` lines 194–205:
```pawn
public plugin_cfg()
{
    new config_file[128];
    get_configsdir(config_file, charsmax(config_file));
    format(config_file, charsmax(config_file), "%s/csgo_competitive.cfg", config_file);

    if (file_exists(config_file))
    {
        server_cmd("exec %s", config_file);
        server_exec();
    }
    g_MaxRoundsHalf = get_pcvar_num(pCvar_MaxRounds);
    if (g_MaxRoundsHalf < 1) g_MaxRoundsHalf = 12;
    g_TargetWinScore = g_MaxRoundsHalf + 1;
    ResetToWarmup();
}
```
`csgo_competitive.cfg` is executed automatically at map initialization by `csgo_competitive.amxx`.

- **Documented CVAR Inventory**:

| Category | CVAR Name | Current Value | Allowed Values / Description |
|---|---|---|---|
| Match Master | `amx_csgo_mode` | `1` | `1` = Enabled, `0` = Disabled |
| Match Format | `amx_csgo_maxrounds` | `12` | `12` = MR12 (First to 13 wins), `15` = MR15 (First to 16 wins) |
| Knife Round | `amx_csgo_kniferound` | `1` | `1` = Knife round for side pick, `0` = Direct live match |
| Warmup | `amx_csgo_warmup` | `1` | `1` = Warmup Deathmatch ($16k), `0` = No warmup |
| Timeouts | `amx_csgo_timeouts` | `1` | Quota of `.timeout` per team per half |
| Timeout Duration | `amx_csgo_timeout_duration` | `60` | Duration in seconds (default CS:GO = 60s) |
| Overtime Money | `amx_csgo_ot_money` | `10000` | Starting money in Overtime ($10,000 or $16,000) |
| YaPB Bot Ready | `amx_csgo_bot_autoready` | `1` | `1` = YaPB bots auto ready when human types `.ready` |
| Loss Bonus | `amx_csgo_lossbonus` | `1` | `1` = CS:GO ladder ($1400-$3400), `0` = CS 1.6 classic reset |
| HUD Style | `amx_csgo_hud_style` | `1` | `1` = Modern CS:GO Top Header, `0` = Classic |
| MVP Card | `amx_csgo_mvp_card` | `1` | `1` = Center screen gold DHUD card, `0` = Chat only |
| C4 Timer HUD | `amx_csgo_c4_timer` | `1` | `1` = Real-time C4 countdown in top bar, `0` = Off |
| Screen Transitions | `amx_csgo_screenfade` | `1` | `1` = Fade to black on halftime / tint on victory |
| Combat Damage | `amx_csgo_dmg_card` | `1` | `1` = On-screen combat summary card, `0` = Console only |
| Server Roundtime | `mp_roundtime` | `1.92` | 1 min 55 sec standard round time |
| Server C4 Timer | `mp_c4timer` | `40` | 40 seconds competitive bomb timer |
| Server Freezetime| `mp_freezetime` | `5` | 5 seconds freeze buy period |
| Server Buytime | `mp_buytime` | `0.25` | 15 seconds buy period |
| Server Startmoney| `mp_startmoney` | `800` | $800 pistol round cash |
| Server Balance | `mp_autoteambalance`| `0` | Prevent engine from auto-shuffling competitive teams |
| Server Team Limit| `mp_limitteams` | `0` | Unrestricted team sizes |
| Server FF | `mp_friendlyfire` | `1` | Friendly fire enabled |
| Server TK Punish | `mp_tkpunish` | `0` | Do not kick players/bots for accidental team damage |

- **Other AMXX Custom Plugin CVAR Locations**:
  - `cstrike/addons/amxmodx/configs/amxx.cfg`:
    - `csgo_ammo_refill.amxx`: `amx_csgo_ammo 1`, `amx_csgo_ammo_on_buy 1`, `amx_csgo_ammo_round_start 1`, `amx_csgo_ammo_instant_clip 1`, `amx_csgo_ammo_block_cmds 1`.
    - `csgo_m4_loadout.amxx`: `amx_m4_loadout 1`, `amx_m4_default 0`, `amx_m4_block_silencer 1`, `amx_m4_auto_silence 1`, `amx_m4_notify 1`.
    - `csgo_usps_silencer.amxx`: `amx_usps_lock 1`, `amx_usps_ct_only 0`, `amx_usps_block_secondary 1`, `amx_usps_auto_silence 1`.
    - `bot_savage_ai.amxx`: `bot_savage_enable 1`, `bot_savage_counterstrafe 1`, `bot_savage_jiggle 1`, `bot_savage_tradefrag 1`, `bot_savage_antiflash 1`, `bot_savage_triggerbot 1`, `bot_savage_hivemind 1`, `bot_savage_reloadcover 1`, `bot_savage_recoil 1`, `bot_savage_bhop 1`, `bot_savage_wallbang 1`, `bot_savage_doublepeek 1`, `bot_savage_fakedefuse 1`, `bot_savage_jumpscout 1`, `bot_savage_dropguns 1`.

---

### 1.4 Backup Conventions & Inventory in Model Directories
We discovered a total of **45 `.bak` files** currently present in the filesystem:
1. `cstrike/models/custom_skins/ct/` (31 `.bak` files):
   - Every primary weapon model has an existing `.bak` backup file (e.g., `v_ak47.mdl.bak` [1,901,536 bytes], `v_m4a1.mdl.bak` [1,851,736 bytes], `v_awp.mdl.bak` [2,792,008 bytes], `v_deagle.mdl.bak` [1,873,348 bytes], `v_knife.mdl.bak` [1,511,364 bytes]).
2. `cstrike/models/custom_skins/t/` (3 `.bak` files):
   - `v_ak47.mdl.bak` [2,098,164 bytes], `v_deagle.mdl.bak` [2,553,576 bytes], `v_m4a1.mdl.bak` [2,944,364 bytes].
3. `cstrike/models/` (1 `.bak` file):
   - `v_ak47.mdl.bak` [1,509,940 bytes].
4. `cstrike_hd/models/` (10 `.bak` files):
   - `v_ak47.mdl.bak`, `v_deagle.mdl.bak`, `v_m4a1.mdl.bak`, `p_ak47.mdl.bak`, `p_deagle.mdl.bak`, `p_m4a1.mdl.bak`, `w_ak47.mdl.bak`, `w_deagle.mdl.bak`, `w_m4a1.mdl.bak`.

**Backup Creation Logic in Verified Scripts**:
All existing scripts (`adjust_vibrance.py`, `inject_gloves.py`, `toggle_sticker_fx.py`, `transfer_weapon_skin.py`, `bake_and_inject_pw.py`) strictly enforce the **Never-Overwrite Backup Principle**:
```python
bak_path = target_path + ".bak"
if not os.path.exists(bak_path):
    shutil.copy2(target_path, bak_path)
```
This guarantees that the `.bak` file always preserves the pristine original state prior to any modification.

**Companion Backup Artifacts**:
- Palette Caches (`.original_palettes.dat`): Pickle files storing `{texture_name: 768_byte_palette}` dictionary for factory palette reset.
- Sticker Raw Dumps (`.sticker_backups/*.raw`): Raw pixel binary buffers stored before sticker hiding to enable 100% pixel-perfect restore.

---

## 2. Logic Chain

1. **Filesystem Organization Logic**:
   - The game utilizes multiple layer directories: `cstrike/models/` for base assets, `custom_skins/` for per-team custom choices, `csgo_skins/` as team defaults, and `cstrike_hd/models/` for HD weapon replacements.
   - The GUI model selector must allow selecting from the active weapon pool (`cstrike/models/` or `custom_skins/` or `cstrike_hd/models/`) and browsing donor models from `CSGO Weapon Pack - Update #4/` or any custom path.
   - For knife models, naming format `v_knife_<type>.mdl` in `custom_skins/ct` and `custom_skins/t` is required by `team_weapon_skins.amxx` and `csgo_knife_sound_manager.amxx` to trigger appropriate inspect/deploy sounds.

2. **AMXX Plugin Management Logic**:
   - AMX Mod X parses `plugins.ini` line-by-line upon map loading. If a line begins with `;`, AMXX treats it as a comment and skips loading the plugin.
   - An adapter module `amxx_adapter.py` must provide high-level methods (`get_plugin_status(name)`, `set_plugin_status(name, enabled)`).
   - Because `plugins.ini` contains human-readable section comments and spacing, modifying the file by full rewrite or stripping comments will destroy the file's structure.
   - Therefore, the parser must read lines as structured tokens, modify only the prefix of the matching plugin line, and preserve all other lines, comments, and spacing unaltered.

3. **Competitive Configuration Logic**:
   - `csgo_competitive.amxx` directly reads and executes `cstrike/addons/amxmodx/configs/csgo_competitive.cfg` via `server_cmd("exec ...")`.
   - Modifying CVARs like `amx_csgo_maxrounds` between `12` (MR12) and `15` (MR15) or toggling `amx_csgo_warmup` in `csgo_competitive.cfg` provides immediate configuration persistence for future game sessions.
   - The CVAR parser in `amxx_adapter.py` must support regex-based value replacement: `^(\s*<cvar>\s+)[^\s/]+(.*)$` -> `\g<1><new_val>\g<2>`, preserving inline comments (`// comment`).

4. **Safety & Backup Center Logic**:
   - Since 45 `.bak` files already exist across model folders, users need a central management view to:
     1. Inspect all backups across `cstrike/models/`, `custom_skins/`, and `cstrike_hd/models/`.
     2. Compare timestamp and file size between the `.mdl` and `.bak`.
     3. Restore individual files or restore all files with a single click (`shutil.copy2(bak, mdl)`).
     4. Verify that restored files have valid GoldSrc header (`b'IDST'` version `10`) prior to overwriting.

---

## 3. Caveats

1. **AMXX Hot-Reloading vs Server Restart**:
   - Changes written to `plugins.ini` and `csgo_competitive.cfg` take effect when a new map loads or when the server starts. If Counter-Strike 1.6 is currently actively running in a match, AMXX does not hot-reload `plugins.ini` until the map changes or `restart` is executed in the console.
2. **Case Sensitivity**:
   - While Windows paths are case-insensitive, AMXX plugin names and GoldSrc model paths are strictly case-matched in Linux environments. All adapter operations should maintain clean lowercase conventions (`v_ak47.mdl`, `team_weapon_skins.amxx`).
3. **Backup File Protection**:
   - When a user performs a "Restore from Backup" action, the active `.mdl` is restored from `.bak`. The `.bak` file should NOT be deleted upon restore, allowing repeated rollbacks.
4. **Third-Party Anti-Virus / Permissions**:
   - Files in `cstrike/addons/amxmodx/configs/` can sometimes be locked if the dedicated server process (`hlds.exe` or `hl.exe`) holds an exclusive read handle. Atomic replacement (`tempfile` + `os.replace`) ensures file writing will not truncate or corrupt configurations.

---

## 4. Conclusion & Recommended Architecture for `amxx_adapter.py`

### 4.1 Recommended Interface for `amxx_adapter.py`
The backend adapter should be placed at `tools/cs16_mod_hub/core/amxx_adapter.py`:

```python
"""
tools/cs16_mod_hub/core/amxx_adapter.py
Safely query, toggle, and configure AMX Mod X plugins and competitive CVARs.
"""

from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional
import os
import re
import shutil
import tempfile

@dataclass
class PluginInfo:
    name: str
    enabled: bool
    description: str
    line_number: int

@dataclass
class BackupItem:
    target_path: Path
    backup_path: Path
    backup_size: int
    target_size: int
    is_modified: bool

class AmxxAdapter:
    def __init__(self, game_root: Path):
        self.game_root = Path(game_root).resolve()
        self.plugins_ini = self.game_root / "cstrike" / "addons" / "amxmodx" / "configs" / "plugins.ini"
        self.competitive_cfg = self.game_root / "cstrike" / "addons" / "amxmodx" / "configs" / "csgo_competitive.cfg"
        self.amxx_cfg = self.game_root / "cstrike" / "addons" / "amxmodx" / "configs" / "amxx.cfg"

    # --- plugins.ini Operations ---
    def get_plugin_status(self, plugin_name: str) -> Optional[bool]:
        """Returns True if plugin is enabled, False if commented with ;, None if not found."""
        ...

    def set_plugin_status(self, plugin_name: str, enabled: bool) -> bool:
        """Enables or disables plugin in plugins.ini, preserving all comments and ordering."""
        ...

    def list_custom_plugins(self) -> Dict[str, PluginInfo]:
        """Lists known custom plugins (team_weapon_skins, csgo_competitive, etc.) with status."""
        ...

    # --- csgo_competitive.cfg Operations ---
    def get_cvar(self, cvar_name: str) -> Optional[str]:
        """Reads CVAR value from csgo_competitive.cfg."""
        ...

    def set_cvar(self, cvar_name: str, value: str) -> bool:
        """Updates CVAR value in csgo_competitive.cfg, preserving formatting and inline comments."""
        ...

    def get_competitive_settings(self) -> Dict[str, str]:
        """Retrieves structured dictionary of all competitive settings (MR, warmup, overtime, HUD)."""
        ...

    def set_competitive_settings(self, settings: Dict[str, str]) -> bool:
        """Batch updates competitive settings."""
        ...

    # --- Backup & Safety Center ---
    def scan_backups(self) -> List[BackupItem]:
        """Scans cstrike/models, custom_skins, and cstrike_hd for .bak files."""
        ...

    def restore_backup(self, backup_item: BackupItem) -> bool:
        """Restores a model from its .bak file after validating GoldSrc IDST header."""
        ...

    def restore_all_backups(self) -> int:
        """Restores all discovered .bak files. Returns count of restored models."""
        ...
```

### 4.2 Safe Line-Based Parsing Implementation Strategy
1. **Comment Token Recognition**:
   - To disable: If line matches `^(\s*)([a-zA-Z0-9_\-]+\.amxx)(.*)$`, replace with `\g<1>; \g<2>\g<3>`.
   - To enable: If line matches `^(\s*);\s*([a-zA-Z0-9_\-]+\.amxx)(.*)$`, replace with `\g<1>\g<2>\g<3>`.
2. **Safe Atomic File Writing**:
   - Never use direct truncation `open(f, 'w')`. Always write to `NamedTemporaryFile(dir=target_dir, delete=False)`, flush/sync, and use `os.replace(temp_path, target_path)`.
   - Ensure an initial backup `plugins.ini.bak` and `csgo_competitive.cfg.bak` is generated if it does not already exist.

---

## 5. Verification Method

### 5.1 Independent Verification Commands
Any agent or engineer can independently verify the filesystem and configuration observations using Python:

```bash
# 1. Verify existence and lines of plugins.ini
python -c "p = r'cstrike/addons/amxmodx/configs/plugins.ini'; lines = open(p).readlines(); print('Total lines:', len(lines)); print('Custom plugins:', [l.strip() for l in lines[43:52]])"

# 2. Verify csgo_competitive.cfg CVARs
python -c "p = r'cstrike/addons/amxmodx/configs/csgo_competitive.cfg'; text = open(p).read(); import re; cvars = re.findall(r'^(amx_\w+|mp_\w+)\s+([^\s/]+)', text, re.M); print('Parsed CVAR count:', len(cvars)); print(dict(cvars[:6]))"

# 3. Verify .bak files count
python -c "import pathlib; baks = list(pathlib.Path('cstrike').rglob('*.bak')); print('Found .bak count in cstrike:', len(baks))"

# 4. Verify GoldSrc header on backup models
python -c "import struct; b = open('cstrike/models/custom_skins/ct/v_ak47.mdl.bak', 'rb').read(8); magic, ver = struct.unpack('<4sI', b); assert magic == b'IDST' and ver == 10, 'Invalid GoldSrc header'; print('GoldSrc IDST header OK')"
```

### 5.2 Invalidation Conditions
This survey report would be invalidated if:
1. `plugins.ini` is moved or replaced with an alternative file (e.g. `plugins-custom.ini`).
2. GoldSrc engine model header specification changes from `IDST` ver 10.
3. The custom plugins listed in lines 45–51 are deleted or renamed.
