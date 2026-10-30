from PIL import Image
import numpy as np
from pathlib import Path

preview_dir = Path(r"D:\Games\Counter-Strike\Counter-Strike 1.6 Original\scripts\m4a4_previews")

for p in preview_dir.glob("*.png"):
    img = Image.open(p)
    arr = np.array(img)
    alpha = arr[:, :, 3] if arr.shape[2] == 4 else None
    non_transparent = np.count_nonzero(alpha > 0) if alpha is not None else arr.size
    print(f"{p.name:<26} size: {img.size} non-transparent pixels: {non_transparent}")
