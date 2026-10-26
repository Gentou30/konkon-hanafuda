#!/usr/bin/env python3
"""ボタンとパネルの素材を作る（art/raw/ui_*.png → assets/images/ui/*.png）。

ボタンは朱塗りの1枚から、漆の赤い部分だけ色相を回して色違いを作る（金のふちはそのまま）。
ゲーム側では StyleBoxTexture の9分割で好きな大きさに伸ばす。
"""
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from chroma_key import crop, fit, key  # noqa: E402

ROOT = os.path.join(os.path.dirname(__file__), "..")
OUT = os.path.join(ROOT, "assets", "images", "ui")

# 色違い: 名前 → (色相[0-1], 彩度の倍率, 明るさの倍率)
VARIANTS = {
    "btn_red": None,
    "btn_blue": (0.63, 0.65, 0.7),
    "btn_gray": (0.70, 0.18, 0.75),
    "btn_purple": (0.80, 0.75, 0.85),
    "btn_green": (0.40, 0.7, 0.75),
}


def recolor(img: Image.Image, hue: float, sat: float, val: float) -> Image.Image:
    rgba = np.asarray(img).astype(np.float32)
    hsv = np.asarray(img.convert("RGB").convert("HSV")).astype(np.float32)
    h, s, v = hsv[..., 0] / 255, hsv[..., 1] / 255, hsv[..., 2] / 255
    # 赤い漆（色相が赤寄りで彩度が高い所）だけを塗り替える。金（黄色寄り）は残す
    red = ((h < 0.06) | (h > 0.93)) & (s > 0.35)
    h2 = np.where(red, hue, h)
    s2 = np.where(red, np.clip(s * sat, 0, 1), s)
    v2 = np.where(red, np.clip(v * val, 0, 1), v)
    out = Image.fromarray((np.dstack([h2, s2, v2]) * 255).astype(np.uint8), "HSV").convert("RGB")
    a = Image.fromarray(rgba[..., 3].astype(np.uint8), "L")
    out.putalpha(a)
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    btn = fit(crop(key(Image.open(os.path.join(ROOT, "art/raw/ui_btn_red.png"))), 2), 480)
    for name, var in VARIANTS.items():
        im = btn if var is None else recolor(btn, *var)
        im.save(os.path.join(OUT, name + ".png"))
        print(name, im.size)
    panel = fit(crop(key(Image.open(os.path.join(ROOT, "art/raw/ui_panel.png"))), 2), 600)
    panel.save(os.path.join(OUT, "panel.png"))
    print("panel", panel.size)
    # 細いパネル用：角の金具が小さい版
    small = fit(panel, 340)
    small.save(os.path.join(OUT, "panel_s.png"))
    print("panel_s", small.size)


if __name__ == "__main__":
    main()


def make_fx():
    """背景の上を舞う粒（紅葉・花びら・狐火）"""
    from PIL import ImageDraw, ImageFilter
    s = 64
    # 紅葉：5つの尖った葉
    leaf = Image.new("RGBA", (s, s))
    d = ImageDraw.Draw(leaf)
    c = s / 2
    pts = []
    for i in range(10):
        ang = -np.pi / 2 + i * np.pi / 5
        r = s * (0.46 if i % 2 == 0 else 0.2)
        pts.append((c + r * np.cos(ang), c + r * np.sin(ang)))
    d.polygon(pts, fill=(235, 90, 30, 255))
    d.line([(c, c), (c, s * 0.95)], fill=(160, 50, 20, 255), width=3)
    leaf.filter(ImageFilter.SMOOTH).save(os.path.join(OUT, "fx_leaf.png"))
    # 花びら：先の割れたしずく形
    petal = Image.new("RGBA", (s, s))
    d = ImageDraw.Draw(petal)
    d.ellipse([s * 0.25, s * 0.1, s * 0.75, s * 0.9], fill=(255, 190, 215, 255))
    d.polygon([(c, s * 0.08), (c - 5, 0), (c + 5, 0)], fill=(0, 0, 0, 0))
    d.ellipse([c - 4, s * 0.02, c + 4, s * 0.18], fill=(0, 0, 0, 0))
    petal.filter(ImageFilter.GaussianBlur(0.8)).save(os.path.join(OUT, "fx_petal.png"))
    # 狐火：やわらかい光の玉
    yy, xx = np.mgrid[0:s, 0:s]
    r = np.sqrt((xx - c) ** 2 + (yy - c) ** 2) / c
    a = np.clip(1 - r, 0, 1) ** 2
    rgba = np.dstack([np.full_like(a, 180), np.full_like(a, 150), np.full_like(a, 255), a * 255]).astype(np.uint8)
    Image.fromarray(rgba, "RGBA").save(os.path.join(OUT, "fx_wisp.png"))
    print("fx ok")


if __name__ == "__main__":
    make_fx()
