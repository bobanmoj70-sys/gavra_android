from __future__ import annotations

import argparse
import math
import re
from pathlib import Path
from typing import Dict, List, Tuple

RGB = Tuple[int, int, int]


def hex_to_rgb(hex_value: str) -> RGB:
    hex_value = hex_value.strip().lstrip("#")
    if len(hex_value) != 6:
        raise ValueError(f"Nevalidan HEX: {hex_value}")
    return (int(hex_value[0:2], 16), int(hex_value[2:4], 16), int(hex_value[4:6], 16))


def rgb_to_hex(rgb: RGB) -> str:
    return "#{:02X}{:02X}{:02X}".format(*rgb)


def parse_registry_gradients(registry_text: str) -> Dict[str, str]:
    pattern = re.compile(
        r"'(?P<id>[a-z0-9_]+)'\s*:\s*V2ThemeDefinition\(.*?gradient:\s*(?P<gradient>[A-Za-z0-9_]+)",
        re.DOTALL,
    )
    result: Dict[str, str] = {}
    for match in pattern.finditer(registry_text):
        result[match.group("id")] = match.group("gradient")
    return result


def parse_gradients(theme_text: str) -> Dict[str, List[RGB]]:
    block_pattern = re.compile(
        r"(?:const|final)\s+LinearGradient\s+(?P<name>[A-Za-z0-9_]+)\s*=\s*LinearGradient\((?P<body>.*?)\);",
        re.DOTALL,
    )
    color_pattern = re.compile(r"Color\(0xFF([0-9A-Fa-f]{6})\)")

    gradients: Dict[str, List[RGB]] = {}
    for block in block_pattern.finditer(theme_text):
        name = block.group("name")
        body = block.group("body")
        colors = [hex_to_rgb(code) for code in color_pattern.findall(body)]
        if colors:
            gradients[name] = colors
    return gradients


def interpolate(colors: List[RGB], steps: int = 16) -> List[RGB]:
    if len(colors) == 1:
        return [colors[0]] * steps

    sampled: List[RGB] = []
    last_idx = len(colors) - 1
    for i in range(steps):
        t = i / (steps - 1)
        position = t * last_idx
        left = int(math.floor(position))
        right = min(last_idx, left + 1)
        frac = position - left
        lr, lg, lb = colors[left]
        rr, rg, rb = colors[right]
        r = round(lr + (rr - lr) * frac)
        g = round(lg + (rg - lg) * frac)
        b = round(lb + (rb - lb) * frac)
        sampled.append((r, g, b))
    return sampled


def gradient_distance(a: List[RGB], b: List[RGB], steps: int = 24) -> float:
    aa = interpolate(a, steps=steps)
    bb = interpolate(b, steps=steps)

    total = 0.0
    for (ar, ag, ab), (br, bg, bb_) in zip(aa, bb):
        dr = ar - br
        dg = ag - bg
        db = ab - bb_
        total += dr * dr + dg * dg + db * db

    mean_sq = total / steps
    return math.sqrt(mean_sq)


def average_color(colors: List[RGB]) -> RGB:
    n = len(colors)
    rs = sum(c[0] for c in colors)
    gs = sum(c[1] for c in colors)
    bs = sum(c[2] for c in colors)
    return (round(rs / n), round(gs / n), round(bs / n))


def print_palette(theme_id: str, colors: List[RGB]) -> None:
    hex_colors = ", ".join(rgb_to_hex(c) for c in colors)
    avg = rgb_to_hex(average_color(colors))
    print(f"- {theme_id:<20} avg={avg} colors=[{hex_colors}]")


def print_distance_matrix(theme_gradients: Dict[str, List[RGB]]) -> None:
    ids = list(theme_gradients.keys())
    print("\nMatrica distanci (manje = sličnije):")
    header = "".ljust(18) + " ".join(i[:12].ljust(12) for i in ids)
    print(header)
    for row in ids:
        row_values = []
        for col in ids:
            value = gradient_distance(theme_gradients[row], theme_gradients[col])
            row_values.append(f"{value:>10.1f}  ")
        print(row[:18].ljust(18) + "".join(row_values))


def print_nearest(theme_gradients: Dict[str, List[RGB]]) -> None:
    ids = list(theme_gradients.keys())
    print("\nNajbliže teme:")
    for current in ids:
        others = []
        for other in ids:
            if other == current:
                continue
            dist = gradient_distance(theme_gradients[current], theme_gradients[other])
            others.append((dist, other))
        others.sort(key=lambda item: item[0])
        if others:
            best_dist, best_theme = others[0]
            print(f"- {current:<20} -> {best_theme:<20} (dist={best_dist:.1f})")


def main() -> int:
    parser = argparse.ArgumentParser(description="Poređenje gradijenata svih registrovanih tema.")
    parser.add_argument("--theme", default="lib/theme.dart", help="Putanja do theme.dart")
    parser.add_argument("--registry", default="lib/services/v2_theme_registry.dart", help="Putanja do registry fajla")
    args = parser.parse_args()

    theme_path = Path(args.theme)
    registry_path = Path(args.registry)

    if not theme_path.exists() or not registry_path.exists():
        print("Greška: theme.dart ili v2_theme_registry.dart ne postoji.")
        return 2

    theme_text = theme_path.read_text(encoding="utf-8")
    registry_text = registry_path.read_text(encoding="utf-8")

    registry_gradients = parse_registry_gradients(registry_text)
    gradient_defs = parse_gradients(theme_text)

    if not registry_gradients:
        print("Nema tema u registry-ju.")
        return 3

    theme_gradients: Dict[str, List[RGB]] = {}
    missing = []
    for theme_id, gradient_name in registry_gradients.items():
        colors = gradient_defs.get(gradient_name)
        if colors is None:
            missing.append((theme_id, gradient_name))
            continue
        theme_gradients[theme_id] = colors

    if missing:
        print("Upozorenje: nisu pronađeni gradijenti za:")
        for theme_id, gradient_name in missing:
            print(f"- {theme_id} -> {gradient_name}")

    if len(theme_gradients) < 2:
        print("Nedovoljno tema za poređenje.")
        return 4

    print("Gradijenti po temama:")
    for theme_id, colors in theme_gradients.items():
        print_palette(theme_id, colors)

    print_distance_matrix(theme_gradients)
    print_nearest(theme_gradients)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
