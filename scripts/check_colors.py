from PIL import Image
import numpy as np
from pathlib import Path

preview_dir = Path(r"D:\Games\Counter-Strike\Counter-Strike 1.6 Original\scripts\m4a4_previews")

im_orig = Image.open(preview_dir / "orig_rif_m4a1.png").convert("RGB")
im_tgt = Image.open(preview_dir / "target_rif_m4a1.png").convert("RGB")

print("Orig average color RGB:", np.mean(np.array(im_orig), axis=(0, 1)))
print("Target average color RGB:", np.mean(np.array(im_tgt), axis=(0, 1)))
