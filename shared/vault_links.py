#!/usr/bin/env python3
"""Keep the links between the PDM vault (iCloud) and this repo working on every Mac.

The two Macs have different home folders (/Users/mfg, /Users/fatihgocgun), so an absolute
link made on one Mac is broken on the other. This script stores every vault <-> repo link
relative to the home folder in `vault-links.json`, and makes each link relative to its own
folder, so the same link works on both Macs.

  python3 shared/vault_links.py scan    # record the links of this Mac (overwrites the list)
  python3 shared/vault_links.py apply   # create or repair the links (safe to run again)
  python3 shared/vault_links.py check   # report broken or missing links

Rules: `apply` never replaces a real file or folder; it only creates or rewrites links.
The repo must be at ~/Documents/projects/apple-apps on both Macs.
"""
import json
import os
import sys
from pathlib import Path

HOME = Path.home()
REPO = Path(__file__).resolve().parent.parent
VAULT = HOME / "Library/Mobile Documents/iCloud~md~obsidian/Documents/Personel Data Management"
LIST = Path(__file__).resolve().parent / "vault-links.json"
SKIP = {".git", ".obsidian", "node_modules", "build", "DerivedData", ".build"}


def home_rel(p: Path) -> str:
    return str(p.relative_to(HOME))


def walk_links(root: Path):
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP and not os.path.islink(os.path.join(dirpath, d))]
        for name in filenames + [d for d in os.listdir(dirpath) if os.path.islink(os.path.join(dirpath, d)) and os.path.isdir(os.path.join(dirpath, d))]:
            p = Path(dirpath) / name
            if p.is_symlink():
                yield p


def resolve_target(link: Path) -> Path:
    raw = os.readlink(link)
    if raw.startswith("/"):
        # an absolute link made on any Mac: keep the part after the home folder
        parts = Path(raw).parts
        if len(parts) > 3 and parts[1] == "Users":
            return HOME.joinpath(*parts[3:])
        return Path(raw)
    return (link.parent / raw).resolve(strict=False)


def scan():
    entries = {}
    for root, other in ((VAULT, REPO), (REPO, VAULT)):
        for link in walk_links(root):
            target = resolve_target(link)
            try:
                target.relative_to(other)
            except ValueError:
                continue  # link stays inside one tree (already portable)
            entries[home_rel(link)] = home_rel(target)
    LIST.write_text(json.dumps(dict(sorted(entries.items())), ensure_ascii=False, indent=1) + "\n")
    print(f"recorded {len(entries)} links -> {LIST.name}")


def apply(dry=False):
    entries = json.loads(LIST.read_text())
    made = fixed = kept = skipped = 0
    for link_rel, target_rel in entries.items():
        link, target = HOME / link_rel, HOME / target_rel
        want = os.path.relpath(target, link.parent)
        if link.is_symlink():
            if os.readlink(link) == want:
                kept += 1
                continue
            if not dry:
                link.unlink()
                link.symlink_to(want)
            fixed += 1
        elif link.exists():
            skipped += 1
            print(f"skip (real file here): {link_rel}")
        else:
            if not link.parent.exists():
                skipped += 1
                print(f"skip (no folder): {link_rel}")
                continue
            if not dry:
                link.symlink_to(want)
            made += 1
    print(f"links: {made} made, {fixed} made relative, {kept} already fine, {skipped} skipped")


def check():
    entries = json.loads(LIST.read_text())
    bad = [k for k, v in entries.items() if not (HOME / k).is_symlink() or not (HOME / k).exists()]
    for k in bad:
        print(f"broken or missing: {k}")
    print(f"{len(entries) - len(bad)}/{len(entries)} links work")
    return 1 if bad else 0


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "check"
    if cmd == "scan":
        scan()
    elif cmd == "apply":
        apply(dry="--dry" in sys.argv)
    else:
        sys.exit(check())
