# apple-apps

Personal iPhone and Mac apps built around one learning practice: reading and listening
(philosophy, sciences, engineering) and English. They are written in SwiftUI. The user
interface is in Turkish.

| App | Platform | What it does |
|---|---|---|
| [teoria](multiplatform/teoria) | iOS + macOS | A reader and memory app for listened books. Highlights from Voice Dream, a paged reader with speech, concept practice, and a curriculum view. |
| [tezgah](multiplatform/tezgah) | iOS + macOS | A shell for the daily study workbenches. A WebKit app on the Mac and a read-only dashboard on the iPhone. |
| [kivilcim](multiplatform/kivilcim) | iOS + macOS | Voice idea capture from the lock screen or a menu bar hotkey. Whisper transcribes on the Mac. |
| [atrium](multiplatform/atrium) | iOS + macOS | A daily overview of the notes vault. |
| [cumle](macos/cumle) | macOS | A sentence-writing workbench for English (Turkish → English, with a hint ladder). |
| [cekmece](macos/cekmece) | macOS | A menu bar launcher for the apps listed here. |
| [kenar](ios/kenar) | iOS | Ties reading to one text: highlights, a camera inbox, an argument map, and a 60-second spoken explanation. |
| [asina](ios/asina) | iOS | Vocabulary with FSRS spaced repetition, widgets and phrasal verbs. |
| [ayna](ios/ayna) | iOS | Tell your day in English, then get corrected audio back the next morning. |
| [disli](ios/disli) | iOS | GramerApp: English grammar topics, laws, quizzes and games. |
| [memories](ios/memories) | iOS | Prepares the English writing session with audio the day before. |
| [saray](ios/saray) | iOS | An on-device object detection camera that labels things at home in English. |
| [engineering](ios/engineering) | iOS | Software engineering basics: lessons, algorithm visualisations, Python and C snippets. |
| [orkestra](ios/orkestra) | iOS | A read-only coordinator that shows which study processes are flowing or stuck. |
| [vitrin](ios/vitrin) | iOS | Builds lock screen wallpapers and widgets from words and quotes. |
| [tini](ios/tini) | iOS | A FLAC player with its own DSP chain that mixes with audiobook apps. |
| [ema](ios/ema) | iOS | An experimental on-device Turkish TTS (ONNX + eSpeak NG). |
| [fon](ios/fon) | iOS | Background music under spoken audio. Retired and replaced by tini. |

## How it is built

- iOS apps: open `ios/<App>.xcodeproj` in Xcode 16 or later.
- Mac apps have no Xcode project. Run `mac/derle.sh` (or `mac/build.sh`) to build with `swiftc`.
- At runtime the apps read and write data in a private Obsidian vault on iCloud Drive.
  That data, the generator scripts and some embedded files are not in this repository
  (see `.gitignore`). The ML models for `saray` and `ema` are not included either.

The signing team and bundle identifiers are the author's own. Change them before you build.
