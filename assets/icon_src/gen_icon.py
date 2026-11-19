"""Octopus Fragment 图标生成器（定稿）
设计：片段卡片（折角 + 文本行）即章鱼的头，卡片上两只眼睛，
     下方四条触手 —— 「片段」与「章鱼」同体。
输出:
  assets/OctopusFragment.ico        多尺寸 ICO（16/20/24 用简化稿，32+ 用完整稿）
  assets/icons/*.png                各尺寸 PNG
用法: python assets/icon_src/gen_icon.py
依赖: Pillow
"""
import math
import os
from PIL import Image, ImageDraw, ImageFilter

BASE = 1024
SS = 4
S = BASE * SS

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "icons")
os.makedirs(OUT, exist_ok=True)

NAVY_TOP = (30, 86, 118)
NAVY_BOT = (9, 32, 49)
CORAL = (255, 122, 92)
CREAM = (250, 246, 237)
CREAM_DIM = (226, 211, 189)
INK = (9, 32, 49)


def sc(v):
    return v * SS


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def cubic(p0, p1, p2, p3, n=500):
    pts = []
    for i in range(n + 1):
        t = i / n
        u = 1 - t
        x = u**3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t**3 * p3[0]
        y = u**3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t**3 * p3[1]
        pts.append((x, y))
    return pts


def tapered_stroke(draw, pts, w0, w1, color):
    n = len(pts)
    for i, (x, y) in enumerate(pts):
        t = i / (n - 1)
        r = (w0 + (w1 - w0) * t) / 2
        draw.ellipse([x - r, y - r, x + r, y + r], fill=color)


def bg_layer():
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    grad = Image.new("RGBA", (S, S))
    gd = ImageDraw.Draw(grad)
    for y in range(S):
        gd.line([(0, y), (S, y)], fill=lerp(NAVY_TOP, NAVY_BOT, y / (S - 1)) + (255,))
    glow = Image.new("L", (S, S), 0)
    ImageDraw.Draw(glow).ellipse([sc(-140), sc(-600), sc(BASE + 140), sc(400)], fill=44)
    glow = glow.filter(ImageFilter.GaussianBlur(sc(90)))
    grad = Image.composite(Image.new("RGBA", (S, S), (255, 255, 255, 255)), grad, glow)
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=sc(226), fill=255)
    img.paste(grad, (0, 0), mask)
    return img


def snippet_card(img, box, radius, lines, fold=True, flap=CREAM_DIM, line_color=CORAL):
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    x1, y1, x2, y2 = [sc(v) for v in box]
    d.rounded_rectangle([x1, y1, x2, y2], radius=sc(radius), fill=CREAM)
    if fold:
        c = sc(126)
        d.polygon([(x2 - c, y1 - sc(6)), (x2 + sc(6), y1 - sc(6)), (x2 + sc(6), y1 + c)], fill=(0, 0, 0, 0))
        d.polygon([(x2 - c + sc(8), y1 + sc(8)), (x2 - c + sc(8), y1 + c), (x2 - sc(8), y1 + c)], fill=flap)
    for (lx, ly, lw, lh) in lines:
        d.rounded_rectangle([sc(lx), sc(ly), sc(lx + lw), sc(ly + lh)], radius=sc(lh / 2), fill=line_color)
    img.alpha_composite(layer)


def tentacle(img, spec, color=CORAL):
    d = ImageDraw.Draw(img)
    p0, c1, c2, p3, w0, w1 = spec
    pts = cubic(p0, c1, c2, p3, 700)
    tapered_stroke(d, [(sc(x), sc(y)) for x, y in pts], sc(w0), sc(w1), color)


def art(full=True):
    """完整稿：折角卡片 + 2 行文本 + 2 眼(带高光) + 4 触手。
    简化稿(full=False)：无折角 1 行文本 + 大眼睛 + 3 粗触手，供 <=24px。"""
    img = bg_layer()
    if full:
        specs = [
            ((304, 436), (240, 576), (198, 694), (222, 800), 122, 52),
            ((434, 456), (398, 626), (400, 752), (366, 872), 130, 56),
            ((590, 456), (626, 626), (624, 752), (658, 872), 130, 56),
            ((720, 436), (784, 576), (826, 694), (802, 800), 122, 52),
        ]
        for s in specs:
            tentacle(img, s)
        snippet_card(img, box=(200, 92, 824, 466), radius=64,
                     lines=[(274, 170, 372, 46), (274, 242, 300, 46)])
        d = ImageDraw.Draw(img)
        for ex in (406, 618):
            r = sc(38)
            d.ellipse([sc(ex) - r, sc(356) - r, sc(ex) + r, sc(356) + r], fill=INK)
            g = sc(11)
            d.ellipse([sc(ex + 12) - g, sc(340) - g, sc(ex + 12) + g, sc(340) + g], fill=CREAM)
    else:
        specs = [
            ((320, 440), (260, 600), (238, 740), (262, 836), 150, 84),
            ((512, 452), (506, 620), (518, 750), (506, 876), 158, 88),
            ((704, 440), (764, 600), (786, 740), (762, 836), 150, 84),
        ]
        for s in specs:
            tentacle(img, s)
        snippet_card(img, box=(210, 110, 814, 470), radius=60,
                     lines=[(288, 196, 320, 52)], fold=False)
        d = ImageDraw.Draw(img)
        for ex in (420, 604):
            r = sc(48)
            d.ellipse([sc(ex) - r, sc(356) - r, sc(ex) + r, sc(356) + r], fill=INK)
    return img


