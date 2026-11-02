#!/usr/bin/env python3
"""Voice Reader Studio: renders a text with a large local voice model on the Mac, for Voice Reader on the iPhone.

A "studio pack" is a folder:
    <name>.vrstudio/
        book.json        title, author, language, the readable text (Voice Reader's DocumentContent),
                         and one entry per spoken segment: where it is in the text, its audio file, its length,
                         the pause after it, and where each word starts in the audio
        audio/0001.m4a   one AAC file per segment (48 kHz mono)

The phone imports the pack as a document; with the Studio voice it plays these files instead of synthesising.
Rendering resumes where it stopped (segments already in audio/ are kept).

Model: VoxCPM2 (OpenBMB, Apache-2.0), voice cloned from one approved reference clip so every segment has the same
voice. Each segment is checked with Whisper (large-v3-turbo); a segment with too many word errors is rendered again.

    vox/bin/python studio.py <text.md> <out folder> --title … --author … [--reference clip.wav]
"""
import argparse, difflib, json, os, re, subprocess, sys, tempfile, time, unicodedata, uuid
import numpy as np
import soundfile as sf

SR = 48_000
MAX_CHARS = 260          # one segment: a sentence, or a few short ones (long enough for natural phrasing)
HARD_CHARS = 420         # a longer sentence is cut at ; or ,
PAUSE_HEADING = 0.9
PAUSE_PARAGRAPH = 0.45
PAUSE_THINK = 4.0        # after "Bir nefes düşün." at a ◆ stop: time to answer before the answer comes

# ---------- text ----------

def utf16_len(s: str) -> int:
    return len(s.encode("utf-16-le")) // 2


def parse_markdown(md: str):
    """Paragraphs one per line (as Voice Reader keeps them), headings as chapters."""
    lines, chapters, kinds = [], [], []
    offset = 0
    for raw in md.splitlines():
        s = raw.strip()
        if not s:
            continue
        kind = "p"
        m = re.match(r"^(#{1,6})\s+(.*)$", s)
        if m:
            kind = "h"
            s = m.group(2).strip()
            chapters.append({"title": s, "offset": offset, "level": len(m.group(1))})
        elif s.startswith(">"):
            s = s.lstrip("> ").strip()
            kind = "q"
        s = re.sub(r"\*\*(.+?)\*\*", r"\1", s)
        s = re.sub(r"(?<!\w)\*(.+?)\*(?!\w)", r"\1", s)
        lines.append(s)
        kinds.append(kind)
        offset += utf16_len(s) + 1
    return "\n".join(lines), chapters, lines, kinds


SENTENCE_END = re.compile(r"(?<=[.!?…])[\"”’)]*\s+(?=[\"“‘(]?[A-ZÇĞİÖŞÜÂÎÛ0-9◆])")


def sentences(par: str):
    out, start = [], 0
    for m in SENTENCE_END.finditer(par):
        out.append((start, m.start() + len(m.group(0).rstrip())))
        start = m.end()
    if start < len(par):
        out.append((start, len(par)))
    return [(a, b) for a, b in out if par[a:b].strip()]


def cut_long(par: str, a: int, b: int):
    """A sentence longer than HARD_CHARS is cut after ; or , near the middle of what is left."""
    pieces = []
    while b - a > HARD_CHARS:
        window = par[a:a + MAX_CHARS + 60]
        cut = max(window.rfind("; "), window.rfind(", ", 0, MAX_CHARS + 60))
        if cut < 80:
            break
        pieces.append((a, a + cut + 1))
        a = a + cut + 2
    pieces.append((a, b))
    return pieces


def segments_for(lines, kinds):
    """(line index, start, end, pause) in characters of that line."""
    segs = []
    for i, (par, kind) in enumerate(zip(lines, kinds)):
        if kind == "h":
            segs.append((i, 0, len(par), PAUSE_HEADING))
            continue
        units = []
        for a, b in sentences(par):
            units += cut_long(par, a, b)
        group = None
        for a, b in units:
            text = par[a:b]
            think = text.strip().startswith("Bir nefes düşün")
            if group and (b - group[0] > MAX_CHARS or think or par[group[0]:group[1]].startswith("◆")):
                segs.append((i, group[0], group[1], 0.0)); group = None
            group = (group[0], b) if group else (a, b)
            if think:
                segs.append((i, group[0], group[1], PAUSE_THINK)); group = None
        if group:
            segs.append((i, group[0], group[1], 0.0))
        # the paragraph's last segment carries the paragraph pause
        if segs and segs[-1][0] == i and segs[-1][3] == 0.0:
            segs[-1] = (i, segs[-1][1], segs[-1][2], PAUSE_PARAGRAPH)
    return segs


