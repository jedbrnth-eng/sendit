#!/usr/bin/env python3
"""Cut one-shot SFX from long CC0 recordings (BigSoundBank).
- pass-bys: the loudest `win` seconds around the RMS peak, high-passed rumble, fades, -1 dBFS.
- crash: layered steel crunch + door thump + glass, offset slightly, fades, -1 dBFS.
usage: tools/cut_sfx.py <src_dir> <dst_dir>
"""
import subprocess, sys, wave, numpy as np

SR = 44100


def read(p):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", p, "-f", "s16le", "-ac", "1", "-ar", str(SR), "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.int16).astype(np.float64) / 32768.0


def write(p, x):
    x = x * (0.89 / max(1e-6, np.max(np.abs(x))))
    with wave.open(p, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes())


def fade(x, fin, fout):
    a, b = int(fin * SR), int(fout * SR)
    if a: x[:a] *= np.linspace(0, 1, a) ** 2
    if b: x[-b:] *= np.linspace(1, 0, b) ** 2
    return x


def highpass(x, hz):
    # one-pole high-pass: removes wind rumble on outdoor recordings
    rc = 1.0 / (2 * np.pi * hz); dt = 1.0 / SR; a = rc / (rc + dt)
    y = np.zeros_like(x)
    for i in range(1, len(x)):
        y[i] = a * (y[i - 1] + x[i] - x[i - 1])
    return y


def peak_window(x, win):
    n = int(win * SR); hop = SR // 50
    e = np.convolve(x * x, np.ones(n) / n, mode="valid")[::hop]
    c = int(np.argmax(e)) * hop
    return x[c:c + n].copy()


def main(src, dst):
    for name in ["car-passing-50km-h-5-s2989", "car-passing-50km-h-6-s2990", "car-passing-50km-h-8-s2992",
                 "car-passing-50km-h-14-s3000", "car-passing-50km-h-3-s2987", "car-passing-50km-h-4-s2988"]:
        y = read(f"{src}/{name}.ogg")
        env = np.convolve(y * y, np.ones(SR // 10) / (SR // 10), mode="same")
        c = int(np.argmax(env))
        # The gap event fires as the car drops behind us, so the loudest moment must come early.
        x = highpass(y[max(0, c - int(0.3 * SR)):c + int(1.1 * SR)].copy(), 90.0)
        write(f"{dst}/passby_{name.split('-s')[-1]}.wav", fade(x, 0.12, 0.6))
    steel = [read(f"{src}/{n}.ogg") for n in ["falling-sheet-steel-bar-1-s1771", "falling-sheet-steel-bar-3-s1773", "fall-2-sheet-steel-bars-1-s1776"]]
    door = read(f"{src}/car-door-3-s1524.ogg")
    def from_peak(y, pre=0.015):
        # start just before the loudest transient so the hit lands on frame 0, not 0.5 s in
        return y[max(0, int(np.argmax(np.abs(y))) - int(pre * SR)):]
    door = from_peak(door)
    for i, s in enumerate(steel):
        s = from_peak(s)[: int(1.2 * SR)]
        mix = np.zeros(int(1.4 * SR))
        d = door[: len(mix)]
        mix[: len(d)] += d * 0.9                       # body thump first
        o = int(0.012 * SR)
        mix[o:o + len(s)] += s[: len(mix) - o] * 1.0   # steel crunch right on top
        write(f"{dst}/crash_{i}.wav", fade(mix, 0.002, 0.5))


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
