from PIL import Image
from pathlib import Path

preview_dir = Path(r"D:\Games\Counter-Strike\Counter-Strike 1.6 Original\scripts\m4a4_previews")

for name in ["target_1.bmp.png", "target_rif_m4a1.png", "orig_rif_m4a1.png"]:
    p = preview_dir / name
    if p.exists():
        im = Image.open(p)
        print(f"{name}: mode={im.mode}, size={im.size}, bbox={im.getbbox()}")
