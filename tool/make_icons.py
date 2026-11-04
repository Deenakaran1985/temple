"""Draws the Temple Alarm logo and writes every Android / iOS / macOS icon size."""
import os, sys
from PIL import Image, ImageDraw, ImageFilter

APP = sys.argv[1]
S = 1024 * 4  # supersampled canvas
AMBER_TOP, AMBER_BOT = (245, 158, 11), (180, 83, 9)
DARK = (124, 45, 18)
WHITE = (255, 255, 255, 255)


def u(v):  # unit (0..1 of the 1024 design grid) -> supersampled px
    return v * S


def gradient(size):
    g = Image.new("RGBA", (size, size))
    d = ImageDraw.Draw(g)
    for y in range(size):
        t = y / (size - 1)
        c = tuple(round(a + (b - a) * t) for a, b in zip(AMBER_TOP, AMBER_BOT))
        d.line([(0, y), (size, y)], fill=c + (255,))
    return g


def glyph(scale=1.0, cut=(0, 0, 0, 0)):
    """White temple gopuram with a bell in the doorway, centred, on transparent.
    scale shrinks it about the centre (adaptive icons need a safe zone)."""
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx = 0.5

    def P(x, y):
        return (u(cx + (x - cx) * scale), u(0.5 + (y - 0.5) * scale))

    # kalasam (finial) on top
    d.polygon([P(0.5, 0.13), P(0.485, 0.19), P(0.515, 0.19)], fill=WHITE)
    d.ellipse([*P(0.47, 0.18), *P(0.53, 0.235)], fill=WHITE)
    # tiers: (top y, bottom y, half-width top, half-width bottom)
    tiers = [(0.235, 0.33, 0.11, 0.15), (0.34, 0.45, 0.16, 0.205),
             (0.46, 0.58, 0.215, 0.26)]
    for y0, y1, w0, w1 in tiers:
        d.polygon([P(cx - w0, y0), P(cx + w0, y0), P(cx + w1, y1), P(cx - w1, y1)], fill=WHITE)
    # base hall
    d.rectangle([*P(0.22, 0.59), *P(0.78, 0.82)], fill=WHITE)
    d.rectangle([*P(0.18, 0.82), *P(0.82, 0.87)], fill=WHITE)
    # doorway (arched) cut out
    d.rectangle([*P(0.405, 0.67), *P(0.595, 0.82)], fill=cut)
    d.ellipse([*P(0.405, 0.6), *P(0.595, 0.74)], fill=cut)
    # bell inside the doorway
    d.rectangle([*P(0.494, 0.625), *P(0.506, 0.65)], fill=WHITE)
    d.chord([*P(0.45, 0.645), *P(0.55, 0.745)], 180, 360, fill=WHITE)
    d.rectangle([*P(0.45, 0.693), *P(0.55, 0.765)], fill=WHITE)
    d.polygon([P(0.45, 0.765), P(0.55, 0.765), P(0.565, 0.785), P(0.435, 0.785)], fill=WHITE)
    d.ellipse([*P(0.485, 0.783), *P(0.515, 0.81)], fill=WHITE)
    # alarm "ring" arcs either side of the finial
    w = int(u(0.018 * scale))
    for r in (0.07, 0.115):
        d.arc([*P(0.5 - r - 0.03, 0.2 - r), *P(0.5 + r + 0.03, 0.2 + r)], 200, 250, fill=WHITE, width=w)
        d.arc([*P(0.5 - r - 0.03, 0.2 - r), *P(0.5 + r + 0.03, 0.2 + r)], 290, 340, fill=WHITE, width=w)
    return img


def shadowed(g):
    sh = Image.new("RGBA", g.size, DARK + (0,))
    sh.putalpha(g.getchannel("A").point(lambda a: a * 0.35))
    sh = sh.filter(ImageFilter.GaussianBlur(S * 0.008))
    out = Image.new("RGBA", g.size, (0, 0, 0, 0))
    out.alpha_composite(sh, (0, int(S * 0.012)))
    out.alpha_composite(g)
    return out


def rounded_mask(radius_frac):
    m = Image.new("L", (S, S), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, S - 1, S - 1], radius=int(S * radius_frac), fill=255)
    return m


bg = gradient(S)
full = bg.copy()
full.alpha_composite(shadowed(glyph(0.86)))
full_rgb = full.convert("RGB")                       # iOS: square, opaque
legacy = Image.new("RGBA", (S, S), (0, 0, 0, 0))     # Android < 8: rounded square
legacy.paste(full, (0, 0), rounded_mask(0.22))
round_ = Image.new("RGBA", (S, S), (0, 0, 0, 0))
cm = Image.new("L", (S, S), 0)
ImageDraw.Draw(cm).ellipse([0, 0, S - 1, S - 1], fill=255)
round_.paste(full, (0, 0), cm)
fg = shadowed(glyph(0.6))                            # adaptive foreground (66% safe zone)
mono = glyph(0.86)                                   # notification: white on transparent
mono_fg = glyph(0.6)                                 # themed icon (Android 13+)


def save(img, path, px):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.resize((px, px), Image.LANCZOS).save(path, optimize=True)


res = os.path.join(APP, "android/app/src/main/res")
for name, k in {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}.items():
    save(legacy, f"{res}/mipmap-{name}/ic_launcher.png", int(48 * k))
    save(round_, f"{res}/mipmap-{name}/ic_launcher_round.png", int(48 * k))
    save(fg, f"{res}/mipmap-{name}/ic_launcher_foreground.png", int(108 * k))
    save(mono_fg, f"{res}/mipmap-{name}/ic_launcher_monochrome.png", int(108 * k))
    save(mono, f"{res}/drawable-{name}/ic_notification.png", int(24 * k))
    save(mono, f"{res}/drawable-{name}/ic_bg_service_small.png", int(24 * k))
    save(fg, f"{res}/drawable-{name}/splash_logo.png", int(108 * k))

ios = os.path.join(APP, "ios/Runner/Assets.xcassets/AppIcon.appiconset")
for f in os.listdir(ios):
    if f.endswith(".png"):
        pt, sc = f[len("Icon-App-"):-4].split("@")
        save(full_rgb, os.path.join(ios, f), round(float(pt.split("x")[0]) * int(sc[0])))

mac = os.path.join(APP, "macos/Runner/Assets.xcassets/AppIcon.appiconset")
if os.path.isdir(mac):
    for f in os.listdir(mac):
        if f.endswith(".png"):
            save(legacy, os.path.join(mac, f), int(f[len("app_icon_"):-4]))

save(legacy, os.path.join(APP, "assets/logo.png"), 512)
print("done")
