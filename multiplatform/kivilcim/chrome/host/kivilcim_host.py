#!/usr/bin/python3
# Kıvılcım · Dikkat — Chrome's native messaging helper (2026-11-04).
# Chrome starts this for each message from the extension (stdin: 4-byte length + JSON; stdout: the same).
#   kaydet → writes the mark to <Kıvılcım>/isaret/<YYYY-MM>/<id>.json (+ voice note as .m4a), then starts isle.py
#   durum  → the "look now" list Claude wrote (Dikkat/claude/analiz.json), with titles and links from dizin.json
# If iCloud is not writable from Chrome (privacy rules), the mark waits in ~/Library/Application Support/Kivilcim/
# gelen-isaret/ and isle.py moves it into the vault on its next run. Nothing is lost.
import base64
import datetime
import json
import os
import pathlib
import shutil
import struct
import subprocess
import sys
import tempfile

HOME = pathlib.Path.home()
KOK = pathlib.Path(os.environ.get("KIVILCIM_KOK") or HOME / "Library/Mobile Documents/iCloud~md~obsidian/Documents/Personel Data Management/05 - Notlar/Fikirler/Kıvılcım")
ARAC = HOME / "Library/Mobile Documents/iCloud~md~obsidian/Documents/Personel Data Management/_araçlar/kivilcim"
YEDEK = HOME / "Library/Application Support/Kivilcim/gelen-isaret"
LIKES_INBOX = HOME / "Library/Application Support/Kivilcim/gelen-akis"
LOG = HOME / "Library/Logs/Kivilcim-chrome.log"
PYTHONS = [HOME / ".local/share/ema/.venv/bin/python", pathlib.Path("/usr/bin/python3")]
FFMPEG = next((p for p in ("/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg") if os.path.exists(p)), None)


def log(s):
    try:
        LOG.parent.mkdir(parents=True, exist_ok=True)
        with open(LOG, "a", encoding="utf-8") as f:
            f.write(f"{datetime.datetime.now():%Y-%m-%d %H:%M:%S} {s}\n")
    except Exception:  # noqa: BLE001
        pass


def oku():
    n = sys.stdin.buffer.read(4)
    if len(n) < 4:
        return None
    (uz,) = struct.unpack("<I", n)
    return json.loads(sys.stdin.buffer.read(uz).decode("utf-8"))


def gonder(v):
    b = json.dumps(v, ensure_ascii=False).encode("utf-8")
    sys.stdout.buffer.write(struct.pack("<I", len(b)) + b)
    sys.stdout.buffer.flush()


def ses_yaz(ses, hedef_m4a):
    """Chrome's recording (webm/opus or mp4) → AAC .m4a, the format the rest of Kıvılcım reads."""
    ham = base64.b64decode(ses["veri"])
    uz = ".mp4" if "mp4" in (ses.get("tip") or "") else ".webm"
    with tempfile.TemporaryDirectory() as g:
        src = pathlib.Path(g) / ("a" + uz)
        src.write_bytes(ham)
        out = pathlib.Path(g) / "a.m4a"
        if FFMPEG:
            subprocess.run([FFMPEG, "-y", "-loglevel", "error", "-i", str(src), "-ac", "1", "-ar", "16000",
                            "-c:a", "aac", "-b:a", "48k", str(out)], check=True, timeout=120)
        else:
            subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", str(src), str(out)], check=True, timeout=120)
        hedef_m4a.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(out, hedef_m4a)


def kaydet(m):
    isr = m["isaret"]
    isr.setdefault("zaman", datetime.datetime.now().astimezone().isoformat(timespec="seconds"))
    ay = isr["zaman"][:7]
    for kok in (KOK / "isaret" / ay, YEDEK / ay):
        try:
            kok.mkdir(parents=True, exist_ok=True)
            if m.get("ses") and m["ses"].get("veri"):
                ses_yaz(m["ses"], kok / f"{isr['id']}.m4a")
                isr["ses"] = f"{isr['id']}.m4a"
            g = kok / f".{isr['id']}.json.yaziliyor"
            g.write_text(json.dumps(isr, ensure_ascii=False, indent=1), encoding="utf-8")
            g.replace(kok / f"{isr['id']}.json")
            log(f"kaydedildi {isr['id']} → {kok} · {isr.get('url', '')[:90]}")
            isle_baslat()
            return {"ok": True, "yer": "vault" if kok.is_relative_to(KOK) else "bekleme", "id": isr["id"]}
        except PermissionError as e:
            log(f"yazılamadı {kok}: {e}")
            continue
        except Exception as e:  # noqa: BLE001
            log(f"HATA {isr.get('id')}: {e}")
            return {"ok": False, "hata": str(e)[:300]}
    return {"ok": False, "hata": "hiçbir yere yazılamadı"}


