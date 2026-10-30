# cs16-glove-injector Summary
Methodology:
- Transfers glove & arm textures between CS 1.6 viewmodels (v_*.mdl).
- Detects glove/arm textures by name patterns ('sport', 'glove', 'hand', 'arm', 'sleeve').
- Swaps 8-bit indexed pixels + 768-byte palette in-place.
- Preserves weapon geometry, bones, animations, and sound triggers.
- Automatically generates .bak backup.
