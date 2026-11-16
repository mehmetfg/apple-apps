# Wise Path for Android — porting notes

The Android app is a Kotlin + Jetpack Compose port of the iPhone app in `../ios/VoiceReader`. The iOS Swift sources
are the specification: same features, same Turkish UI texts, same file formats (so data can move between the apps).

## Build

```
cd ios/voice-reader/android
export JAVA_HOME=/opt/homebrew/opt/openjdk@17
./gradlew assembleDebug            # app/build/outputs/apk/debug/app-debug.apk
./gradlew testDebugUnitTest        # JVM unit tests
```

Kotlin 1.9.24, Compose compiler 1.5.14 (Compose BOM 2024.06.00, Material 3), AGP 8.5.2, Gradle 8.9, compileSdk 34,
minSdk 26. Libraries already in `app/build.gradle.kts`: kotlinx-serialization-json, coroutines, navigation-compose,
androidx.media (MediaSessionCompat), Glance app widgets, WorkManager, DocumentFile, pdfbox-android. No Google Play
services (the app must run on any Android).

## Layout (package `com.fatihgocgun.wisepath`)

| Package | What | iOS source |
|---|---|---|
| `model/Records.kt` | DocumentRecord, Highlight, Bookmark, Chapter, DocumentContent, ImportedDocument, `AppJson` | Model/Records.swift |
| `store/LibraryStore.kt` | library.json, places.json, docs/<id>/content.json, cover.jpg; StateFlows | Model/LibraryStore.swift |
| `settings/Settings.kt` | every preference as Compose state + the enums | Model/Settings.swift |
| `speech/TextNav.kt` | paragraphs, sentences, words, navigation targets; SpokenText; LanguageGuess | SpeechPlayer.swift (helpers), SpokenText.swift |
| `speech/SpeechBackend.kt` | SpeechBackend interface, TtsBackend (Android TextToSpeech) | — |
| `speech/SpeechPlayer.kt` | the reading engine: queue, word tracking, sleep timer, breaks, segments, audio focus | Speech/SpeechPlayer.swift |
| `speech/PlaybackService.kt` | foreground media service, MediaSession, notification, headset keys | — |
| `stats/ListeningLog.kt` | the listening log (data) | Model/ListeningLog.swift |
| `notes/NoteStore.kt`, `notes/NoteRecorder.kt` | notes log (data), voice recording + on-device transcription | Model/NoteStore.swift, Speech/NoteRecorder.swift |
| `AppModel.kt` | the singleton: open, import, marks, notes, folders, media keys | AppModel*.swift |
| `Util.kt` | `Format` (Turkish durations/dates), `TextFold` (accent-insensitive search), `Haptics` | — |
| `Modules.kt` | the optional parts hook into AppModel here | — |
| `ui/` | Theme, AppNav (all routes), library, reader, settings | Views/*.swift |

## Conventions

- Positions are UTF-16 offsets = Kotlin `String` indices. Ranges in Kotlin are `IntRange` (`first..last`, inclusive).
- Dates in files are Apple reference-date seconds (`Instant` typealias in Records.kt); ids are upper-case UUIDs.
- Files live under `context.filesDir/WisePath/` (`AppModel.root`).
- `AppModel.get(context)` is the one model. `app.player.state` / `app.player.spoken` are StateFlows;
  `app.store.documents` / `app.store.folders` are StateFlows; `app.settings.*` are Compose state.
- UI text is Turkish, the same words as the iOS app. Comments in English, explaining why.
- Every screen is a `@Composable` taking callbacks; navigation lives in `ui/AppNav.kt` (`Routes`).

## Status (2026-11-16)

All modules ported; `assembleDebug`, `assembleRelease`, `testDebugUnitTest` (20 tests) and `lintDebug` pass.
Not yet run on a device or emulator.

| Area | Package | State |
|---|---|---|
| Library, shelves, covers, folders, book menu | `ui/library` | done |
| Reader, follow scroll, panels (ses, görsel, konumlar, arama, hız, seçim) | `ui/reader` | done |
| Speech (Android TTS, word ranges, music breaks, active wait, media session) | `speech` | done |
| Import: EPUB, PDF, DOCX, ODT, FB2, HTML, RTF, TXT, MD, MOBI/AZW, .doc | `importer` | done (PDF untested on device) |
| Stats, today card, notes, voice notes, transcription | `stats`, `notes` | done |
| Bike / walk recording, Yollarım, music mode | `move`, `music` | done |
| Automation, widgets, shortcuts, evening review, book search, prompts | `automation`, `widget`, `shortcuts`, `evening`, `search`, `prompt` | done |
| Cloud voices (ElevenLabs, OpenAI, Google, Azure) | `cloud` | done |
| Sync through a picked folder (iOS file formats), vault copy | `sync` | done |

Left out (iOS-only): neural voices (Ema, Siri, FastSpeech, Supertonic), VoiceMaster / system pitch, Studio packs,
Teoria / PDMBus, iCloud (replaced by a SAF folder), camera scan OCR, quote and "Okuduklarım" widgets, Live Activities,
Siri phrases, SF-Symbol images in kinetic type.
