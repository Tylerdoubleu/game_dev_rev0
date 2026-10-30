"""v0.6 (Ren): procedural foley for movement + the break air horn (numpy only, 44.1 kHz mono 16-bit).
Run from the repo root: python3 scripts/tools/gen_movement_audio.py"""
import math, wave
import numpy as np
SR = 44100
rng = np.random.default_rng(606)

def biquad(x, kind, f, q=0.707):
    w0 = 2 * math.pi * f / SR; a = math.sin(w0) / (2 * q); c = math.cos(w0)
    if kind == "lp": b = [(1 - c) / 2, 1 - c, (1 - c) / 2]
    elif kind == "hp": b = [(1 + c) / 2, -(1 + c), (1 + c) / 2]
    else: b = [a, 0, -a]  # band-pass
    a0, a1, a2 = 1 + a, -2 * c, 1 - a
    b0, b1, b2 = b[0] / a0, b[1] / a0, b[2] / a0; a1 /= a0; a2 /= a0
    y = np.zeros_like(x); x1 = x2 = y1 = y2 = 0.0
    for i in range(len(x)):
        v = b0 * x[i] + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, x[i], y1, v; y[i] = v
    return y

def env(n, attack, decay_pow=2.0):
    t = np.linspace(0, 1, n); a = max(1, int(attack * SR))
    e = (1 - t) ** decay_pow; e[:a] *= np.linspace(0, 1, a); return e

def save(path, x, peak=0.9):
    x = x / (np.abs(x).max() + 1e-9) * peak
    fade = min(len(x), 220); x[-fade:] *= np.linspace(1, 0, fade)
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x * 32767).astype("<i2").tobytes())

def noise(sec): return rng.standard_normal(int(sec * SR))
M = "assets/audio/movement/"

# Footsteps on turf: a soft heel thump + short gritty turf/rubber-crumb crunch. 4 variations.
for i in range(4):
    n = int(0.16 * SR); t = np.arange(n) / SR
    thump = np.sin(2 * math.pi * (70 + 12 * i) * t) * np.exp(-t * 38)
    crunch = biquad(noise(0.16), "bp", 1700 + 350 * i, 0.8) * env(n, 0.004, 3.5)
    grit = biquad(noise(0.16), "hp", 4200, 0.7) * env(n, 0.002, 6) * 0.35
    save(M + "step_turf_%d.wav" % (i + 1), thump * 0.9 + crunch * 0.6 + grit, 0.75)

# Sprint step: harder plant, more crunch.
for i in range(2):
    n = int(0.18 * SR); t = np.arange(n) / SR
    thump = np.sin(2 * math.pi * (62 + 10 * i) * t) * np.exp(-t * 30)
    crunch = biquad(noise(0.18), "bp", 1400 + 500 * i, 0.7) * env(n, 0.003, 3)
    save(M + "step_sprint_%d.wav" % (i + 1), thump + crunch * 0.85, 0.85)

# Knee-slide scrape across turf (pads + slide pants), ~0.65 s with a fading swish.
n = int(0.65 * SR); t = np.arange(n) / SR
sw = biquad(noise(0.65), "bp", 900, 0.6) * (1 - t / 0.65) ** 1.2 * np.minimum(1, t / 0.03)
hiss = biquad(noise(0.65), "hp", 3000) * (1 - t / 0.65) ** 2 * 0.4
rum = biquad(noise(0.65), "lp", 160) * (1 - t / 0.65) * 1.6
save(M + "slide_scrape.wav", sw + hiss + rum, 0.8)

# Dive landing: chest-pad body thud on turf with a little gear rattle.
n = int(0.35 * SR); t = np.arange(n) / SR
thud = np.sin(2 * math.pi * 55 * t) * np.exp(-t * 16) + biquad(noise(0.35), "lp", 400) * np.exp(-t * 22) * 1.4
rattle = biquad(noise(0.35), "bp", 2600, 1.2) * np.exp(-t * 30) * 0.4
save(M + "dive_land.wav", thud + rattle, 0.9)

# Jump/fall landing (lighter).
n = int(0.22 * SR); t = np.arange(n) / SR
save(M + "land_soft.wav", np.sin(2 * math.pi * 75 * t) * np.exp(-t * 25) + biquad(noise(0.22), "bp", 1500, 0.8) * np.exp(-t * 35) * 0.5, 0.7)

def voice(sec, f0, formants, breath=0.25, shape=None):
    """Tiny formant voice: glottal pulse train through band-passes, plus breath noise. Muffled (through a mask)."""
    n = int(sec * SR); t = np.arange(n) / SR
    f = f0(t) if callable(f0) else np.full(n, f0)
    ph = np.cumsum(f / SR) % 1.0
    glot = (ph < 0.4) * np.sin(math.pi * ph / 0.4) ** 2 - 0.25
    src = glot + noise(sec) * breath
    out = sum(biquad(src, "bp", fr, q) * g for fr, q, g in formants)
    out = biquad(out, "lp", 2400)  # paintball mask muffle
    e = shape(t) if shape else env(n, 0.02, 1.5)
    return out * e

# Dive "hup!" effort, slide "hnh" effort, and a sprint exhale. Kept subtle and masked.
save(M + "effort_dive.wav", voice(0.26, lambda t: 150 - 40 * t / 0.26, [(650, 6, 1.0), (1150, 8, 0.6), (2400, 10, 0.2)], 0.3,
     lambda t: np.minimum(1, t / 0.015) * np.exp(-t * 9)), 0.7)
save(M + "effort_slide.wav", voice(0.2, lambda t: 128 - 20 * t / 0.2, [(500, 6, 1.0), (1000, 8, 0.5)], 0.35,
     lambda t: np.minimum(1, t / 0.02) * np.exp(-t * 12)), 0.6)
for i in range(2):
    n = int(0.38 * SR); t = np.arange(n) / SR
    br = biquad(noise(0.38), "bp", 1200 + 300 * i, 0.9) + biquad(noise(0.38), "bp", 2600, 1.5) * 0.4
    br = biquad(br, "lp", 3000) * np.sin(math.pi * np.minimum(1, t / 0.38)) ** 1.5
    save(M + "breath_sprint_%d.wav" % (i + 1), br, 0.45)

# Break air horn: two detuned sawtooth reeds (A4-ish + a fifth below) with a growl, 1.6 s.
sec = 1.6; n = int(sec * SR); t = np.arange(n) / SR
def saw(f): return 2 * ((t * f) % 1.0) - 1
f_wob = 1 + 0.004 * np.sin(2 * math.pi * 5.5 * t)
h = saw(466 * f_wob) + saw(470 * f_wob) * 0.8 + saw(311 * f_wob) * 0.7 + saw(233 * f_wob) * 0.35
h = np.tanh(h * 1.6)
h = biquad(h, "lp", 3800) + biquad(h, "bp", 1200, 1.2) * 0.5
e = np.minimum(1, t / 0.04) * np.where(t > sec - 0.18, (sec - t) / 0.18, 1.0)
save("assets/audio/break/air_horn.wav", h * e, 0.85)
print("ok")
