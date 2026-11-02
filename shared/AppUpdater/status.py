"""Shows, per Mac, which build of each app it runs compared with the published one.
   python3 status.py"""
import glob
import json
import os

dist = os.environ.get("APP_UPDATER_DIR") or os.path.expanduser(
    "~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Personel Data Management/_araçlar/dagitim")
apps = json.load(open(os.path.join(dist, "manifest.json")))["apps"]
hosts = sorted(os.path.basename(h) for h in glob.glob(os.path.join(dist, "cihazlar", "*")))
print(f"{'app':<16}{'published':<18}" + "".join(f"{h[:22]:<24}" for h in hosts))
for bid, e in sorted(apps.items(), key=lambda kv: kv[1]["name"]):
    row = f"{e['name']:<16}{e['date']:<18}"
    for h in hosts:
        p = os.path.join(dist, "cihazlar", h, f"{bid}.json")
        if not os.path.exists(p):
            cell = "—"
        else:
            r = json.load(open(p))
            cell = ("✓ " if r["build"] == e["build"] else "eski ") + r["seen"][:10]
        row += f"{cell:<24}"
    print(row)

# a Mac appears here only after it opens an app that contains AppUpdater
silent = [a["name"] for bid, a in apps.items()
          if not any(os.path.exists(os.path.join(dist, "cihazlar", h, f"{bid}.json")) for h in hosts)]
print()
if len(hosts) < 2:
    print("Only this Mac has reported. On the other Mac run '_araçlar/dagitim/İlk kurulum.command' once,")
    print("then open each app; its column appears here after the first launch.")
if silent:
    print("Not opened anywhere since publishing: " + ", ".join(sorted(silent)))