def like_save(m):
    """A post liked on X, for tomorrow's daily feed (feed.py). No processing: it only waits to be picked."""
    like = m["like"]
    status = "".join(c for c in str(like.get("status", "")) if c.isdigit())
    if not status or not like.get("url"):
        return {"ok": False, "hata": "post kimliği yok"}
    for folder in (KOK / "Feed" / "x-likes", LIKES_INBOX):
        try:
            folder.mkdir(parents=True, exist_ok=True)
            g = folder / f".{status}.json.yaziliyor"
            g.write_text(json.dumps(like, ensure_ascii=False, indent=1), encoding="utf-8")
            g.replace(folder / f"{status}.json")
            return {"ok": True}
        except PermissionError as e:
            log(f"yazılamadı {folder}: {e}")
    return {"ok": False, "hata": "hiçbir yere yazılamadı"}


def like_remove(m):
    status = "".join(c for c in str(m.get("status", "")) if c.isdigit())
    for folder in (KOK / "Feed" / "x-likes", LIKES_INBOX):
        try:
            (folder / f"{status}.json").unlink()
        except OSError:
            pass
    return {"ok": True}


def isle_baslat():
    if os.environ.get("KIVILCIM_KOK"):
        return   # test run
    """Process right away (fetch the page, transcribe the voice note); isle.py's own lock prevents overlap."""
    py = next((p for p in PYTHONS if p.exists()), None)
    isle = ARAC / "isle.py"
    if not py or not isle.exists():
        return
    try:
        subprocess.Popen([str(py), str(isle)], stdin=subprocess.DEVNULL, stdout=open(os.devnull, "w"),
                         stderr=open(LOG, "a"), start_new_session=True, cwd=str(ARAC))
    except Exception as e:  # noqa: BLE001
        log(f"isle.py başlatılamadı: {e}")


def durum():
    try:
        a = json.loads((KOK / "Dikkat/claude/analiz.json").read_text(encoding="utf-8"))
    except Exception:  # noqa: BLE001
        a = {}
    try:
        d = {o["id"]: o for o in json.loads((KOK / "dizin.json").read_text(encoding="utf-8")).get("ogeler", [])}
    except Exception:  # noqa: BLE001
        d = {}
    simdi = []
    for x in a.get("simdi") or []:
        o = d.get(x.get("id"), {})
        if o.get("status") == "done":
            continue
        simdi.append({"id": x.get("id"), "baslik": o.get("baslik") or x.get("baslik") or "?", "url": o.get("url", ""),
                      "neden": x.get("neden", "")})
    acik = sum(1 for o in d.values() if o.get("kind") == "isaret" and o.get("status") != "done")
    return {"ok": True, "simdi": simdi[:3], "acik": acik, "analiz": a.get("zaman", "")}


def main():
    log(f"başladı (python {sys.version.split()[0]}, kullanıcı {os.getuid()})")
    m = oku()
    if m is None:
        return
    e = m.get("eylem")
    try:
        if e == "kaydet":
            gonder(kaydet(m))
        elif e == "durum":
            gonder(durum())
        elif e == "x_like":
            gonder(like_save(m))
        elif e == "x_unlike":
            gonder(like_remove(m))
        elif e == "ac" and m.get("yol"):
            subprocess.Popen(["open", str(KOK / m["yol"])])
            gonder({"ok": True})
        else:
            gonder({"ok": False, "hata": f"bilinmeyen eylem: {e}"})
    except Exception as ex:  # noqa: BLE001
        log(f"HATA {e}: {ex}")
        gonder({"ok": False, "hata": str(ex)[:300]})


if __name__ == "__main__":
    main()
