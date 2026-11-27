"""Quantizes the persona PNGs to 256-colour palettes (flat art, no visible loss)."""
import glob, os
from PIL import Image
d = os.path.join(os.path.dirname(__file__), '../../apps/mobile/assets/personas')
for f in glob.glob(os.path.join(d, '*.png')):
    im = Image.open(f).convert('RGBA')
    im.quantize(colors=256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE).save(f, optimize=True)
