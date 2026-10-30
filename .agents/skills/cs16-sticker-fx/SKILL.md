---
name: cs16-sticker-fx
description: >-
  Use this skill when the user wants to toggle, switch, or customize sticker visual effects
  (such as Chrome/Foil metallic shine, flat Matte, glow, or temporarily hiding stickers) on CS 1.6 viewmodels.
---

# CS 1.6 Sticker Effects Controller

This skill controls the visual rendering flags and visibility of weapon stickers/decals in Counter-Strike 1.6 GoldSrc StudioModels (`v_*.mdl`).

---

## Supported Sticker Effects

| Mode | Flag | Description |
| :--- | :--- | :--- |
| `foil` / `chrome` | `0x42` | **Foil / Holo Metallic Gleam**: Reflects light and moves dynamically based on view angle. |
| `matte` | `0x40` | **Matte Finish**: Classic flat cutout sticker without reflections. |
| `glow` | `0x60` | **Additive Glow**: Shines brightly in dark hallways/shadows. |
| `hide` | `0x40` + Alpha | **Hidden**: Completely hides the sticker from the gun without removing the 3D mesh. |
| `restore` | `0x40` | **Restore**: Restores previously hidden stickers back to their original texture. |

---

## Detailed Command Usage

Run the bundled script [toggle_sticker_fx.py](./scripts/toggle_sticker_fx.py) via PowerShell:

### 1. Make All Stickers Shiny Foil / Chrome
```powershell
python .agents/skills/cs16-sticker-fx/scripts/toggle_sticker_fx.py -w ak47 -m foil
```

### 2. Switch Stickers Back to Matte (Flat Decal)
```powershell
python .agents/skills/cs16-sticker-fx/scripts/toggle_sticker_fx.py -w ak47 -m matte
```

### 3. Temporarily Hide Stickers from the Gun
```powershell
python .agents/skills/cs16-sticker-fx/scripts/toggle_sticker_fx.py -w ak47 -m hide
```

### 4. Restore Hidden Stickers
```powershell
python .agents/skills/cs16-sticker-fx/scripts/toggle_sticker_fx.py -w ak47 -m restore
```

### 5. Target a Specific Sticker Slot
```powershell
# Only change sticker 1 to Foil
python .agents/skills/cs16-sticker-fx/scripts/toggle_sticker_fx.py -w ak47 -m foil --sticker-id 1
```

### Parameters Reference:
* `-w`, `--weapon`: Weapon name (e.g. `ak47`, `deagle`, `m4a1`) or full file path.
* `-m`, `--mode`: Effect mode (`foil`, `chrome`, `matte`, `glow`, `hide`, `restore`).
* `-d`, `--dir`: Directory where models are located (default: `cstrike_hd/models`).
* `--sticker-id`: `all` (default) or slot number `1`, `2`, `3`, `4`.
* `--no-backup`: Skip creating a `.bak` backup file.
