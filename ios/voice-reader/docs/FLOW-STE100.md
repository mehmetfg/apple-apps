# Wise Path — logical data flow and fault points

Written in ASD-STE100 Simplified Technical English (Issue 9).
Map: `Artifacts/wise-path-akis.html` (source: `docs/wisepath-flow.dataflow.json`, archify dataflow).
Date: 2026-10-28.

## 1. Purpose

This document tells you how data moves in the Wise Path application.
It also tells you where the flow can stop and what to do.

## 2. Components

| Component | Location | Function |
|---|---|---|
| Documents (Belgeler) | Files, clipboard, AirDrop, drop folder | Supply the text. |
| User (Sen) | Phone screen, headphone keys | Starts and stops reading. Makes marks, voice notes and GPS records. |
| Importer (İçe aktarıcı) | `Import/DocumentImporter` | Changes EPUB, PDF, DOCX, HTML, RTF and TXT into plain text. Runs in the background. |
| Library (Kütüphane) | `Model/LibraryStore`, `library.json`, `docs/<id>/` | Keeps the documents, the text, the covers and the marks. |
| Speech engine (Ses motoru) | `Speech/SpeechPlayer`, `VoiceMaster` | Reads the text aloud. Moves the cursor. |
| Place log (Yer defteri) | `places.json` | Keeps the exact reading place. Writes in 1 second or less. |
| Records (Kayıtlar) | `Listening/`, `Notes/`, `workouts/` | Keep listening time, notes and routes. |
| App Group | `group.com.fatihgocgun.okur` | Shares a snapshot and small covers with the widgets. |
| iCloud and vault | `_araçlar/voice-reader/durum/` | Copy the records to the Mac. |
| Screens (Ekranlar) | `Views/` | Show the library, the reader, the road screen and the statistics. |
| Widgets | `WisePathWidgets` | Show the current book, the books in progress, statistics and quotes. |
| Mac | Teoria, PDM network (`_bus`) | Read the records. |

## 3. Main flow

1. The user adds a document.
2. The importer changes the document into text.
3. The library keeps the text and the cover.
4. The user pushes play.
5. The speech engine reads the text from the library.
6. The speech engine sends the cursor position each 2 seconds.
7. The place log keeps the exact position.
8. The library list changes only when the percentage changes.
9. The screens show the new percentage.

Note: Step 8 is new (2026-10-28). Before this change, each position update changed the library list.
Then all screens drew again each 2 seconds. This caused stops in the interface.

## 4. Record flow

1. The user makes a voice note, a mark or a GPS route.
2. The application writes the record to the phone.
3. The application writes a copy to the vault folder in iCloud.
4. iCloud sends the copy to the Mac.
5. The Mac applications read the record.

## 5. Widget flow

1. The application writes a snapshot to the App Group folder.
2. The application writes a small cover for each book.
3. WidgetKit draws the widgets again.
4. When you touch a widget, the application opens with a `wisepath://` link.

## 6. Fault points

### 6.1 iCloud does not send records to the Mac

Symptom: The record is on the phone. The record is not on the Mac.
Cause: The phone writes the file to the iCloud folder. iCloud does not upload the file.
This occurred from 2026-10-26 to 2026-10-28. The fault is in iCloud, not in the application.

Procedure:
1. Connect the phone to the Mac with a cable, or put them on the same network.
2. Unlock the phone.
3. Wait 10 minutes. The Mac application Kıvılcım gets the missing voice notes with `devicectl`.
4. For Wise Path data, Teoria uses `veri/voicereader_phone.py`.
5. If the fault continues, open Settings > Apple Account > iCloud > iCloud Drive on the phone.
6. Set "Sync this iPhone" to off. Then set it to on.

### 6.2 The widgets show old data

Symptom: The widget shows an old percentage.
Cause: The application writes the snapshot only at these times: when reading pauses, when the application goes to the background, and when the number of books changes.

Procedure:
1. Pause the reading.
2. Or close the application.
3. The widgets show the new data in a few seconds.

### 6.3 The installation of the widgets fails

Symptom: The installation script shows "No Accounts".
Cause: Xcode has no Apple account. The App Group needs a provisioning profile.

Procedure:
1. Open Xcode > Settings > Accounts.
2. Add the Apple account.
3. Run `zsh telefona-kur.sh` again.

## 7. Corrected faults

| Fault | Cause | Correction |
|---|---|---|
| The interface stopped during reading. | Each position update changed the library list. | The list changes only at a new percentage. The place log keeps the exact position. |
| The reader skipped text on iOS 27. | iOS 27 sends an empty audio buffer before the end. | The engine uses the `didFinish` message to find the end. |
| Music mode stopped Spotify. | The application changed the audio session while it was active. | The application releases the session first. Then it changes the category. |
| The screen went dark in music mode. | The paused reader set the idle timer again. | Music mode keeps the screen on. |

## 8. Limits

- This document does not tell about the Mac applications in detail.
- The map shows 12 components. It does not show the automation, the music mode or the voice settings.
