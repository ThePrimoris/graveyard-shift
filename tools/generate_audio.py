"""Procedural audio for Graveyard Shift (v2).

Run from the project root:  python3 tools/generate_audio.py
Deterministic (seeded). No samples, no AI audio — pure synthesis, licence-free.

v2 goals over the lost v1 generator: every SFX gets its own sonic identity
(wood tick vs glass chime vs anvil ring vs bubbling still), and every ambient
loop gets a distinct scene (bells+wind, birds+creaks, drips+rumble,
heartbeat+drone, bubble+glass). Loops are fold-crossfaded to be seamless.

  sfx/*.wav    44.1 kHz mono 16-bit
  music/*.wav  22.05 kHz stereo 16-bit, ~16 s seamless loops
"""
import numpy as np
import wave
import os

SR = 44100
MSR = 22050
rng = np.random.default_rng(1031)  # the graveyard's birthday


# ---------------------------------------------------------------- helpers

def t_axis(seconds, sr=SR):
    return np.arange(int(seconds * sr)) / sr


def sine(freq, seconds, sr=SR, phase=0.0):
    return np.sin(2 * np.pi * freq * t_axis(seconds, sr) + phase)


def sine_sweep(f0, f1, seconds, sr=SR):
    """Sine whose pitch glides f0 -> f1 (exponential)."""
    t = t_axis(seconds, sr)
    k = np.log(max(f1, 1e-3) / max(f0, 1e-3)) / max(seconds, 1e-9)
    # NB: divide by k ITSELF — clamping k here (e.g. max(k, eps)) destroys
    # every DOWNWARD sweep: the huge mis-scaled phase folds into wideband
    # static. The abs guard below already covers the k≈0 case.
    if abs(k) > 1e-9:
        phase = 2 * np.pi * f0 * (np.exp(k * t) - 1) / k
    else:
        phase = 2 * np.pi * f0 * t
    return np.sin(phase)


def saw(freq, seconds, sr=SR, nharm=18):
    """Band-limited-ish saw via summed harmonics."""
    t = t_axis(seconds, sr)
    out = np.zeros_like(t)
    for h in range(1, nharm + 1):
        if freq * h > sr * 0.45:
            break
        out += np.sin(2 * np.pi * freq * h * t) / h
    return out * (2 / np.pi)


def noise(seconds, sr=SR):
    return rng.standard_normal(int(seconds * sr))


def brown_noise(seconds, sr=SR):
    """Integrated white noise (-6 dB/oct): naturally dark, no hiss. The right
    base for wind and rumble — raw white noise through a one-pole filter
    keeps enough top end to read as static."""
    x = np.cumsum(rng.standard_normal(int(seconds * sr)))
    # remove the random-walk drift with a gentle highpass
    x = x - lowpass(x.copy(), 8.0, sr)
    m = np.max(np.abs(x))
    return x / m if m > 1e-9 else x


def lowpass(x, cutoff, sr=SR, passes=1):
    """One-pole lowpass, cascadable."""
    a = np.clip(2 * np.pi * cutoff / sr, 0.0, 0.99)
    for _ in range(passes):
        y = np.empty_like(x)
        acc = 0.0
        for i in range(len(x)):
            acc += a * (x[i] - acc)
            y[i] = acc
        x = y
    return x


def highpass(x, cutoff, sr=SR):
    return x - lowpass(x.copy(), cutoff, sr)


def bandpass(x, lo, hi, sr=SR, passes=1):
    return highpass(lowpass(x, hi, sr, passes), lo, sr)


def env_ad(n, attack, decay, curve=4.0):
    """Attack/decay envelope over n samples (attack+decay in samples)."""
    e = np.zeros(n)
    a = max(int(attack), 1)
    e[:a] = np.linspace(0, 1, a)
    d = n - a
    if d > 0:
        e[a:] = np.exp(-curve * np.linspace(0, 1, d))
    return e


