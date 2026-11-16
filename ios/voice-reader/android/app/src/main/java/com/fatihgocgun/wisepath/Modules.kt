// The optional parts of the app hook themselves into AppModel here, once, when it is created.
package com.fatihgocgun.wisepath

import com.fatihgocgun.wisepath.notes.MicButton
import com.fatihgocgun.wisepath.notes.NoteOverlays
import com.fatihgocgun.wisepath.ui.Slots
import androidx.compose.ui.unit.dp

object Modules {
    fun install(app: AppModel) {
        // notes: the recording strip and toast over the reader, and the reader's microphone key
        Slots.noteOverlays = { NoteOverlays() }
        Slots.micButton = { MicButton(size = 44.dp) }

        // moving modes: ⏭ marks the sentence and ⏮ starts a voice note while bike mode is on
        com.fatihgocgun.wisepath.move.installRideKeys(app)

        // automation: the runner takes the book-finished and segment hooks; its line shows under the mini player
        com.fatihgocgun.wisepath.automation.AutomationRunner.install(app)
        Slots.automationStatus = { com.fatihgocgun.wisepath.automation.AutomationStatusLine() }

        // widgets, launcher shortcuts and the evening review follow the player, the library and the listening log
        com.fatihgocgun.wisepath.widget.WidgetFeed.attach(app)
        com.fatihgocgun.wisepath.shortcuts.installShortcuts(app.context)
        val previousOnSave = app.log.onSave
        app.log.onSave = { snapshot ->
            previousOnSave?.invoke(snapshot)
            com.fatihgocgun.wisepath.evening.scheduleEvening(app)
        }

        // cloud voices (ElevenLabs, OpenAI, Google, Azure) and folder sync; last, so they keep the hooks set above
        com.fatihgocgun.wisepath.cloud.installCloud(app)
        com.fatihgocgun.wisepath.sync.installSync(app)
    }
}
