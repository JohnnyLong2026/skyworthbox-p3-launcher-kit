# -*- coding: utf-8 -*-
"""
One white mark, used everywhere:
  - res/drawable/ic_alarm.xml     vector, white, any size (settings header, footer, reminder)
  - res/mipmap-*/ic_launcher.png  dark rounded tile with the mark
  - res/drawable-nodpi/banner.png 16:9 tile: mark + "定时启动", nothing else
  - res/drawable-xxhdpi/ic_alarm_notify.png  white silhouette for the notification

Geometry is defined once (mark_geometry) and emitted three ways, so the vector and the
bitmaps are literally the same drawing.
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = os.path.join(ROOT, "TVAutoStart", "app", "src", "main", "res")
OUT = os.path.join(ROOT, "logo-concepts")
os.makedirs(OUT, exist_ok=True)

WHITE = (255, 255, 255, 255)
FONT_BOLD = "C:/Windows/Fonts/msyhbd.ttc"

# ----------------------------------------------------------------- geometry, in units of a square of side S centred on (0, 0)
RING_R = 0.300      # ring centre-line radius
RING_W = 0.060      # ring stroke
TICK_W = 0.040
TICK_A, TICK_B = 0.222, 0.268          # tick runs inward from the ring
TICK_ANGLES = (270.0, 0.0, 90.0, 180.0)  # 12, 3, 6, 9 (screen degrees: 0 = +x, y down)
ARROW_A = -42.0                        # up-right, wholly inside the dial
SHAFT_W = 0.062
SHAFT_END = 0.168
HEAD_BASE = 0.160
HEAD_HALF = 0.080
HEAD_TIP = 0.244


def pol(r, deg):
    a = math.radians(deg)
    return r * math.cos(a), r * math.sin(a)


def mark_geometry(cx, cy, S):
    """Returns (lines, triangle) in absolute pixels: lines = [(p0, p1, width)]."""
    lines = []
    for d in TICK_ANGLES:
        p0 = pol(TICK_A * S, d)
        p1 = pol(TICK_B * S, d)
        lines.append(((cx + p0[0], cy + p0[1]), (cx + p1[0], cy + p1[1]), TICK_W * S))

    shaft = pol(SHAFT_END * S, ARROW_A)
    lines.append(((cx, cy), (cx + shaft[0], cy + shaft[1]), SHAFT_W * S))

    ar = math.radians(ARROW_A)
    ux, uy = math.cos(ar), math.sin(ar)
    px_, py_ = -uy, ux
    bc = (cx + ux * HEAD_BASE * S, cy + uy * HEAD_BASE * S)
    tri = [
        (cx + ux * HEAD_TIP * S, cy + uy * HEAD_TIP * S),
        (bc[0] + px_ * HEAD_HALF * S, bc[1] + py_ * HEAD_HALF * S),
        (bc[0] - px_ * HEAD_HALF * S, bc[1] - py_ * HEAD_HALF * S),
    ]
    return lines, tri, (RING_R * S, RING_W * S)


def draw_mark(img, cx, cy, S, color=WHITE):
    d = ImageDraw.Draw(img)
    lines, tri, (rr, rw) = mark_geometry(cx, cy, S)
    for p0, p1, w in lines:
        d.line([p0, p1], fill=color, width=int(round(w)))
        for p in (p0, p1):
            d.ellipse([p[0] - w / 2, p[1] - w / 2, p[0] + w / 2, p[1] + w / 2], fill=color)
    d.polygon(tri, fill=color)
    # ring last, so the shaft's rounded start hides under it
    d.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], outline=color, width=int(round(rw)))
    return img


# ----------------------------------------------------------------- vector drawable
def vector_xml(size=48):
    cx = cy = size / 2.0
    lines, tri, (rr, rw) = mark_geometry(cx, cy, size)
    p = []
    p.append('<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
             '    android:width="48dp"\n    android:height="48dp"\n'
             '    android:viewportWidth="48"\n    android:viewportHeight="48">')

    def n(v):
        return ("%.3f" % v).rstrip("0").rstrip(".")

    # ring
    p.append('    <path\n        android:pathData="M%s,%s A%s,%s 0 0,1 %s,%s A%s,%s 0 0,1 %s,%s"\n'
             '        android:strokeColor="#FFFFFFFF"\n        android:strokeWidth="%s"\n'
             '        android:fillColor="#00000000" />'
             % (n(cx - rr), n(cy), n(rr), n(rr), n(cx + rr), n(cy),
                n(rr), n(rr), n(cx - rr), n(cy), n(rw)))
    # ticks + shaft
    for (x0, y0), (x1, y1), w in lines:
        p.append('    <path\n        android:pathData="M%s,%s L%s,%s"\n'
                 '        android:strokeColor="#FFFFFFFF"\n        android:strokeWidth="%s"\n'
                 '        android:strokeLineCap="round"\n        android:fillColor="#00000000" />'
                 % (n(x0), n(y0), n(x1), n(y1), n(w)))
    # arrow head
    p.append('    <path\n        android:pathData="M%s,%s L%s,%s L%s,%s Z"\n'
             '        android:fillColor="#FFFFFFFF" />'
             % (n(tri[0][0]), n(tri[0][1]), n(tri[1][0]), n(tri[1][1]), n(tri[2][0]), n(tri[2][1])))
    p.append('</vector>')
    return "\n".join(p) + "\n"


# ----------------------------------------------------------------- bitmaps
def tile(px, mark_frac=0.80, radius_frac=0.235, bg=True):
    S = px * 4
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    if bg:
        g = Image.new("RGB", (16, 16))
        gd = ImageDraw.Draw(g)
        for y in range(16):
            t = y / 15
            gd.line([(0, y), (16, y)], fill=(int(32 - 14 * t), int(32 - 14 * t), int(36 - 15 * t)))
        plate = g.resize((S, S), Image.BICUBIC).convert("RGBA")
        mask = Image.new("L", (S, S), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=int(S * radius_frac), fill=255)
        img = Image.composite(plate, img, mask)
    m = int(S * mark_frac)
    layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    draw_mark(layer, S / 2, S / 2, m)
    img = Image.alpha_composite(img, layer)
    return img.resize((px, px), Image.LANCZOS)


def banner_art(w=1280, h=720):
    """Design at 1280x720 then 2x downscale to 640x360."""
    K = 2
    W, H = w * K, h * K
    img = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(img)
    for y in range(H):
        t = y / (H - 1)
        d.line([(0, y), (W, y)], fill=(int(26 - 14 * t), int(26 - 16 * t), int(30 - 18 * t)))
    # soft light behind the mark
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([100, 120, 900, 1200], fill=(255, 255, 255, 16))
    img = Image.alpha_composite(img.convert("RGBA"), glow.filter(ImageFilter.GaussianBlur(0.12 * W)))

    mark_px = int(0.62 * H)
    gap = int(0.050 * W)
    target_text = int(0.80 * W) - mark_px - gap
    probe = ImageDraw.Draw(img)
    size = max(24, int(target_text / 4.0))
    for _ in range(24):
        font = ImageFont.truetype(FONT_BOLD, size)
        tw = probe.textlength("定时启动", font=font)
        if abs(tw - target_text) <= 4:
            break
        size = max(24, int(size * target_text / tw))

    group = mark_px + gap + tw
    x0 = (W - group) / 2
    draw_mark(img, x0 + mark_px / 2, H / 2, mark_px)
    d = ImageDraw.Draw(img)
    d.text((x0 + mark_px + gap, H / 2), "定时启动", font=font,
           fill=(255, 255, 255), anchor="lm")
    return img.convert("RGB").resize((w, h), Image.LANCZOS)


# ----------------------------------------------------------------- write everything
def main():
    with open(os.path.join(RES, "drawable", "ic_alarm.xml"), "w", encoding="utf-8") as f:
        f.write(vector_xml(48))

    sizes = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}
    for folder, px in sizes.items():
        tile(px).save(os.path.join(RES, "mipmap-%s" % folder, "ic_launcher.png"))

    banner_art().save(os.path.join(RES, "drawable-nodpi", "banner.png"))

    sil = Image.new("RGBA", (384, 384), (0, 0, 0, 0))
    draw_mark(sil, 192, 192, 300)
    sil.resize((96, 96), Image.LANCZOS).save(
        os.path.join(RES, "drawable-xxhdpi", "ic_alarm_notify.png"))

    # preview sheet
    tile(1024).save(os.path.join(OUT, "white-icon-1024.png"))
    banner_art().save(os.path.join(OUT, "white-banner.png"))
    print("written")


if __name__ == "__main__":
    main()
