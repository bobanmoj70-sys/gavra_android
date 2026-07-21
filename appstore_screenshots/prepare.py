"""
Priprema screenshotova za App Store Connect.

Ulaz:  appstore_screenshots/raw/*.jpg  (screenshotovi iz Android app-a)
Izlaz: appstore_screenshots/ios_6.7/*.png  (spremno za upload, rezolucija 1290x2796 - iPhone 6.7")

Strategija:
- Svaki screenshot se centrira i uklapa (contain-fit) na iOS 6.7" canvas.
- Ako slika ima drugačiji aspect ratio od iOS ekrana, dodaju se blage margine
  (boja se uzima sa vrha slike, tako da se ne vidi "traka" već blago produžena pozadina).
- Opcionalno: CROP_TOP_PX možeš podesiti ako želiš da odsečeš Android status bar
  sa vrha PRE skaliranja (u pikselima, na originalnoj slici).

Pokretanje:
    python prepare.py
"""

from PIL import Image
import glob
import os

RAW_DIR = os.path.join(os.path.dirname(__file__), "raw")

# Ako želiš da odsečeš gornju traku (Android status bar) sa originalne slike
# pre obrade, postavi broj piksela ovde (na originalnoj rezoluciji, ne target).
CROP_TOP_PX = 0
CROP_BOTTOM_PX = 0  # isto, za donju navigacionu traku ako postoji

# Svaki tuple: (naziv_foldera, target_width, target_height)
TARGETS = [
    ("ios_6.7", 1290, 2796),   # iPhone 6.7" (15/14 Pro Max) - obavezno
    ("ipad_12.9", 2048, 2732),  # iPad Pro 12.9" - obavezno za universal app
]


def process(path, out_dir, target_w, target_h):
    img = Image.open(path).convert("RGB")
    w, h = img.size

    if CROP_TOP_PX or CROP_BOTTOM_PX:
        img = img.crop((0, CROP_TOP_PX, w, h - CROP_BOTTOM_PX))
        w, h = img.size

    bg_color = img.getpixel((0, 0))
    canvas = Image.new("RGB", (target_w, target_h), bg_color)

    # Contain-fit: skaliraj tako da cela slika stane unutar target dimenzija
    scale = min(target_w / w, target_h / h)
    new_w, new_h = int(w * scale), int(h * scale)
    resized = img.resize((new_w, new_h), Image.LANCZOS)

    x = (target_w - new_w) // 2
    y = (target_h - new_h) // 2
    canvas.paste(resized, (x, y))

    out_name = os.path.splitext(os.path.basename(path))[0] + ".png"
    out_path = os.path.join(out_dir, out_name)
    canvas.save(out_path, "PNG")
    print(f"Sacuvano: {out_path}  ({target_w}x{target_h})")


files = sorted(glob.glob(os.path.join(RAW_DIR, "*.jpg"))) + sorted(
    glob.glob(os.path.join(RAW_DIR, "*.png"))
)

if not files:
    print(f"Nema slika u {RAW_DIR}")
    raise SystemExit(1)

for folder_name, tw, th in TARGETS:
    out_dir = os.path.join(os.path.dirname(__file__), folder_name)
    os.makedirs(out_dir, exist_ok=True)
    for path in files:
        process(path, out_dir, tw, th)

print("\nGotovo. Provjeri foldere:", ", ".join(f[0] for f in TARGETS))
