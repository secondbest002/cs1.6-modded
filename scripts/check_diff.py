from PIL import Image
import numpy as np
from pathlib import Path

preview_dir = Path(r"D:\Games\Counter-Strike\Counter-Strike 1.6 Original\scripts\m4a4_previews")

im_orig = Image.open(preview_dir / "orig_rif_m4a1.png")
im_tgt = Image.open(preview_dir / "target_rif_m4a1.png")

diff = np.abs(np.array(im_orig, dtype=np.int16) - np.array(im_tgt, dtype=np.int16))
print("Max diff between orig and target rif_m4a1:", np.max(diff))
print("Mean diff:", np.mean(diff))
