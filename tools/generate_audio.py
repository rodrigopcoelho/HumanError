#!/usr/bin/env python3
"""Generates every sound used by HUMAN ERROR (original, procedural, CC0).

Usage:  python3 tools/generate_audio.py        (writes assets/audio/*.wav)
Only the Python standard library is required.
"""
import math, os, random, struct, wave

SR = 22050
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio")
random.seed(417)


def write(name, samples, gain=1.0):
    peak = max(1e-9, max(abs(s) for s in samples))
    scale = 0.89 / peak * gain  # normalise, then apply the per-sound gain
    data = b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s * scale)) * 32767)) for s in samples)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(data)
    print("wrote %-14s %5.2fs" % (name, len(samples) / SR))


def noise(n):
    return [random.uniform(-1.0, 1.0) for _ in range(n)]


def lowpass(x, cutoff):
    a = 1.0 - math.exp(-2.0 * math.pi * cutoff / SR)
    y, out = 0.0, []
    for s in x:
        y += a * (s - y); out.append(y)
    return out


def highpass(x, cutoff):
    lp = lowpass(x, cutoff)
    return [s - l for s, l in zip(x, lp)]


def bandpass(x, lo, hi):
    return highpass(lowpass(x, hi), lo)


def env(n, attack, decay_rate):
    a = max(1, int(attack * SR))
    return [min(1.0, i / a) * math.exp(-decay_rate * i / SR) for i in range(n)]


def mix(*tracks):
    n = max(len(t) for t in tracks)
    out = [0.0] * n
    for t in tracks:
        for i, s in enumerate(t):
            out[i] += s
    return out


def scale(x, g):
    return [s * g for s in x]


def seamless(x, fade=0.4):
    """Crossfades the tail onto the head so the buffer loops without a click."""
    f = int(fade * SR)
    body = x[:len(x) - f]
    for i in range(f):
        t = i / f
        body[i] = body[i] * t + x[len(x) - f + i] * (1.0 - t)
    return body


def tone(freq, dur, shape="sine"):
    n = int(dur * SR)
    out = []
    for i in range(n):
        p = (freq * i / SR) % 1.0
        if shape == "sine":
            out.append(math.sin(2 * math.pi * p))
        elif shape == "square":
            out.append(1.0 if p < 0.5 else -1.0)
        else:
            out.append(2.0 * p - 1.0)
    return out


def click(dur, cutoff_lo, cutoff_hi, decay, attack=0.0005):
    n = int(dur * SR)
    e = env(n, attack, decay)
    return [s * k for s, k in zip(bandpass(noise(n), cutoff_lo, cutoff_hi), e)]


def pad(x, before=0.0, after=0.0):
    return [0.0] * int(before * SR) + x + [0.0] * int(after * SR)


