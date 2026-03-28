from __future__ import annotations

import argparse
import collections
import json
import math
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Extract representative HEX shades from an image gradient."
    )
    parser.add_argument("image", type=Path, help="Path to input image")
    parser.add_argument(
        "--samples",
        type=int,
        default=7,
        help="How many shades to return (default: 7)",
    )
    parser.add_argument(
        "--axis",
        choices=["vertical", "horizontal", "diagonal", "auto"],
        default="auto",
        help="Gradient axis. Default auto-detect based on variation.",
    )
    parser.add_argument(
        "--band",
        type=float,
        default=0.35,
        help="Center band width ratio used for sampling (0.05-1.0, default: 0.35)",
    )
    parser.add_argument(
        "--trim",
        type=float,
        default=0.08,
        help="Trim ratio from gradient ends to avoid borders (0.0-0.4, default: 0.08)",
    )
    parser.add_argument(
        "--json-out",
        type=Path,
        default=None,
        help="Optional path to write JSON output",
    )
    parser.add_argument(
        "--method",
        choices=["median", "mean", "dominant"],
        default="median",
        help="Color aggregation method (default: median)",
    )
    return parser.parse_args()


def clamp(value: float, lower: float, upper: float) -> float:
    return max(lower, min(upper, value))


def rgb_to_hex(rgb: tuple[int, int, int]) -> str:
    return "#{:02X}{:02X}{:02X}".format(*rgb)


def load_pixels(image_path: Path):
    try:
        from PIL import Image
    except Exception as error:  # pragma: no cover - runtime dependency guard
        raise RuntimeError(
            "Pillow nije instaliran. Pokreni: pip install pillow"
        ) from error

    image = Image.open(image_path).convert("RGB")
    width, height = image.size
    pixels = image.load()
    return image, pixels, width, height


def luminance(rgb: tuple[int, int, int]) -> float:
    red, green, blue = rgb
    return 0.2126 * red + 0.7152 * green + 0.0722 * blue


