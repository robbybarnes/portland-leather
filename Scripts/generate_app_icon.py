#!/usr/bin/env python3
# Generates the 1024px app icon: a cream serif "L" monogram on a cognac
# field. No SF Symbols, no PLG imagery.
from PIL import Image, ImageDraw, ImageFont
import os

pixels = 1024
bg_color = (0x8A, 0x4B, 0x2A)       # Cognac #8A4B2A
text_color = (0xF7, 0xF2, 0xE9)     # Cream #F7F2E9

img = Image.new("RGB", (pixels, pixels), color=bg_color)
draw = ImageDraw.Draw(img)

font_path = "/System/Library/Fonts/Supplemental/Georgia.ttf"
if not os.path.exists(font_path):
    font_path = "/System/Library/Fonts/Times.ttc"

try:
    font = ImageFont.truetype(font_path, 640)
except Exception:
    font = ImageFont.load_default()

text = "L"
bbox = draw.textbbox((0, 0), text, font=font)
w = bbox[2] - bbox[0]
h = bbox[3] - bbox[1]

x = (pixels - w) / 2 - bbox[0]
y = (pixels - h) / 2 - bbox[1]

draw.text((x, y), text, fill=text_color, font=font)

out_dir = "Leatherfolio/Resources/Assets.xcassets/AppIcon.appiconset"
os.makedirs(out_dir, exist_ok=True)
out_path = os.path.join(out_dir, "AppIcon.png")
img.save(out_path, "PNG")
print(f"Wrote {out_path} ({os.path.getsize(out_path)} bytes)")
