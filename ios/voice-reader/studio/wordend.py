#!/usr/bin/env python3
"""Word endings: how firmly a voice lands the last part of each word (the user's "tokluk": the last syllable struck
strong and closed, as if no word could follow). Word times from Whisper; per word of 4+ letters and 0.2 s or more:

  end_level  level of the word's last 35 % against its first 65 % (dB; > 0 = the end is the stronger part)
  end_pitch  pitch of the last 35 % against the first 65 % (semitones)
  strong     share of words whose end is at least as loud as their start (%)
  close      time the level takes to fall 15 dB after the last word before a pause (ms; short = closed firmly), also
             in syllables of that voice at that pace: compare voices by this, never by ms at different speeds
  fall       pitch of a phrase's last word against the phrase's middle (semitones; negative = it lands low)

    vox/bin/python wordend.py a.wav [b.wav …]
"""
import sys, warnings, numpy as np, librosa, mlx_whisper
warnings.filterwarnings("ignore")

def analyse(path, language="tr"):
    y, sr = librosa.load(path, sr=16000, mono=True)
    y = y / (np.max(np.abs(y)) + 1e-9)
    hop = 160
    f0, vf, _ = librosa.pyin(y, fmin=65, fmax=420, sr=sr, frame_length=1024, hop_length=hop)
    rms = librosa.feature.rms(y=y, frame_length=400, hop_length=hop)[0]
    n = min(len(f0), len(rms)); f0, vf, rms = f0[:n], vf[:n], rms[:n]
    db = 20 * np.log10(rms + 1e-6)
    r = mlx_whisper.transcribe(path, path_or_hf_repo="mlx-community/whisper-large-v3-turbo", language=language, word_timestamps=True, verbose=None)
    words = [w for s in r.get("segments", []) for w in s.get("words", [])]
    fr = hop / sr
    lv, pt, close, fall = [], [], [], []
    med = np.nanmedian(f0[vf])
    for k, w in enumerate(words):
        a, b = int(w["start"] / fr), int(w["end"] / fr)
        text = "".join(c for c in w["word"] if c.isalpha())
        if b - a < int(0.2 / fr) or len(text) < 4 or b > n: continue
        cut = a + int((b - a) * 0.65)
        loud = db[a:b] > db[a:b].max() - 18
        h, t = db[a:cut][loud[:cut - a]], db[cut:b][loud[cut - a:]]
        if len(h) < 3 or len(t) < 2: continue
        lv.append(t.mean() - h.mean())
        fh, ft = f0[a:cut][vf[a:cut]], f0[cut:b][vf[cut:b]]
        if len(fh) >= 3 and len(ft) >= 2: pt.append(12 * np.log2(np.median(ft) / np.median(fh)))
        nxt = words[k + 1]["start"] if k + 1 < len(words) else w["end"] + 1
        if nxt - w["end"] >= 0.15:                      # the last word before a pause
            seg = db[cut:min(n, b + int(0.3 / fr))]
            top = seg[: max(2, b - cut)].max(); p = int(np.argmax(seg[: max(2, b - cut)]))
            low = np.flatnonzero(seg[p:] < top - 15)
            if len(low): close.append(low[0] * fr * 1000)
            if len(ft) >= 2: fall.append(12 * np.log2(np.median(ft) / med))
    lv, pt = np.array(lv), np.array(pt)
    # the pace, so that times can be read against the length of a syllable: vowels a second of spoken time, words a minute
    vowels = sum(c in "aeıioöuüâîûAEIİOÖUÜ" for w in words for c in w["word"])
    spoken = sum(w["end"] - w["start"] for w in words)
    syl = vowels / max(spoken, 1e-6)
    wpm = 60 * len(words) / max(words[-1]["end"] - words[0]["start"], 1e-6) if words else 0
    return dict(syl=syl, wpm=wpm, words=len(lv), end_level=lv.mean(), strong=100 * np.mean(lv >= 0), end_pitch=pt.mean() if len(pt) else float("nan"),
                close=np.median(close) if close else float("nan"), fall=np.mean(fall) if fall else float("nan"), ends=len(close))

if __name__ == "__main__":
    for f in sys.argv[1:]:
        lang = "en" if f.endswith(".en.wav") else "tr"
        r = analyse(f, lang)
        print(f"{f.split('/')[-1]:28s} words {r['words']:3d} · end level {r['end_level']:+5.1f} dB · strong ends {r['strong']:3.0f}% · end pitch {r['end_pitch']:+5.2f} st · "
              f"close {r['close']:4.0f} ms ({r['ends']}) = {r['close'] * r['syl'] / 1000:.2f} syllables · final fall {r['fall']:+5.2f} st · {r['wpm']:.0f} words/min, {r['syl']:.1f} syl/s", flush=True)
