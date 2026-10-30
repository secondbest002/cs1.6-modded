# cs16-pw-injector Summary
Methodology:
- Extracts base weapon texture from viewmodel (v_*.mdl).
- Bakes decal layers and stickers over base texture using Pillow compositing.
- Quantizes to 256 colors with 8-bit palette.
- Automatically creates .bak backups of p_*.mdl and w_*.mdl.
- Injects updated texture bytes into p_*.mdl and w_*.mdl.
