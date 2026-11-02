"""Copies a published zip into the shared folder and records it in manifest.json (called by publish.sh)."""
import datetime
import fcntl
import hashlib
import json
import os
import plistlib
import shutil
import subprocess
import sys

dist, zip_path, app, name, build = sys.argv[1:6]
with open(os.path.join(app, "Contents", "Info.plist"), "rb") as f:
    bundle_id = plistlib.load(f)["CFBundleIdentifier"]
sha = hashlib.sha256(open(zip_path, "rb").read()).hexdigest()
host = subprocess.run(["scutil", "--get", "ComputerName"], capture_output=True, text=True).stdout.strip()

with open("/tmp/app-updater-manifest.lock", "w") as lock:
    fcntl.flock(lock, fcntl.LOCK_EX)
    # zip first, manifest second: a Mac that sees the new manifest must find the zip (or wait for its hash)
    target = os.path.join(dist, f"{name}.zip")
    shutil.copyfile(zip_path, target + ".tmp")
    os.replace(target + ".tmp", target)
    path = os.path.join(dist, "manifest.json")
    try:
        manifest = json.load(open(path))
    except (OSError, ValueError):
        manifest = {"apps": {}}
    manifest.setdefault("apps", {})[bundle_id] = {
        "name": os.path.basename(app)[:-4],
        "file": f"{name}.zip",
        "build": build,
        "sha256": sha,
        "size": os.path.getsize(target),
        "date": datetime.datetime.now().strftime("%Y-%m-%d %H:%M"),
        "host": host,
    }
    manifest["updated"] = datetime.datetime.now().isoformat(timespec="seconds")
    with open(path + ".tmp", "w") as f:
        json.dump(manifest, f, ensure_ascii=False, indent=2, sort_keys=True)
    os.replace(path + ".tmp", path)
print(f"published {name}.zip build {build} ({os.path.getsize(target) // 1024} KB)")
