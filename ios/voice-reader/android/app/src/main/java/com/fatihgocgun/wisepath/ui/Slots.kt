// Places in the core screens where optional parts draw (set from Modules.install), so the library and the reader do
// not depend on every part being there.
package com.fatihgocgun.wisepath.ui

import androidx.compose.runtime.Composable

object Slots {
    /** Under the mini player's title while an automation runs. */
    var automationStatus: @Composable () -> Unit = {}
    /** Over the reader and the ride screen: the note toast and the recording strip. */
    var noteOverlays: @Composable () -> Unit = {}
    /** The reader's microphone key (voice note on the sentence being read). */
    var micButton: @Composable () -> Unit = {}
}
