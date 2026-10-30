from PIL import Image
from pathlib import Path

preview_dir = Path(r"D:\Games\Counter-Strike\Counter-Strike 1.6 Original\scripts\m4a4_previews")

for name in ["target_1.bmp.png", "target_2.bmp.png", "orig_sticker_1.bmp.png", "orig_sticker_4.bmp.png"]:
    p = preview_dir / name
    if p.exists():
        im = Image.open(p)
        print(f"File {name}: size={im.size}")