def echo(x, delay_s, decay, taps=4, sr=SR):
    d = int(delay_s * sr)
    out = np.copy(x)
    for i in range(1, taps + 1):
        shifted = np.zeros_like(x)
        if d * i < len(x):
            shifted[d * i:] = x[:len(x) - d * i] * (decay ** i)
        out += shifted
    return out


def normalize(x, peak=0.9):
    m = np.max(np.abs(x))
    return x * (peak / m) if m > 1e-9 else x


def write_wav(path, x, sr=SR, stereo=False):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    x = np.clip(x, -1.0, 1.0)
    data = (x * 32767).astype(np.int16)
    with wave.open(path, "wb") as f:
        f.setnchannels(2 if stereo else 1)
        f.setsampwidth(2)
        f.setframerate(sr)
        if stereo:
            f.writeframes(np.column_stack(data).astype(np.int16).tobytes()
                          if isinstance(data, tuple) else data.tobytes())
        else:
            f.writeframes(data.tobytes())


def write_stereo(path, left, right, sr=MSR):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    left = np.clip(left, -1, 1)
    right = np.clip(right, -1, 1)
    inter = np.empty(len(left) * 2, dtype=np.int16)
    inter[0::2] = (left * 32767).astype(np.int16)
    inter[1::2] = (right * 32767).astype(np.int16)
    with wave.open(path, "wb") as f:
        f.setnchannels(2)
        f.setsampwidth(2)
        f.setframerate(sr)
        f.writeframes(inter.tobytes())


def fold_loop(x, fade_s, sr=MSR):
    """Crossfades the tail into the head so the loop point is seamless."""
    f = int(fade_s * sr)
    body, tail = x[:-f], x[-f:]
    w = np.linspace(0, 1, f)
    body[:f] = body[:f] * w + tail * (1 - w)
    return body


# ---------------------------------------------------------------- SFX

def sfx_ui_click():
    """A soft parchment/wood tick — felt more than heard."""
    n = int(0.06 * SR)
    tap = bandpass(noise(0.06), 900, 3200) * env_ad(n, 30, n, 9)
    thump = sine(190, 0.06) * env_ad(n, 12, n, 10) * 0.5
    return normalize(tap * 0.5 + thump, 0.42)


def sfx_harvest_tick():
    """A shovel biting earth: dull, low, organic."""
    n = int(0.16 * SR)
    bite = lowpass(noise(0.16), 900, passes=2) * env_ad(n, 40, n, 7)
    body = sine_sweep(150, 65, 0.16) * env_ad(n, 25, n, 6) * 0.8
    grit = bandpass(noise(0.16), 1800, 5200) * env_ad(n, 15, int(n * 0.3), 14) * 0.2
    return normalize(bite * 0.7 + body + grit, 0.6)


def sfx_item_pickup():
    """A small glass chime, two quick notes — bright, friendly, distinct."""
    def partial(freq, dur, amp):
        n = int(dur * SR)
        return (sine(freq, dur) + 0.35 * sine(freq * 2.76, dur)) * env_ad(n, 18, n, 6) * amp
    a = partial(1318.5, 0.22, 0.6)                       # E6
    b = partial(1760.0, 0.26, 0.5)                       # A6
    out = np.zeros(int(0.34 * SR))
    out[:len(a)] += a
    off = int(0.08 * SR)
    out[off:off + len(b)] += b
    return normalize(out, 0.55)


def sfx_level_up():
    """A rising candle-lit arpeggio with shimmer: A3 C4 E4 A4."""
    notes = [220.0, 261.6, 329.6, 440.0]
    out = np.zeros(int(1.2 * SR))
    for i, f in enumerate(notes):
        dur = 0.5 if i < 3 else 0.75
        n = int(dur * SR)
        tone = (sine(f, dur) + 0.4 * sine(f * 2, dur) + 0.15 * sine(f * 1.005, dur)) \
            * env_ad(n, 90, n, 5)
        off = int(i * 0.11 * SR)
        out[off:off + n] += tone * (0.4 + 0.08 * i)
    sparkle = bandpass(noise(1.2), 5000, 10000)[:len(out)] * env_ad(len(out), int(0.35 * SR), len(out), 4) * 0.05
    return normalize(out + sparkle, 0.62)


