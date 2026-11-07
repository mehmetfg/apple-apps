# SBS — personal health information system (iPhone)

Three tabs in the manner of the Health app: Insights, Longevity, Browse. Liquid Glass, iOS 26+.

- `ios/SBS/Model.swift`: the shape of `sbs.json` (markers, areas, highlights, conditions, episodes, ledger).
- `ios/SBS/Store.swift`: reads `02 - Eudomonia/Beden/SBS/state/sbs.json` from the vault (PDMVault bookmark), keeps a copy,
  writes Apple Health day summaries and inbox documents to `SBS/phone/<device>/`.
- `ios/SBS/Health.swift`: HealthKit, last 30 days; writes only weight and waist.
- `ios/SBS/Graphics.swift`: segmented ring, arc gauge, typical band, sparkline, petal wheel, body figure.
- `ios/SBS/Report.swift`: the three-page doctor report as a PDF.
- `ios/proje_uret.py`: writes the Xcode project and links the PDMBus package.
- `ikon/icon.py`: draws the three icon variants.

The Mac side (the ledger builder `sbs.py`, the assets, the procedure for Claude) lives in the private vault.
`ios/SBS/snapshot.json` is personal data copied at install time; it is gitignored.

Test in the simulator with preview health data and the real vault file:

    SIMCTL_CHILD_SBS_TAB=longevity xcrun simctl launch <udid> com.fatihgocgun.sbs -demoHealth -health.asked YES

Install on the phone: `zsh telefona-kur.sh` (needs the Apple account in Xcode).
