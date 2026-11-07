#!/usr/bin/env python3
"""Firm endings ("tokluk"): where a phrase runs into a pause, the voice's release is made steeper, so the last word
closes in about the time Yelda takes (0.8 of a syllable for the level to fall 15 dB from the last syllable's peak: 70 ms at 240 words a minute).
Measured 2026-11-06: every voice closes in 0.8 syllables at its own natural pace; a neural voice sped up by WSOLA to
the listening speed closes in 1.2 (100 ms at 260 words a minute), because the squeezed tail keeps its level.
So this runs AFTER the tempo change, with the target for that speed.

Only the decay after the last loud point of the phrase is touched: its fall in dB is multiplied (never more than
2.2 times, never more than 13 dB of extra cut: measured on the Bilge pack at 260 words a minute, 1.30 → 0.71
syllables with the same words heard by Whisper; 2.5 times and 18 dB went past Yelda, to 0.5), and less so where the sound is a fricative or a burst (s, ş, t, k:
much of the energy above 4 kHz), so a word's last consonant stays. Nothing moves in time: the length is the same.

    from close_tight import tighten;  y2, report = tighten(y, sr=48000, target_ms=70)   # target = 0.8 / (syllables a second) at the listening speed
"""
import numpy as np
import scipy.signal as sg


def _frames(y, sr, win_ms=10, hop_ms=5):
    win, hop = int(sr * win_ms / 1000), int(sr * hop_ms / 1000)
    n = max(1, (len(y) - win) // hop + 1)
    idx = np.arange(n)[:, None] * hop + np.arange(win)[None, :]
    return y[np.minimum(idx, len(y) - 1)], hop


def tighten(y, sr=48_000, target_ms=70.0, max_k=2.2, max_cut=13.0, pause_ms=150.0):
    y = np.asarray(y, dtype=np.float32)
    if len(y) < sr // 4:
        return y, []
    fr, hop = _frames(y, sr)
    db = 10 * np.log10(np.mean(fr ** 2, axis=1) + 1e-10)
    b, a = sg.butter(2, 4000 / (sr / 2), "high")
    frh, _ = _frames(sg.lfilter(b, a, y).astype(np.float32), sr)
    hf = np.mean(frh ** 2, axis=1) / (np.mean(fr ** 2, axis=1) + 1e-10)        # share of the energy above 4 kHz
    fric = np.clip((hf - 0.2) / 0.3, 0, 1)
    ref = np.percentile(db, 95)
    quiet = db < ref - 32
    n = len(db); ms = hop / sr * 1000
    need = int(pause_ms / ms)
    extra = np.zeros(n)                                                         # dB to add (≤ 0), per frame
    report = []
    i = 1
    while i < n:
        if quiet[i] and not quiet[i - 1]:
            j = i
            while j < n and quiet[j]: j += 1
            if j - i >= need or j == n:                                         # a pause, or the end of the piece
                lo = max(0, i - int(250 / ms))
                top = db[lo:i].max()
                q = lo + int(np.argmax(db[lo:i]))                               # the last syllable's peak
                tail_end = min(n, i + int(60 / ms))
                L = np.minimum(0, sg.medfilt(db[q:tail_end], 3) - top)          # the natural fall, dB under the top
                below = np.flatnonzero(L <= -15)
                t15 = (below[0] if len(below) else len(L)) * ms
                if t15 > target_ms * 1.15:
                    k = min(max_k, t15 / target_ms)
                    cut = np.maximum(-max_cut, (k - 1) * L * (1 - 0.8 * fric[q:tail_end]))
                    extra[q:tail_end] = np.minimum(extra[q:tail_end], cut)
                    back = min(n, tail_end + int(40 / ms))                      # in the silence the cut lets go again
                    if back > tail_end:
                        extra[tail_end:back] = np.linspace(cut[-1], 0, back - tail_end)
                    report.append((q * ms / 1000, t15, k))
                else:
                    report.append((q * ms / 1000, t15, 1.0))
            i = j
        else:
            i += 1
    if not np.any(extra):
        return y, report
    extra = np.convolve(extra, np.ones(3) / 3, mode="same")
    centres = np.arange(n) * hop + int(sr * 0.005)
    g = np.interp(np.arange(len(y)), centres, extra)
    return (y * (10 ** (g / 20))).astype(np.float32), report


if __name__ == "__main__":
    import sys, soundfile as sf
    y, sr = sf.read(sys.argv[1], dtype="float32")
    z, rep = tighten(y, sr)
    sf.write(sys.argv[2], z, sr)
    done = [r for r in rep if r[2] > 1]
    print(f"{len(rep)} endings, {len(done)} tightened; median fall time before {np.median([r[1] for r in rep]):.0f} ms")
