# cs16-color-vibrance Summary
Methodology:
- Adjust color vibrance, saturation, contrast, and brightness on GoldSrc model palettes (v_*.mdl).
- Operates directly on the 768-byte RGB palette tables located at texture header idx + w * h.
- Preserves transparent key color (index 255) when texture is masked (flags & 0x40 != 0).
- Supports presets (vivid, punchy, soft, grayscale) and custom float multipliers (sat, contrast, brightness).
- Caches initial pristine palette in .original_palettes.dat for factory reset.
- Non-destructive: creates .bak backup unless --no-backup.