def save(img_base, name, sizes):
    for s in sizes:
        img_base.resize((s, s), Image.LANCZOS).save(os.path.join(OUT, f"{name}-{s}.png"))


def main():
    full = art(True).resize((BASE, BASE), Image.LANCZOS)
    small = art(False).resize((BASE, BASE), Image.LANCZOS)

    save(full, "octopus", [32, 48, 64, 80, 112, 128, 144, 256, 512, 1024])
    save(small, "octopus-small", [16, 20, 24])

    # 多尺寸 ICO：BMP(DIB) 帧，兼容 LoadImage/TraySetIcon（PNG 帧会加载失败）
    import struct

    ico_path = os.path.join(ROOT, "assets", "OctopusFragment.ico")
    frames = []
    for s in (16, 20, 24):
        frames.append((s, small.resize((s, s), Image.LANCZOS)))
    for s in (32, 40, 48, 64, 128, 256):
        frames.append((s, full.resize((s, s), Image.LANCZOS)))

    def bmp_frame(im):
        w, h = im.size
        px = im.convert("RGBA")
        # XOR：BGRA，自底向上
        xor = b""
        for y in range(h - 1, -1, -1):
            for x in range(w):
                r, g, b, a = px.getpixel((x, y))
                xor += struct.pack("<BBBB", b, g, r, a)
        # AND 掩码：1bpp，自底向上，行按 32 位对齐（32 位图标下全 0，靠 alpha）
        row_bytes = ((w + 31) // 32) * 4
        and_mask = b"\x00" * row_bytes * h
        bih = struct.pack("<IiiHHIIiiII", 40, w, h * 2, 1, 32, 0,
                          len(xor) + len(and_mask), 0, 0, 0, 0)
        return bih + xor + and_mask

    blobs = [bmp_frame(im) for _, im in frames]
    n = len(frames)
    header = struct.pack("<HHH", 0, 1, n)
    directory = b""
    offset = 6 + n * 16
    for (s, _), blob in zip(frames, blobs):
        w = 0 if s >= 256 else s  # 256 记作 0
        directory += struct.pack("<BBBBHHII", w, w, 0, 0, 1, 32, len(blob), offset)
        offset += len(blob)
    with open(ico_path, "wb") as f:
        f.write(header + directory + b"".join(blobs))

    # 实测：Windows LoadImage 能否加载
    import ctypes
    LR_LOADFROMFILE, LR_DEFAULTSIZE, IMAGE_ICON = 0x10, 0x40, 1
    h = ctypes.windll.user32.LoadImageW(0, ico_path, IMAGE_ICON, 0, 0,
                                        LR_LOADFROMFILE | LR_DEFAULTSIZE)
    if h:
        ctypes.windll.user32.DestroyIcon(h)
        print("LoadImage OK ->", ico_path)
    else:
        raise SystemExit("LoadImage FAILED: " + ico_path)

    # 预览图：亮/暗底 + 多尺寸
    sheet = Image.new("RGBA", (1000, 420), (245, 245, 245, 255))
    sheet.paste(Image.new("RGBA", (1000, 210), (34, 38, 44, 255)), (0, 210))
    positions = [(40, 20, 256), (320, 46, 144), (488, 62, 112), (624, 78, 80), (728, 94, 48), (800, 102, 32), (856, 106, 24), (906, 110, 16)]
    for x, y, s in positions:
        im = Image.open(os.path.join(OUT, f"octopus{'-small' if s <= 24 else ''}-{s}.png"))
        sheet.alpha_composite(im, (x, y))
        sheet.alpha_composite(im, (x, y + 210))
    sheet.save(os.path.join(OUT, "_preview.png"))
    print("done ->", ico_path)


if __name__ == "__main__":
    main()
