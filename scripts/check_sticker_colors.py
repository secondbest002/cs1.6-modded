from PIL import Image
from pathlib import Path

p = Path(r"D:\Games\Counter-Strike\Counter-Strike 1.6 Original\scripts\m4a4_previews\target_1.bmp.png")
im = Image.open(p)
print("target_1.bmp.png format:", im.format, im.size, im.mode)
# Find dominant colors
colors = sorted(im.getcolors(maxcolors=262144) or [], key=lambda x: x[0], reverse=True)
print("Top 5 colors (count, RGBA):")
for c in colors[:5]:
    print(" ", c)
