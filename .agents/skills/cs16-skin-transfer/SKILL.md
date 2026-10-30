---
name: cs16-skin-transfer
description: >-
  Use this skill when the user wants to transfer or swap a weapon skin texture from a donor/collection
  viewmodel to a target viewmodel while preserving custom animations (recoil, reload, inspect), gloves,
  stickers, and StatTrak modules, with optional synchronization to p/w models.
---

# CS 1.6 Weapon Skin Transfer

This skill transfers the core weapon body skin from a donor/collection model (such as `v_*_usethis.mdl`) into an active viewmodel while strictly **preserving**:
* Custom firing and recoil animations (`shoot1`, `shoot2`, `shoot3`).
* Custom inspect, reload, and draw sequences.
* Active gloves and arm textures (e.g. Sport Gloves).
* Existing stickers (automatically excludes foreign stickers like Crown Foil from the donor).
* StatTrak modules and counter digits.

---

## Command Usage & Parameter Guide

Run the bundled script [transfer_weapon_skin.py](./scripts/transfer_weapon_skin.py) via PowerShell:

### 1. Basic Transfer (Viewmodel Only)
```powershell
python .agents/skills/cs16-skin-transfer/scripts/transfer_weapon_skin.py -s "cstrike_hd/models/v_ak47_usethis.mdl" -t ak47
```

### 2. Full Transfer with Automatic P & W Synchronization
Updates the first-person viewmodel, third-person player model (`p_*.mdl`), and world dropped model (`w_*.mdl`) all in one command:
```powershell
python .agents/skills/cs16-skin-transfer/scripts/transfer_weapon_skin.py -s "v_ak47_usethis.mdl" -t ak47 --sync-pw
```

### 3. Parameters Reference
| Flag | Short | Description | Example |
| :--- | :--- | :--- | :--- |
| `--source` | `-s` | Path or name of the donor/collection model | `-s v_ak47_usethis.mdl` |
| `--target` | `-t` | Name of the active target weapon or model path | `-t ak47` |
| `--dir` | `-d` | Default models directory (default: `cstrike_hd/models`) | `-d cstrike/models` |
| `--sync-pw` | | Also inject the new skin into corresponding `p_` and `w_` models | `--sync-pw` |
| `--no-backup` | | Skip creating `.bak` backup files | `--no-backup` |
