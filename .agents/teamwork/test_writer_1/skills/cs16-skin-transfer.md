# cs16-skin-transfer Summary
Methodology:
- Transfers weapon body skin from donor model (e.g., v_*_usethis.mdl) into target viewmodel.
- Identifies weapon textures vs non-weapon (excluding gloves, arms, stickers, StatTrak).
- Strictly preserves target model's sequences/animations, sound triggers, bones, gloves, and stickers.
- Supports optional --sync-pw to update third-person (p_) and world (w_) models.
- Generates safety .bak backups.
