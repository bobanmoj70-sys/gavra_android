"""
Priprema screenshotova iz "production final/ios/slike" za App Store Connect.

Ulaz:  C:\\Users\\Bojan\\Desktop\\production final\\ios\\slike\\*.PNG  (1125x2436, iPhone X/11 Pro)
Izlaz: C:\\Users\\Bojan\\Desktop\\production final\\ios\\slike_appstore\\<velicina>\\*.png

Apple App Store Connect zahtevi (2026):
- iPhone 6.9"/6.7" (Pro Max)  -> 1290 x 2796  (OBAVEZNO za sve iPhone app-ove)
- iPhone 6.5"                  -> 1284 x 2778  (opciono, legacy uređaji)
- iPhone 5.5"                  -> 1242 x 2208  (opciono, legacy uređaji)

Ulazne slike (1125x2436) imaju gotovo identičan aspect ratio kao svi target-i,
pa se samo skaliraju (resize) bez crop-a ili dodavanja margina - nema distorzije.

Pokretanje:
    python prepare_slike.py
"""

from PIL import Image
import glob
import os

SRC_DIR = r"C:\Users\Bojan\Desktop\production final\ios\slike"
IPAD_SRC_DIR = r"C:\Users\Bojan\Desktop\production final\ios\ipad_12.9"
OUT_ROOT = r"C:\Users\Bojan\Desktop\production final\ios\slike_appstore"

# (naziv_foldera, target_width, target_height, obavezno)
TARGETS = [
    ("iphone_6.7", 1290, 2796, True),   # obavezno - iPhone 15/14 Pro Max i noviji
]

# iPad screenshotovi su vec u ispravnoj rezoluciji (2048x2732), samo treba
# ukloniti alfa kanal (RGBA -> RGB) jer App Store Connect to zahteva.
IPAD_TARGET = ("ipad_12.9", 2048, 2732)


def process(path, out_dir, target_w, target_h):
    img = Image.open(path).convert("RGB")
    w, h = img.size

    src_ratio = w / h
    dst_ratio = target_w / target_h

    if abs(src_ratio - dst_ratio) < 0.01:
        # Skoro identičan aspect ratio -> čist resize, bez distorzije
        resized = img.resize((target_w, target_h), Image.LANCZOS)
        canvas = resized
    else:
        # Fallback: contain-fit na canvas iste boje kao vrh slike
        bg_color = img.getpixel((0, 0))
        canvas = Image.new("RGB", (target_w, target_h), bg_color)
        scale = min(target_w / w, target_h / h)
        new_w, new_h = int(w * scale), int(h * scale)
        resized = img.resize((new_w, new_h), Image.LANCZOS)
        x = (target_w - new_w) // 2
        y = (target_h - new_h) // 2
        canvas.paste(resized, (x, y))

    out_name = os.path.splitext(os.path.basename(path))[0].lower() + ".png"
    out_path = os.path.join(out_dir, out_name)
    canvas.save(out_path, "PNG")
    print(f"  -> {out_path}  ({target_w}x{target_h})")


def main():
    files = sorted(glob.glob(os.path.join(SRC_DIR, "*.PNG"))) + sorted(
        glob.glob(os.path.join(SRC_DIR, "*.png"))
    )
    files = sorted(set(files))

    if not files:
        print(f"Nema slika u {SRC_DIR}")
        raise SystemExit(1)

    print(f"Pronadjeno {len(files)} slika u {SRC_DIR}\n")

    for folder_name, tw, th, required in TARGETS:
        tag = "OBAVEZNO" if required else "opciono"
        out_dir = os.path.join(OUT_ROOT, folder_name)
        os.makedirs(out_dir, exist_ok=True)
        print(f"[{tag}] {folder_name} ({tw}x{th}):")
        for path in files:
            process(path, out_dir, tw, th)
        print()

    # iPad slike - vec su u ispravnoj rezoluciji, samo se konvertuju RGBA->RGB
    # i uvek se presnimavaju (overwrite) u izlazni folder.
    ipad_files = sorted(glob.glob(os.path.join(IPAD_SRC_DIR, "*.png"))) + sorted(
        glob.glob(os.path.join(IPAD_SRC_DIR, "*.PNG"))
    )
    ipad_files = sorted(set(ipad_files))

    if ipad_files:
        folder_name, tw, th = IPAD_TARGET
        out_dir = os.path.join(OUT_ROOT, folder_name)
        os.makedirs(out_dir, exist_ok=True)
        print(f"[OBAVEZNO] {folder_name} ({tw}x{th}):")
        for path in ipad_files:
            process(path, out_dir, tw, th)
        print()
    else:
        print(f"Nema iPad slika u {IPAD_SRC_DIR} (preskoceno)\n")

    print("Gotovo. Rezultati u:", OUT_ROOT)
    print("Za App Store Connect: obavezno uploaduj foldere 'iphone_6.7' i 'ipad_12.9'.")


if __name__ == "__main__":
    main()
