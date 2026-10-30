# cs16-sticker-fx Summary
Methodology:
- Modifies GoldSrc StudioModel texture rendering flags in mstudiotexture_t:
  * Foil / Chrome (0x42): STUDIO_NF_CHROME (0x02) | STUDIO_NF_MASKED (0x40)
  * Matte (0x40): STUDIO_NF_MASKED (0x40)
  * Glow (0x60): STUDIO_NF_ADDITIVE (0x20) | STUDIO_NF_MASKED (0x40)
  * Hide: backs up raw pixels to .sticker_backups/ and fills pixels with 0xFF (transparent key)
  * Restore: recovers raw pixels from .sticker_backups/ and sets flags back to 0x40
- Creates .bak file backup before modifying.