def channel_variation(pixels, width: int, height: int, axis: str) -> float:
    values: list[float] = []
    if axis == "vertical":
        for y in range(height):
            values.append(luminance(pixels[width // 2, y]))
    else:
        for x in range(width):
            values.append(luminance(pixels[x, height // 2]))

    if not values:
        return 0.0

    mean = sum(values) / len(values)
    variance = sum((value - mean) ** 2 for value in values) / len(values)
    return math.sqrt(variance)


def detect_axis(pixels, width: int, height: int, axis: str) -> str:
    if axis != "auto":
        return axis

    vertical_variation = channel_variation(pixels, width, height, "vertical")
    horizontal_variation = channel_variation(pixels, width, height, "horizontal")

    return "vertical" if vertical_variation >= horizontal_variation else "horizontal"


def sample_along_axis(
    pixels,
    width: int,
    height: int,
    axis: str,
    sample_count: int,
    band_ratio: float,
    trim_ratio: float,
    method: str,
) -> list[tuple[int, int, int]]:
    sample_count = max(2, sample_count)
    band_ratio = clamp(band_ratio, 0.05, 1.0)
    trim_ratio = clamp(trim_ratio, 0.0, 0.4)
    colors: list[tuple[int, int, int]] = []

    def dominant_color(samples: list[tuple[int, int, int]]) -> tuple[int, int, int]:
        if not samples:
            return (0, 0, 0)
        counter: collections.Counter[tuple[int, int, int]] = collections.Counter()
        for red, green, blue in samples:
            key = (red // 16, green // 16, blue // 16)
            counter[key] += 1
        bucket, _ = counter.most_common(1)[0]
        return tuple(min(255, channel * 16 + 8) for channel in bucket)

    def median_color(samples: list[tuple[int, int, int]]) -> tuple[int, int, int]:
        if not samples:
            return (0, 0, 0)
        rs = sorted(value[0] for value in samples)
        gs = sorted(value[1] for value in samples)
        bs = sorted(value[2] for value in samples)
        middle = len(samples) // 2
        return (rs[middle], gs[middle], bs[middle])

    def mean_color(samples: list[tuple[int, int, int]]) -> tuple[int, int, int]:
        if not samples:
            return (0, 0, 0)
        count = len(samples)
        red = sum(value[0] for value in samples) // count
        green = sum(value[1] for value in samples) // count
        blue = sum(value[2] for value in samples) // count
        return (red, green, blue)

    def aggregate(samples: list[tuple[int, int, int]]) -> tuple[int, int, int]:
        if method == "dominant":
            return dominant_color(samples)
        if method == "mean":
            return mean_color(samples)
        return median_color(samples)

    if axis == "vertical":
        top = int((height - 1) * trim_ratio)
        bottom = int((height - 1) * (1.0 - trim_ratio))
        if bottom <= top:
            top, bottom = 0, height - 1

        band_width = max(1, int(width * band_ratio))
        x_start = max(0, (width - band_width) // 2)
        x_end = min(width, x_start + band_width)
        for index in range(sample_count):
            y = int(round(top + index * (bottom - top) / (sample_count - 1)))
            y0 = max(0, y - 2)
            y1 = min(height, y + 3)
            window_samples: list[tuple[int, int, int]] = []
            for x in range(x_start, x_end):
                for y_sample in range(y0, y1):
                    window_samples.append(pixels[x, y_sample])
            colors.append(aggregate(window_samples))
    else:
        if axis == "horizontal":
            left = int((width - 1) * trim_ratio)
            right = int((width - 1) * (1.0 - trim_ratio))
            if right <= left:
                left, right = 0, width - 1

            band_height = max(1, int(height * band_ratio))
            y_start = max(0, (height - band_height) // 2)
            y_end = min(height, y_start + band_height)
            for index in range(sample_count):
                x = int(round(left + index * (right - left) / (sample_count - 1)))
                x0 = max(0, x - 2)
                x1 = min(width, x + 3)
                window_samples: list[tuple[int, int, int]] = []
                for y in range(y_start, y_end):
                    for x_sample in range(x0, x1):
                        window_samples.append(pixels[x_sample, y])
                colors.append(aggregate(window_samples))
        else:
            start = trim_ratio
            end = 1.0 - trim_ratio
            if end <= start:
                start, end = 0.0, 1.0
            band_half = max(1, int(min(width, height) * band_ratio * 0.08))
            for index in range(sample_count):
                t = start + (end - start) * (index / (sample_count - 1))
                center_x = int(round((width - 1) * t))
                center_y = int(round((height - 1) * t))
                window_samples: list[tuple[int, int, int]] = []
                for dx in range(-band_half, band_half + 1):
                    for dy in range(-band_half, band_half + 1):
                        x = min(width - 1, max(0, center_x + dx))
                        y = min(height - 1, max(0, center_y + dy))
                        window_samples.append(pixels[x, y])
                colors.append(aggregate(window_samples))

    return colors


def main() -> int:
    args = parse_args()

    if not args.image.exists():
        print(f"Greška: fajl ne postoji: {args.image}")
        return 2

    try:
        _, pixels, width, height = load_pixels(args.image)
    except RuntimeError as error:
        print(str(error))
        return 3

    axis = detect_axis(pixels, width, height, args.axis)
    sampled_colors = sample_along_axis(
        pixels=pixels,
        width=width,
        height=height,
        axis=axis,
        sample_count=args.samples,
        band_ratio=args.band,
        trim_ratio=args.trim,
        method=args.method,
    )

    hex_colors = [rgb_to_hex(color) for color in sampled_colors]

    payload = {
        "image": str(args.image),
        "axis": axis,
        "samples": args.samples,
        "hex": hex_colors,
    }

    print(f"Axis: {axis}")
    print("HEX nijanse:")
    for index, color in enumerate(hex_colors, start=1):
        print(f"{index:02d}. {color}")

    if args.json_out is not None:
        args.json_out.parent.mkdir(parents=True, exist_ok=True)
        args.json_out.write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")
        print(f"Sačuvano: {args.json_out}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())