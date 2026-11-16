// What changed in the library, as one line of the append-only event log the iOS app writes
// (Events/<device>.jsonl in iCloud Drive › Voice Reader). Same JSON shape as SyncEngine.swift's SyncEvent.
package com.fatihgocgun.wisepath.sync

import com.fatihgocgun.wisepath.model.Bookmark
import com.fatihgocgun.wisepath.model.Highlight
import com.fatihgocgun.wisepath.model.Instant
import com.fatihgocgun.wisepath.model.newId
import com.fatihgocgun.wisepath.model.now
import kotlinx.serialization.Serializable

@Serializable
enum class SyncKind {
    highlightAdd, highlightRemove, highlightNote, bookmarkAdd, bookmarkRemove,
    docFolder, docFlag, docTitle, docDelete, folderAdd, folderRemove, folderRename,
}

@Serializable
data class SyncEvent(
    val id: String = newId(),
    val at: Instant = now(),
    val kind: SyncKind,
    val doc: String? = null,
    val highlight: Highlight? = null,
    val bookmark: Bookmark? = null,
    val ref: String? = null,
    val text: String? = null,
    val text2: String? = null,
)

/** Where the library's changes go for the other devices (the sync engine registers itself here). */
interface SyncSink {
    fun record(event: SyncEvent)
    fun positionsChanged()
}