def main():
    os.makedirs(OUT, exist_ok=True)

    # --- interface
    write("click", scale(mix(click(0.05, 900, 5000, 120), scale(tone(180, 0.03), 0.25)), 0.9))
    write("select", [s * k for s, k in zip(tone(660, 0.07, "square"), env(int(0.07 * SR), 0.002, 45))], 0.35)
    write("open", mix(click(0.08, 300, 3000, 60), pad([s * k for s, k in zip(tone(440, 0.09), env(int(0.09 * SR), 0.003, 30))], 0.02)), 0.6)
    conf = pad([s * k for s, k in zip(tone(523, 0.12, "square"), env(int(0.12 * SR), 0.002, 22))]) + \
        [s * k for s, k in zip(tone(784, 0.22, "square"), env(int(0.22 * SR), 0.002, 14))]
    write("confirm", lowpass(conf, 3500), 0.4)
    deny = [s * k for s, k in zip(tone(196, 0.16, "square"), env(int(0.16 * SR), 0.002, 14))] + \
        [s * k for s, k in zip(tone(147, 0.26, "square"), env(int(0.26 * SR), 0.002, 10))]
    write("deny", lowpass(deny, 2500), 0.4)
    err = []
    for _ in range(2):
        err += [s * k for s, k in zip(mix(tone(311, 0.14, "square"), tone(330, 0.14, "square")), env(int(0.14 * SR), 0.002, 8))] + [0.0] * int(0.05 * SR)
    write("error", lowpass(err, 3000), 0.4)
    note = [s * k for s, k in zip(tone(880, 0.14), env(int(0.14 * SR), 0.004, 16))] + \
        [s * k for s, k in zip(tone(1174.7, 0.4), env(int(0.4 * SR), 0.004, 8))]
    write("notify", note, 0.45)
    write("blip", [s * k for s, k in zip(tone(1320, 0.05, "square"), env(int(0.05 * SR), 0.001, 60))], 0.22)
    stamp = mix(click(0.25, 60, 900, 22, 0.002), scale(pad(click(0.1, 800, 4000, 60), 0.012), 0.5))
    write("stamp", stamp, 1.0)
    for i, (lo, hi) in enumerate([(1200, 6000), (900, 5000), (1500, 7000)], 1):
        k = mix(click(0.045, lo, hi, 140), scale(pad(click(0.03, 300, 1500, 90), 0.004), 0.6))
        write("key%d" % i, k, 0.8)

    # --- machine
    hdd = [0.0] * int(1.6 * SR)
    t = 0.05
    while t < 1.45:
        c = click(0.03, 500, 3500, 160)
        base = int(t * SR)
        for i, s in enumerate(c):
            if base + i < len(hdd):
                hdd[base + i] += s * random.uniform(0.4, 1.0)
        t += random.choice([0.03, 0.045, 0.06, 0.09, 0.2])
    spin = [s * 0.12 for s in bandpass(noise(len(hdd)), 200, 900)]
    write("hdd", mix(hdd, spin), 0.7)
    n = int(1.8 * SR)
    boot = []
    for i in range(n):
        tt = i / SR
        f = 90 + 380 * (1 - math.exp(-tt * 2.2))
        boot.append(math.sin(2 * math.pi * f * tt) * 0.35 * min(1.0, tt * 4) * min(1.0, (1.8 - tt) * 3))
    beep = pad([s * k for s, k in zip(tone(988, 0.16, "square"), env(int(0.16 * SR), 0.002, 10))], 1.3)
    write("boot", mix(boot, scale(lowpass(beep, 4000), 0.35), scale(bandpass(noise(n), 300, 2500), 0.05)), 0.8)

    # --- world
    ring = []
    for burst in range(2):
        m = int(0.42 * SR)
        for i in range(m):
            tt = i / SR
            trem = 0.5 + 0.5 * (1.0 if math.sin(2 * math.pi * 22 * tt) > 0 else -1.0)
            ring.append((math.sin(2 * math.pi * 1280 * tt) + 0.6 * math.sin(2 * math.pi * 1640 * tt)) * trem * 0.4)
        ring += [0.0] * int(0.2 * SR)
    write("phone_ring", ring, 0.6)
    write("pickup", mix(click(0.12, 200, 2500, 35), pad(click(0.06, 600, 3000, 70), 0.09)), 0.9)
    door = mix(click(0.5, 40, 500, 9, 0.004), scale(pad(click(0.12, 500, 3500, 40), 0.03), 0.6), scale(pad(click(0.2, 60, 400, 14), 0.18), 0.7))
    write("door", door, 1.0)
    n = int(2.6 * SR)
    gurgle = bandpass(noise(n), 200, 1400)
    coffee = [gurgle[i] * (0.35 + 0.3 * math.sin(2 * math.pi * 6.5 * i / SR) * math.sin(2 * math.pi * 0.9 * i / SR)) * min(1.0, i / (0.3 * SR)) * min(1.0, (n - i) / (0.6 * SR)) for i in range(n)]
    write("coffee", coffee, 0.8)

    # --- ambience loops
    n = int(6.4 * SR)
    fan = mix(scale(lowpass(noise(n), 420), 1.0), scale(bandpass(noise(n), 900, 2400), 0.10))
    fan = [s * (0.9 + 0.1 * math.sin(2 * math.pi * 0.5 * i / SR)) + 0.05 * math.sin(2 * math.pi * 118 * i / SR) for i, s in enumerate(fan)]
    write("fan", seamless(fan), 0.9)
    n = 4 * SR
    hum = [0.5 * math.sin(2 * math.pi * 60 * i / SR) + 0.25 * math.sin(2 * math.pi * 120 * i / SR) + 0.12 * math.sin(2 * math.pi * 180 * i / SR)
           + 0.03 * math.sin(2 * math.pi * 9400 * i / SR) for i in range(n)]
    write("crt_hum", hum, 0.5)
    n = int(4.4 * SR)
    hiss = bandpass(noise(n), 2500, 7000)
    buzz = []
    for i in range(n):
        tt = i / SR
        saw = 2.0 * ((120 * tt) % 1.0) - 1.0
        buzz.append(0.3 * saw + 0.2 * math.sin(2 * math.pi * 240 * tt) + hiss[i] * 0.12 * (0.6 + 0.4 * math.sin(2 * math.pi * 120 * tt)))
    write("fluorescent", seamless(lowpass(buzz, 5000)), 0.5)
    n = int(12.4 * SR)
    murmur = [0.0] * n
    for voice in range(5):
        base = bandpass(noise(n), random.uniform(180, 320), random.uniform(600, 900))
        rate = random.uniform(2.8, 4.6)
        phase = random.uniform(0, 6.28)
        talk_phase = random.uniform(0, 6.28)
        talk_rate = random.uniform(0.07, 0.16)
        for i in range(n):
            tt = i / SR
            syll = max(0.0, math.sin(2 * math.pi * rate * tt + phase)) ** 2
            talking = 1.0 if math.sin(2 * math.pi * talk_rate * tt + talk_phase) > -0.1 else 0.0
            murmur[i] += base[i] * syll * talking
    write("murmur", seamless(lowpass(murmur, 700), 0.8), 0.8)
    n = int(5.4 * SR)
    raw = noise(n)
    inter = []
    held = 0.0
    for i in range(n):
        if i % 6 == 0:
            held = round(raw[i] * 4) / 4.0
        gate = 1.0 if math.sin(2 * math.pi * 3.1 * i / SR) * math.sin(2 * math.pi * 0.7 * i / SR) > 0.25 else 0.15
        inter.append(held * gate * 0.6 + 0.2 * math.sin(2 * math.pi * 50 * i / SR))
    write("interference", seamless(bandpass(inter, 150, 6000)), 0.6)

    # --- minimal music: a slow, slightly detuned drone (integer cycles so it loops)
    dur = 16
    n = dur * SR
    partials = [(55.0, 0.5), (55.0 + 1 / 16, 0.4), (82.5, 0.22), (110.0 + 1 / 8, 0.16), (164.8125, 0.07), (233.0625, 0.04)]
    drone = []
    for i in range(n):
        tt = i / SR
        s = sum(a * math.sin(2 * math.pi * f * tt) for f, a in partials)
        swell = 0.65 + 0.35 * math.sin(2 * math.pi * tt / dur - 1.2)
        drone.append(s * swell)
    air = lowpass(noise(n + int(0.8 * SR)), 300)
    air = seamless(air, 0.8)
    write("drone", [d + 0.5 * a for d, a in zip(drone, air)], 0.7)


if __name__ == "__main__":
    main()
