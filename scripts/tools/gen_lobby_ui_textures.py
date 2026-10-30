"""v0.6 (Ren): procedural Gritty 2000s Tournament UI textures for the lobby browser + waiting room.
Run from the repo root: python3 scripts/tools/gen_lobby_ui_textures.py  (needs Pillow + numpy)."""
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
rng = np.random.default_rng(2004)
OUT = "assets/textures/ui/"

def noise(w, h, scale, octaves=4):
    acc = np.zeros((h, w)); amp = 1.0; tot = 0
    for o in range(octaves):
        s = max(1, int(scale / (2 ** o)))
        small = rng.random((h // s + 2, w // s + 2))
        img = Image.fromarray((small * 255).astype(np.uint8)).resize((w + 2 * s, h + 2 * s), Image.BICUBIC)
        acc += amp * np.asarray(img, dtype=float)[s:s + h, s:s + w] / 255.0
        tot += amp; amp *= 0.5
    return acc / tot

def splatter(draw, w, h, color, n, rmax):
    for _ in range(n):
        x, y = rng.integers(0, w), rng.integers(0, h)
        r = rng.integers(1, rmax)
        a = int(rng.integers(90, 200))
        draw.ellipse([x - r, y - r, x + r, y + r], fill=color + (a,))

# 1. Field netting over a dark tarp (tileable-ish background)
w = h = 512
base = noise(w, h, 96)
tarp = np.stack([18 + base * 22, 21 + base * 24, 17 + base * 18], -1)
img = Image.fromarray(tarp.clip(0, 255).astype(np.uint8)).convert("RGBA")
d = ImageDraw.Draw(img)
step = 32
for i in range(-h, w + h, step):
    d.line([(i, 0), (i + h, h)], fill=(58, 60, 50, 150), width=2)
    d.line([(i, h), (i + h, 0)], fill=(58, 60, 50, 150), width=2)
for x in range(0, w, step // 2):
    for y in range(0, h, step // 2):
        if (x // (step // 2) + y // (step // 2)) % 2 == 0:
            d.ellipse([x - 2, y - 2, x + 2, y + 2], fill=(70, 72, 60, 170))
ov = Image.new("RGBA", (w, h)); od = ImageDraw.Draw(ov)
splatter(od, w, h, (230, 60, 140), 40, 4); splatter(od, w, h, (230, 235, 40), 40, 4)
img = Image.alpha_composite(img, ov.filter(ImageFilter.GaussianBlur(0.6)))
img.convert("RGB").save(OUT + "ui_netting_bg.png")

# 2. Painted plywood board (scoreboard backing)
w, h = 512, 512
grain = noise(w, h * 4, 40, 3)[: h, :]
streak = np.sin(np.linspace(0, 60, h))[:, None] * 0.08 + noise(w, h, 8, 2) * 0.25
v = 0.55 + grain * 0.35 + streak
wood = np.stack([v * 46, v * 48, v * 42], -1)
scuff = noise(w, h, 64) > 0.68
wood[scuff] = wood[scuff] * 0.6 + np.array([95, 72, 45]) * 0.4  # bare wood showing through worn paint
img = Image.fromarray(wood.clip(0, 255).astype(np.uint8)).convert("RGBA")
ov = Image.new("RGBA", (w, h)); od = ImageDraw.Draw(ov)
splatter(od, w, h, (240, 245, 40), 25, 3); splatter(od, w, h, (240, 70, 150), 18, 3)
for _ in range(14):  # scratches
    x, y = rng.integers(0, w), rng.integers(0, h)
    od.line([(x, y), (x + rng.integers(-60, 60), y + rng.integers(-8, 8))], fill=(150, 140, 120, 70), width=1)
img = Image.alpha_composite(img, ov)
img.convert("RGB").save(OUT + "ui_plywood_board.png")

# 3. Scuffed vinyl card (lobby rows / team panels), greyscale so Godot can tint it
w, h = 256, 128
n = noise(w, h, 32)
g = 172 + n * 60
img = Image.fromarray(np.stack([g, g, g], -1).astype(np.uint8)).convert("RGBA")
d = ImageDraw.Draw(img)
d.rectangle([0, 0, w - 1, h - 1], outline=(30, 30, 30, 255), width=3)
d.rectangle([3, 3, w - 4, h - 4], outline=(140, 140, 140, 120), width=1)
for _ in range(30):
    x, y = rng.integers(0, w), rng.integers(0, h)
    d.line([(x, y), (x + rng.integers(-20, 20), y + rng.integers(-3, 3))], fill=(235, 235, 235, 70))
img.save(OUT + "ui_vinyl_card.png")

# 4. Masking tape strip with torn ends
w, h = 160, 44
n = noise(w, h, 10, 2)
tape = np.stack([200 + n * 25, 188 + n * 22, 150 + n * 18, np.full((h, w), 225.0)], -1)
for x in range(w):
    for end in (x < 8, x > w - 9):
        pass
a = tape[..., 3]
for y in range(h):
    cut_l = int(rng.integers(0, 9)); cut_r = int(rng.integers(0, 9))
    a[y, :cut_l] = 0; a[y, w - cut_r:] = 0
Image.fromarray(tape.clip(0, 255).astype(np.uint8), "RGBA").save(OUT + "ui_tape_strip.png")
print("ok")
