---
name: cs16-color-vibrance
description: >-
  Use this skill when the user wants to adjust, boost, or toggle color saturation, contrast,
  and brightness on CS 1.6 weapon models, gloves, or entire viewmodels, with presets and quick resets.
---

# CS 1.6 Color Vibrance & Contrast Enhancer

This skill performs color palette transformations on Counter-Strike 1.6 GoldSrc StudioModels (`v_*.mdl`). It operates directly on the 768-byte RGB palette tables, delivering instant results with **0% loss of detail**, no re-quantization artifacts, and 100% reversible resets.

---

## Command Usage & Parameter Guide

Run the bundled script [adjust_vibrance.py](./scripts/adjust_vibrance.py) via PowerShell:

### 1. Apply Color Presets

```powershell
# Vivid Look: Saturation +35%, Contrast +15% on Weapon Body
python .agents/skills/cs16-color-vibrance/scripts/adjust_vibrance.py -w ak47 -p vivid

# Punchy / High-Contrast Look: Saturation +55%, Contrast +25%
python .agents/skills/cs16-color-vibrance/scripts/adjust_vibrance.py -w ak47 -p punchy

# Soft / Muted Tones
python .agents/skills/cs16-color-vibrance/scripts/adjust_vibrance.py -w ak47 -p soft

# Black & White / Grayscale
python .agents/skills/cs16-color-vibrance/scripts/adjust_vibrance.py -w ak47 -p grayscale
```

---

### 2. Choosing Target Texture Groups (`--target`)

You can target specific elements of the model using `-t`:

```powershell
# Target ONLY weapon body (leaves gloves & stickers untouched) [Default]
python .agents/skills/cs16-color-vibrance/scripts/adjust_vibrance.py -w ak47 -t weapon -p vivid

# Target ONLY gloves and arms
python .agents/skills/cs16-color-vibrance/scripts/adjust_vibrance.py -w ak47 -t gloves -p punchy

# Target EVERYTHING in the viewmodel
python .agents/skills/cs16-color-vibrance/scripts/adjust_vibrance.py -w ak47 -t all -p vivid
```

---

### 3. Custom Precision Sliders

Customize exact multiplier numbers:
```powershell
# Saturation x1.40 (+40%), Contrast x1.20 (+20%), Brightness x1.10 (+10%)
python .agents/skills/cs16-color-vibrance/scripts/adjust_vibrance.py -w ak47 --sat 1.4 --contrast 1.2 --brightness 1.1
```

---

### 4. Resetting Back to Factory Colors (`--reset`)

Restore the original pristine palette anytime:
```powershell
# Reset weapon body colors back to original
python .agents/skills/cs16-color-vibrance/scripts/adjust_vibrance.py -w ak47 -t weapon --reset

# Reset entire model back to original
python .agents/skills/cs16-color-vibrance/scripts/adjust_vibrance.py -w ak47 -t all --reset
```

---

### Parameters Reference:

| Flag | Short | Default | Description |
| :--- | :--- | :--- | :--- |
| `--weapon` | `-w` | *(required)* | Weapon name (e.g. `ak47`, `deagle`, `m4a1`) or full file path |
| `--target` | `-t` | `weapon` | Target group: `weapon`, `gloves`, or `all` |
| `--preset` | `-p` | | Presets: `vivid`, `punchy`, `soft`, `grayscale` |
| `--sat` | | | Saturation multiplier (e.g. `1.3` for +30%) |
| `--contrast` | | | Contrast multiplier (e.g. `1.2` for +20%) |
| `--brightness` | | | Brightness multiplier (e.g. `1.05` for +5%) |
| `--reset` | | | Restores the original factory palette from cache |
| `--dir` | `-d` | `cstrike_hd/models` | Models folder directory |
| `--no-backup` | | | Do not create `.bak` backup file |
