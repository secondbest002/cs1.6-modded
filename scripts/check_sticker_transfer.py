from PIL import Image
from pathlib import Path
import sys

root = Path(r"D:\Games\Counter-Strike\Counter-Strike 1.6 Original")
sys.path.insert(0, str(root / "scripts"))
from cs16_studio.image_pipeline import quantize_goldsrc

preview_dir = root / "scripts" / "m4a4_previews"
target_stk = Image.open(preview_dir / "target_1.bmp.png")

print(f"Target sticker 1 size: {target_stk.size}")
# Resize to 256x256 for sticker_1.bmp in orig model
resized_stk = target_stk.resize((256, 256), Image.Resampling.LANCZOS)
pix, pal = quantize_goldsrc(resized_stk, is_masked=True, defringe=True)
print(f"Quantized bytes: {len(pix) + len(pal)} (expected {256*256+768})")