def sfx_build():
    """Stone set down, then a mallet knock — heavy, satisfying."""
    out = np.zeros(int(0.5 * SR))
    n1 = int(0.24 * SR)
    thud = sine_sweep(120, 55, 0.24) * env_ad(n1, 20, n1, 7)
    rubble = lowpass(noise(0.24), 1300) * env_ad(n1, 30, n1, 9) * 0.5
    out[:n1] += thud + rubble
    n2 = int(0.2 * SR)
    knock = (sine_sweep(320, 190, 0.2) + lowpass(noise(0.2), 2000) * 0.3) * env_ad(n2, 12, n2, 10)
    off = int(0.22 * SR)
    out[off:off + n2] += knock * 0.8
    return normalize(out, 0.66)


def sfx_combat_hit():
    """A punchy body blow: pitch-dropped thump + a crack of noise."""
    n = int(0.18 * SR)
    punch = sine_sweep(170, 55, 0.18) * env_ad(n, 10, n, 8)
    crack = bandpass(noise(0.18), 1400, 6500) * env_ad(n, 6, int(n * 0.25), 16) * 0.5
    return normalize(punch + crack, 0.7)


def sfx_brew():
    """The still bubbling over: rising resonant bloops."""
    out = np.zeros(int(0.55 * SR))
    freqs = [300, 380, 460, 560]
    for i, f in enumerate(freqs):
        dur = 0.14
        n = int(dur * SR)
        bloop = sine_sweep(f * 0.7, f * 1.25, dur) * env_ad(n, 25, n, 7)
        off = int(i * 0.11 * SR)
        out[off:off + n] += bloop * 0.55
    fizz = bandpass(noise(0.55), 3200, 8200) * 0.06
    return normalize(out + fizz * env_ad(len(out), int(0.1 * SR), len(out), 3), 0.5)


def sfx_smith():
    """Hammer on anvil: inharmonic metal ring over a dull strike."""
    n = int(0.45 * SR)
    strike = sine_sweep(240, 90, 0.1)
    strike = np.pad(strike, (0, n - len(strike))) * env_ad(n, 6, int(0.12 * SR), 9)
    ring = np.zeros(n)
    for f, amp in ((1180, 0.5), (1783, 0.35), (2960, 0.22), (4210, 0.12)):
        ring += sine(f, 0.45) * amp
    ring *= env_ad(n, 4, n, 5.5)
    return normalize(strike * 0.8 + ring * 0.5, 0.62)


def sfx_potion():
    """Two low gulps and a little splash."""
    out = np.zeros(int(0.4 * SR))
    for i in range(2):
        dur = 0.12
        n = int(dur * SR)
        gulp = sine_sweep(420, 130, dur) * env_ad(n, 14, n, 8)
        off = int(i * 0.14 * SR)
        out[off:off + n] += gulp * 0.7
    ns = int(0.12 * SR)
    splash = bandpass(noise(0.12), 1800, 6000) * env_ad(ns, 10, ns, 10) * 0.25
    out[int(0.26 * SR):int(0.26 * SR) + ns] += splash
    return normalize(out, 0.55)


def sfx_victory_sting():
    """Three notes lifting out of the dark: D4 F4 A4 held."""
    out = np.zeros(int(1.3 * SR))
    for i, f in enumerate((293.7, 349.2, 440.0)):
        dur = 0.5 if i < 2 else 0.95
        n = int(dur * SR)
        tone = (sine(f, dur) + 0.4 * sine(f * 2, dur) + 0.2 * saw(f, dur, nharm=6)) \
            * env_ad(n, 110, n, 4.2)
        off = int(i * 0.17 * SR)
        out[off:off + n] += tone * 0.45
    glow = bandpass(noise(1.3), 4000, 9000) * env_ad(len(out), int(0.5 * SR), len(out), 3) * 0.05
    return normalize(out + glow, 0.6)


