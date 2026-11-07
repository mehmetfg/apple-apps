#!/usr/bin/env python3
"""High speed without the blur: speech is shortened unevenly. Pauses go to a small fixed length, steady vowels are
squeezed the most, and the places that carry the words (consonants, bursts, the moves between sounds: fast spectral
change or much energy above 4 kHz) are squeezed the least. Variable-rate WSOLA, pitch kept.

    from fast_speech import squeeze;  y2 = squeeze(y, sr, seconds_wanted)
"""
import numpy as np
import scipy.signal as sg


def protect_map(y, sr, hop):
    """Per hop: 0 = a steady vowel, 1 = a consonant or a transition; and whether it is a pause."""
    f, t, Z = sg.stft(y, fs=sr, nperseg=int(sr * 0.02), noverlap=int(sr * 0.02) - hop, boundary=None, padded=False)
    mag = np.abs(Z) + 1e-9
    db = 10 * np.log10(np.mean(mag ** 2, axis=0))
    ref = np.percentile(db, 95)
    pause = db < ref - 35
    logm = np.log(mag)
    flux = np.r_[0, np.sqrt(np.mean(np.diff(logm, axis=1) ** 2, axis=0))]
    flux = flux / (np.percentile(flux[~pause], 90) + 1e-9)
    hf = np.sum(mag[f >= 4000] ** 2, axis=0) / np.sum(mag ** 2, axis=0)
    c = np.clip(np.maximum(flux, (hf - 0.15) / 0.3), 0, 1)
    c = np.convolve(c, np.ones(5) / 5, mode="same")                 # ±10 ms: the edges of a consonant count too
    return c, pause


def squeeze(y, sr, seconds, short_pause=0.035, long_pause=0.10, spare=0.85, hop_ms=5.0):
    y = np.asarray(y, dtype=np.float32)
    hop = int(sr * hop_ms / 1000)
    c, pause = protect_map(y, sr, hop)
    n = len(c)
    # pauses: each run to a fixed small length (a breath between sentences stays longer than one inside a sentence)
    rate = np.ones(n)
    i = 0
    while i < n:
        if pause[i]:
            j = i
            while j < n and pause[j]: j += 1
            length = (j - i) * hop / sr
            want = long_pause if length >= 0.2 else short_pause
            rate[i:j] = max(1.0, length / want)
            i = j
        else:
            i += 1
    speech = ~pause
    fixed = np.sum(1 / rate[pause]) * hop / sr
    want_speech = max(0.05, seconds - fixed)
    # speech: rate = 1 + (R − 1)·(1 − spare·c); R by bisection so that the speech takes the time that is left
    lo, hi = 1.0, 12.0
    for _ in range(40):
        R = (lo + hi) / 2
        t = np.sum(1 / (1 + (R - 1) * (1 - spare * c[speech]))) * hop / sr
        lo, hi = (R, hi) if t > want_speech else (lo, R)
    rate[speech] = 1 + (R - 1) * (1 - spare * c[speech])
    # variable-rate WSOLA
    N, H, T = int(sr * 0.02), int(sr * 0.01), int(sr * 0.006)
    win = np.hanning(N).astype(np.float32)
    pos_rate = np.repeat(rate, hop)
    pos_rate = np.r_[pos_rate, np.full(max(0, len(y) - len(pos_rate)) + N, pos_rate[-1])]
    out = np.zeros(int(len(y) / 1.0) + 2 * N, dtype=np.float32); norm = np.zeros_like(out)
    yp = np.r_[y, np.zeros(2 * N + 2 * T, dtype=np.float32)]
    a, o, prev = 0.0, 0, None
    while a + N + T < len(y):
        s = int(a)
        if prev is not None:
            nat = yp[prev + H: prev + H + N]
            lo_s = max(0, s - T)
            cand = np.lib.stride_tricks.sliding_window_view(yp[lo_s: s + T + N], N)
            score = cand @ nat / (np.sqrt(np.sum(cand ** 2, axis=1)) + 1e-9)
            s = lo_s + int(np.argmax(score))
        out[o:o + N] += yp[s:s + N] * win; norm[o:o + N] += win
        prev = s
        a += H * pos_rate[min(int(a), len(pos_rate) - 1)]
        o += H
    out = out[:o + H] / np.maximum(norm[:o + H], 1e-3)
    return out.astype(np.float32), R
