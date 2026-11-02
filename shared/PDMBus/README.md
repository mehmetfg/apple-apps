# PDMBus

The Swift package of the PDM bus. The bus is a folder in the vault (`_bus/`). Its manual is
`_bus/README.md` in the vault (ASD-STE100). Section 7.1 of that manual tells how to connect an app.

| File | Content |
|---|---|
| `PDMEvent.swift` | One event (one JSON line). `PDMValue` for the `data` object. `PDMSubject` helpers. |
| `PDMBus.swift` | `emit()` into the App Group outbox, `sync()` to the vault, `cachedWords()` / `cachedToday()`. |
| `PDMState.swift` | Codable models of `words.json` and `today.json`, and the small `PDMWordSummary` for widgets. |
| `PDMVault.swift` | The vault bookmark, the simulator test hook `PDM_VAULT`, and the `_bus` check. |
| `PDMSettingsSection.swift` | The "PDM Ağı" settings section (Turkish interface text). |
| `link_xcode.py` | Adds the package and the App Group to Xcode targets. Running it again changes nothing. |

Tests (on the Mac, with no App Group):

```bash
PDM_CONTAINER=$(mktemp -d) swift test
```
