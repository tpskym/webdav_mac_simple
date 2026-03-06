#!/usr/bin/env python3
"""Делает белый фон PNG прозрачным и сохраняет квадрат 1024x1024."""
import sys
from pathlib import Path

from PIL import Image

def main():
    src = Path(__file__).resolve().parent.parent / "assets" / "webdav-icon-1024.png"
    out = src  # перезапись

    im = Image.open(src).convert("RGBA")
    w, h = im.size

    # Квадрат по меньшей стороне, центр
    size = min(w, h)
    left = (w - size) // 2
    top = (h - size) // 2
    im = im.crop((left, top, left + size, top + size))
    im = im.resize((1024, 1024), Image.Resampling.LANCZOS)

    # Белый и почти белый -> прозрачный (порог 250)
    data = list(im.get_flattened_data() if hasattr(im, "get_flattened_data") else im.getdata())
    new_data = []
    for r, g, b, a in data:
        if r >= 250 and g >= 250 and b >= 250:
            new_data.append((255, 255, 255, 0))
        else:
            new_data.append((r, g, b, a))
    im.putdata(new_data)

    im.save(out, "PNG")
    print("Сохранено:", out)

if __name__ == "__main__":
    main()