def sfx_defeat_sting():
    """A low fall: D3 sliding to a flat, dark A2 with a groan of noise."""
    n = int(1.25 * SR)
    fall = sine_sweep(146.8, 108.0, 1.25) * env_ad(n, int(0.06 * SR), n, 3.2)
    under = sine_sweep(73.4, 55.0, 1.25) * env_ad(n, int(0.1 * SR), n, 3.0) * 0.7
    groan = lowpass(noise(1.25), 350) * env_ad(n, int(0.2 * SR), n, 4) * 0.3
    return normalize(fall + under + groan, 0.6)


# ---------------------------------------------------------------- MUSIC
# All loops: LOOP_S seconds at 22.05 kHz stereo, fold-crossfaded (FADE_S).

LOOP_S = 18.0
FADE_S = 2.0


def _mt(seconds=LOOP_S):
    return np.arange(int(seconds * MSR)) / MSR


def _wind(lo, hi, lfo_hz, depth, seconds=LOOP_S):
    """Breathing wind from BROWN noise, steeply filtered — dark movement, no
    static. (v2 used white noise through one-pole filters: audible hiss.)"""
    w = brown_noise(seconds, MSR)
    w = lowpass(w, hi, MSR, passes=3)
    w = highpass(w, lo, MSR)
    m = np.max(np.abs(w))
    if m > 1e-9:
        w = w / m
    lfo = 1.0 - depth + depth * (0.5 + 0.5 * np.sin(2 * np.pi * lfo_hz * _mt(seconds) + rng.uniform(0, 6.28)))
    return w * lfo


def _master(x):
    """Final tone control for the ambient beds: shave residual top end so
    quiet loops never read as hiss on small speakers."""
    return lowpass(x, 6000, MSR)


def _bell(freq, dur, sr=MSR):
    """A dark church-bell strike: minor-third partials, long decay."""
    n = int(dur * sr)
    t = np.arange(n) / sr
    out = np.zeros(n)
    for p, amp in ((1.0, 1.0), (1.19, 0.55), (1.7, 0.35), (2.0, 0.28), (2.74, 0.15)):
        out += np.sin(2 * np.pi * freq * p * t) * amp * np.exp(-t * (1.1 + p))
    return out


def _place(canvas, clip, at_s, gain, sr=MSR):
    i = int(at_s * sr)
    end = min(i + len(clip), len(canvas))
    if i < len(canvas):
        canvas[i:end] += clip[:end - i] * gain


def amb_graveyard():
    """Low wind, a distant D-minor bell, a breath of buried choir."""
    wind = _wind(120, 700, 0.07, 0.55) * 0.16
    canvas_l = np.copy(wind)
    canvas_r = _wind(120, 700, 0.06, 0.55) * 0.16
    for at, f in ((2.2, 146.8), (9.6, 110.0), (14.8, 146.8)):
        b = _bell(f, 5.0)
        _place(canvas_l, b, at, 0.10)
        _place(canvas_r, b, at + 0.012, 0.085)  # slight haas spread
    t = _mt()
    swell = 0.5 + 0.5 * np.sin(2 * np.pi * t / LOOP_S * 2 + 1.1)
    for f in (73.4, 110.0, 146.8):  # D2 A2 D3
        pad = (np.sin(2 * np.pi * f * t) + np.sin(2 * np.pi * f * 1.004 * t)) * 0.5
        canvas_l += pad * swell * 0.028
        canvas_r += pad * (1 - swell * 0.4) * 0.028
    return normalize(fold_loop(_master(canvas_l), FADE_S), 0.5), normalize(fold_loop(_master(canvas_r), FADE_S), 0.5)