def spoken_form(s: str) -> str:
    s = s.replace("◆ Durak.", "Durak.").replace("◆", "")
    return re.sub(r"\s+", " ", s).strip()

# ---------- alignment ----------

def norm(w: str) -> str:
    w = w.replace("I", "ı").replace("İ", "i").lower()
    w = unicodedata.normalize("NFKD", w)
    w = "".join(c for c in w if not unicodedata.combining(c))
    return re.sub(r"[^\w]", "", w)


WORD = re.compile(r"[\wÂâÎîÛû'’]+", re.UNICODE)


def spoken_number(w: str) -> str:
    """Whisper writes numbers as digits ("1676", "44'te"); the text spells them out."""
    from num2words import num2words
    def rep(m):
        try:
            return num2words(int(m.group(0)), lang="tr")
        except Exception:
            return m.group(0)
    return re.sub(r"\d+", rep, w)


def align(text: str, base: int, line_offset16: int, whisper_words, duration: float):
    """Word starts (ms) for every word of `text`; positions are UTF-16 offsets in the whole document.
    The text and what Whisper heard are compared letter by letter (spaces and punctuation ignored, numbers spelled
    out), so a word heard as one token or as digits still lands; a word with no matching letter is placed between its
    neighbours by letter count. Accuracy = share of the text's letters that were heard."""
    toks = [(m.start(), m.end(), m.group(0)) for m in WORD.finditer(text)]
    if not toks:
        return [], 1.0
    a_chars, a_word = [], []
    for i, t in enumerate(toks):
        for c in norm(t[2]):
            a_chars.append(c); a_word.append(i)
    b_chars, b_time = [], []
    for w in whisper_words:
        letters = norm(spoken_number(w["word"]))
        if not letters:
            continue
        st, en = float(w["start"]), float(w.get("end", w["start"]))
        for k, c in enumerate(letters):
            b_chars.append(c); b_time.append(st + (en - st) * k / len(letters))
    starts = [None] * len(toks)
    matched = 0
    sm = difflib.SequenceMatcher(a="".join(a_chars), b="".join(b_chars), autojunk=False)
    for blk in sm.get_matching_blocks():
        for k in range(blk.size):
            wi = a_word[blk.a + k]
            if starts[wi] is None:
                starts[wi] = b_time[blk.b + k]
        matched += blk.size
    if starts[0] is None:
        starts[0] = 0.0
    known = [(toks[i][0], starts[i]) for i in range(len(toks)) if starts[i] is not None]
    known.append((len(text), duration))
    j = 0
    for i, t in enumerate(toks):
        if starts[i] is not None:
            continue
        while j + 1 < len(known) and known[j + 1][0] <= t[0]:
            j += 1
        (c0, s0), (c1, s1) = known[j], known[min(j + 1, len(known) - 1)]
        starts[i] = s0 + (s1 - s0) * ((t[0] - c0) / max(1, c1 - c0))
    for i in range(1, len(starts)):
        starts[i] = max(starts[i], starts[i - 1] + 0.01)
    words = []
    for (s0, e0, w), st in zip(toks, starts):
        loc = line_offset16 + utf16_len(text[:s0]) + base
        words.append([int(round(st * 1000)), loc, utf16_len(w)])
    return words, matched / max(1, len(a_chars))


