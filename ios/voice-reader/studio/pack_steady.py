#!/usr/bin/env python3
"""Kararlı ölçü for a finished studio pack: every segment's melody is drawn toward the whole pack's middle pitch
(so the segments also come to the same height), its level is evened, and the segments are brought to the same
loudness. The durations do not change. The untouched audio is kept in audio-raw/ (run again = start from it).

    vox/bin/python pack_steady.py <pack.vrstudio> [--target 3.7]
"""
import argparse, glob, os, shutil, subprocess, sys, tempfile
import numpy as np, soundfile as sf

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "steady", "steady")

def decode(m4a, tmp):
    wav = os.path.join(tmp, "x.wav")
    subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEF32@48000", "-c", "1", m4a, wav], check=True)
    y, sr = sf.read(wav, dtype="float32")
    return y

def loud(y):
    """Level of the speaking parts in dB."""
    n = 4800
    e = np.array([np.sqrt(np.mean(y[i:i + n] ** 2) + 1e-12) for i in range(0, max(1, len(y) - n), n)])
    if len(e) == 0: return -60.0
    return float(20 * np.log10(np.median(e[e > 0.25 * e.max()]) + 1e-9))

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("pack"); ap.add_argument("--target", type=float, default=3.7)
    ap.add_argument("--floor", type=float, default=0.45)
    a = ap.parse_args()
    audio, raw = os.path.join(a.pack, "audio"), os.path.join(a.pack, "audio-raw")
    if not os.path.isdir(raw):
        shutil.copytree(audio, raw)
    files = sorted(glob.glob(os.path.join(raw, "*.m4a")))
    with tempfile.TemporaryDirectory() as tmp:
        clips = [decode(f, tmp) for f in files]
        whole = os.path.join(tmp, "all.f32"); np.concatenate(clips).astype("<f4").tofile(whole)
        hz, spread = map(float, subprocess.run([TOOL, "measure", whole], capture_output=True, text=True).stdout.split())
        keep = 1.0 if spread <= a.target else max(a.floor, a.target / spread)
        levels = [loud(y) for y in clips]; mid = float(np.median(levels))
        print(f"paket: {hz:.1f} Hz, melodi {spread:.2f} yarım ton → keep {keep:.2f}; düzey ortası {mid:.1f} dB", flush=True)
        for f, y, lv in zip(files, clips, levels):
            i, o = os.path.join(tmp, "i.f32"), os.path.join(tmp, "o.f32")
            y.astype("<f4").tofile(i)
            gain = float(np.clip(mid - lv, -5, 5))
            subprocess.run([TOOL, "apply", i, o, f"{keep:.3f}", f"{hz:.2f}", f"{gain:.2f}"], check=True)
            z = np.fromfile(o, dtype="<f4")
            assert len(z) == len(y)
            wav = os.path.join(tmp, "o.wav"); sf.write(wav, z, 48000)
            subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", "-b", "96000", wav, os.path.join(audio, os.path.basename(f))], check=True)
        out = os.path.join(tmp, "after.f32")
        np.concatenate([decode(os.path.join(audio, os.path.basename(f)), tmp) for f in files]).astype("<f4").tofile(out)
        print("sonra:", subprocess.run([TOOL, "measure", out], capture_output=True, text=True).stdout.strip(), flush=True)

if __name__ == "__main__":
    main()
