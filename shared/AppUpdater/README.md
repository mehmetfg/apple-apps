# AppUpdater

Self-update for the Mac apps through the shared iCloud folder
(vault › `_araçlar/dagitim`, user notes in its README.md).

- `AppUpdater.swift` — compiled into every Mac app; call `AppUpdater.start()` once at launch.
  At launch a newer build installs without asking; an hourly check asks first.
- `publish.sh <App.app> <ZipName>` — called at the end of each `derle.sh`/`build.sh`:
  stamps `CFBundleVersion` (yyyyMMddHHmmss), re-signs with the same identity, runs `manifest.py`.
- `manifest.py` — copies the zip (zip first, manifest second) and updates `manifest.json` under a lock.
- `status.py` — table of builds per Mac from `cihazlar/`.

`APP_UPDATER_DIR` overrides the folder in all four (used for tests).
Wired into: Atrium, Cümle, Kıvılcım, Tekne, Teoria, Tezgâh, Uygulamalarım.
New Mac app: add `$UPDATER/AppUpdater.swift` to the compile line, call `AppUpdater.start()`,
and run `zsh "$UPDATER/publish.sh" "$APP" <ZipName>` after `codesign`.