# ---------- main ----------

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("source")
    ap.add_argument("out")
    ap.add_argument("--title", required=True)
    ap.add_argument("--author", default=None)
    ap.add_argument("--voice", default="Anlatıcı")
    ap.add_argument("--reference", default=os.path.expanduser("~/.local/share/insan-ses/deneme/vox-narrator.wav"))
    ap.add_argument("--reference-text", default=None, help="what the reference clip says (better prosody)")
    ap.add_argument("--min-accuracy", type=float, default=0.92)
    ap.add_argument("--limit", type=int, default=0, help="render only the first N segments (trial)")
    args = ap.parse_args()

    md = open(args.source, encoding="utf-8").read()
    text, chapters, lines, kinds = parse_markdown(md)
    segs = segments_for(lines, kinds)
    line_off = []
    o = 0
    for l in lines:
        line_off.append(o)
        o += utf16_len(l) + 1

    out = args.out
    os.makedirs(os.path.join(out, "audio"), exist_ok=True)
    book_path = os.path.join(out, "book.json")
    done = {}
    if os.path.exists(book_path):
        old = json.load(open(book_path, encoding="utf-8"))
        if old.get("content", {}).get("text") == text:
            done = {s["file"]: s for s in old["segments"] if s.get("file")}

    from voxcpm import VoxCPM
    import mlx_whisper
    model = VoxCPM.from_pretrained("openbmb/VoxCPM2", load_denoiser=False)

    def save(segments, complete):
        book = {
            "format": "voice-reader-studio", "version": 1,
            "id": str(uuid.uuid5(uuid.NAMESPACE_URL, "voice-reader-studio:" + args.title)).upper(),
            "title": args.title, "author": args.author, "language": "tr", "voice": args.voice,
            "model": "VoxCPM2", "complete": complete,
            "content": {"text": text, "chapters": chapters, "pages": []},
            "segments": segments,
        }
        tmp = book_path + ".tmp"
        json.dump(book, open(tmp, "w", encoding="utf-8"), ensure_ascii=False)
        os.replace(tmp, book_path)

    results = []
    todo = segs[: args.limit] if args.limit else segs
    t_start = time.time()
    audio_total = 0.0
    for n, (li, a, b, pause) in enumerate(todo, 1):
        name = f"{n:04d}.m4a"
        raw = lines[li][a:b]
        loc = line_off[li] + utf16_len(lines[li][:a])
        entry = {"location": loc, "length": utf16_len(raw), "file": name, "pause": pause}
        if name in done and done[name]["location"] == loc and os.path.exists(os.path.join(out, "audio", name)):
            results.append(done[name]); continue
        say = spoken_form(raw)
        best = None
        for attempt in range(3):
            kwargs = dict(text=say, reference_wav_path=args.reference, cfg_value=2.0, inference_timesteps=10)
            if args.reference_text:
                kwargs.update(prompt_wav_path=args.reference, prompt_text=args.reference_text)
            wav = model.generate(**kwargs)
            wav = np.asarray(wav, dtype=np.float32)
            dur = len(wav) / SR
            with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
                sf.write(f.name, wav, SR)
                tmpwav = f.name
            heard = mlx_whisper.transcribe(tmpwav, path_or_hf_repo="mlx-community/whisper-large-v3-turbo",
                                           language="tr", word_timestamps=True, verbose=None)
            hw = [w for s in heard.get("segments", []) for w in s.get("words", [])]
            words, acc = align(raw, 0, loc, hw, dur)
            if best is None or acc > best[2]:
                if best:
                    os.unlink(best[0])
                best = (tmpwav, words, acc, dur)
            else:
                os.unlink(tmpwav)
            if acc >= args.min_accuracy:
                break
            print(f"  {name}: {acc:.0%} doğru, yeniden", flush=True)
        tmpwav, words, acc, dur = best
        subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", "-b", "96000", tmpwav,
                        os.path.join(out, "audio", name)], check=True)
        os.unlink(tmpwav)
        entry.update(duration=round(dur, 3), accuracy=round(acc, 3), words=words)
        results.append(entry)
        audio_total += dur
        save(results, False)
        el = time.time() - t_start
        print(f"{n}/{len(todo)} {name} {dur:5.1f} sn ses · {acc:.0%} · geçen {el/60:4.1f} dk", flush=True)
    save(results, len(results) == len(segs))
    print(f"bitti: {len(results)} parça, {sum(s['duration'] for s in results)/60:.1f} dk ses")


if __name__ == "__main__":
    main()
