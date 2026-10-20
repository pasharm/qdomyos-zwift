#!/usr/bin/env python3
# Test only (T-084): the brightness of a screenshot, to tell a dark page from a light one.
#   luma.py shot.png
# prints "luma=<0..255> dark|light" for the screen without the status bar and the bottom
# navigation (the top 6% and the bottom 8% of the frame).
import sys
from PIL import Image

img = Image.open(sys.argv[1]).convert("L")
w, h = img.size
body = img.crop((0, int(h * 0.06), w, int(h * 0.92))).resize((w // 8, h // 8))
pixels = body.tobytes()
luma = sum(pixels) / len(pixels)
print("luma=%d %s" % (luma, "dark" if luma < 110 else "light"))