def amb_forest():
    """Higher breeze through leaves, sparse bird calls, a wooden creak."""
    canvas_l = _wind(400, 2400, 0.11, 0.6) * 0.13
    canvas_r = _wind(400, 2400, 0.09, 0.6) * 0.13
    for at in (1.8, 6.4, 12.9):  # up-glide chirps, seeded positions
        dur = 0.16
        n = int(dur * MSR)
        chirp = sine_sweep(2100 + rng.uniform(-200, 300), 3300, dur, MSR)[:n] * env_ad(n, 40, n, 7)
        side = canvas_l if rng.random() < 0.5 else canvas_r
        _place(side, chirp, at, 0.05)
        _place(canvas_r if side is canvas_l else canvas_l, chirp, at + 0.006, 0.03)
    creak = lowpass(saw(68, 0.9, MSR, nharm=10), 500, MSR) * env_ad(int(0.9 * MSR), int(0.3 * MSR), int(0.9 * MSR), 4)
    _place(canvas_l, creak, 9.4, 0.05)
    _place(canvas_r, creak, 9.41, 0.05)
    t = _mt()
    for f in (98.0, 146.8):  # G2 D3 earth pad
        canvas_l += np.sin(2 * np.pi * f * t) * 0.014
        canvas_r += np.sin(2 * np.pi * f * 1.003 * t) * 0.014
    return normalize(fold_loop(_master(canvas_l), FADE_S), 0.5), normalize(fold_loop(_master(canvas_r), FADE_S), 0.5)


def amb_quarry():
    """Cavern rumble, echoing water drips, a far-off pick."""
    # Brown-noise rumble: deep movement with no white-noise hiss on top.
    rumble_l = lowpass(brown_noise(LOOP_S, MSR), 130, MSR, passes=2)
    rumble_r = lowpass(brown_noise(LOOP_S, MSR), 130, MSR, passes=2)
    canvas_l, canvas_r = rumble_l * 0.5, rumble_r * 0.5
    for at in (1.3, 4.9, 8.2, 12.1, 15.6):
        dur = 0.09
        n = int(dur * MSR)
        plink = sine_sweep(2500 + rng.uniform(-500, 500), 1400, dur, MSR)[:n] * env_ad(n, 8, n, 9)
        plink = echo(plink, 0.19, 0.45, taps=3, sr=MSR)
        pan = rng.uniform(0.25, 0.75)
        _place(canvas_l, plink, at, 0.07 * (1 - pan) * 2)
        _place(canvas_r, plink, at, 0.07 * pan * 2)
    # The far-off pick: anti-alias filter BEFORE decimating to 22.05k (the v2
    # naive [::2] aliased into metallic static).
    tink = lowpass(sfx_smith(), 5000, SR, passes=2)[::2][:int(0.3 * MSR)] * 0.05
    _place(canvas_l, tink, 10.4, 0.6)
    _place(canvas_r, tink, 10.43, 0.5)
    return normalize(fold_loop(_master(canvas_l), FADE_S), 0.5), normalize(fold_loop(_master(canvas_r), FADE_S), 0.5)


def amb_combat():
    """A heartbeat under a dark detuned drone; tension breathing in."""
    n = int(LOOP_S * MSR)
    t = _mt()
    drone = (saw(55.0, LOOP_S, MSR, nharm=8) + saw(55.55, LOOP_S, MSR, nharm=8)) * 0.5
    drone = lowpass(drone, 320, MSR) * 0.14
    beat = np.zeros(n)
    period = 60.0 / 72.0  # 72 bpm
    at = 0.0
    while at < LOOP_S - 0.4:
        for off, g in ((0.0, 1.0), (0.32, 0.6)):  # lub-dub
            dn = int(0.14 * MSR)
            # ~4ms attack: still a thud, but no clicky broadband transient.
            thump = sine_sweep(95, 42, 0.14, MSR)[:dn] * env_ad(dn, 90, dn, 8)
            _place(beat, thump, at + off, 0.20 * g)
        at += period
    # Tension breath: a slow-swelling DARK layer (brown noise, mid band) —
    # the v2 white-noise shimmer read as static.
    breath_l = bandpass(brown_noise(LOOP_S, MSR), 300, 1400, MSR, passes=2)
    breath_r = bandpass(brown_noise(LOOP_S, MSR), 300, 1400, MSR, passes=2)
    swell_l = (0.5 + 0.5 * np.sin(2 * np.pi * t / LOOP_S * 2 - 1.57)) * 0.05
    swell_r = (0.5 + 0.5 * np.sin(2 * np.pi * t / LOOP_S * 2 - 1.2)) * 0.05
    left = drone + beat + breath_l * swell_l
    right = drone * 0.94 + beat + breath_r * swell_r
    return normalize(fold_loop(_master(left), FADE_S), 0.55), normalize(fold_loop(_master(right), FADE_S), 0.55)


def amb_alchemy():
    """The still at work: soft bubbling, glassy E-minor partials, thin wind."""
    n = int(LOOP_S * MSR)
    canvas_l = _wind(250, 1200, 0.08, 0.5) * 0.07
    canvas_r = _wind(250, 1200, 0.07, 0.5) * 0.07
    at = 0.4
    while at < LOOP_S - 0.3:
        dur = 0.1
        bn = int(dur * MSR)
        f = rng.uniform(240, 620)
        bloop = sine_sweep(f * 0.75, f * 1.2, dur, MSR)[:bn] * env_ad(bn, 18, bn, 8)
        pan = rng.uniform(0.2, 0.8)
        _place(canvas_l, bloop, at, 0.05 * (1 - pan) * 2)
        _place(canvas_r, bloop, at, 0.05 * pan * 2)
        at += rng.uniform(0.5, 1.6)
    t = _mt()
    swell = 0.5 + 0.5 * np.sin(2 * np.pi * t / LOOP_S * 3 + 0.6)
    for f, g in ((164.8, 1.0), (246.9, 0.7), (329.6, 0.5)):  # E3 B3 E4
        glass = (np.sin(2 * np.pi * f * t) + 0.3 * np.sin(2 * np.pi * f * 2.01 * t))
        canvas_l += glass * swell * 0.016 * g
        canvas_r += glass * (1 - swell * 0.35) * 0.016 * g
    return normalize(fold_loop(_master(canvas_l), FADE_S), 0.5), normalize(fold_loop(_master(canvas_r), FADE_S), 0.5)


# ---------------------------------------------------------------- main

SFX = {
    "ui_click": sfx_ui_click,
    "harvest_tick": sfx_harvest_tick,
    "item_pickup": sfx_item_pickup,
    "level_up": sfx_level_up,
    "build": sfx_build,
    "combat_hit": sfx_combat_hit,
    "brew": sfx_brew,
    "smith": sfx_smith,
    "potion": sfx_potion,
    "victory_sting": sfx_victory_sting,
    "defeat_sting": sfx_defeat_sting,
}

MUSIC = {
    "amb_graveyard": amb_graveyard,
    "amb_forest": amb_forest,
    "amb_quarry": amb_quarry,
    "amb_combat": amb_combat,
    "amb_alchemy": amb_alchemy,
}


def main():
    for name, fn in SFX.items():
        write_wav("audio/sfx/%s.wav" % name, fn())
        print("sfx/%s.wav" % name)
    for name, fn in MUSIC.items():
        left, right = fn()
        write_stereo("audio/music/%s.wav" % name, left, right)
        print("music/%s.wav (%.1fs loop)" % (name, len(left) / MSR))


if __name__ == "__main__":
    main()
