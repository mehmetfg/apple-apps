package com.fatihgocgun.wisepath.core

import com.fatihgocgun.wisepath.model.AppJson
import com.fatihgocgun.wisepath.model.DocumentRecord
import com.fatihgocgun.wisepath.speech.LanguageGuess
import com.fatihgocgun.wisepath.speech.TextNav
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class CoreTest {
    @Test fun appleDatesRoundTrip() {
        // 2024-01-01T00:00:00Z is 725760000 s after 2001-01-01
        val json = """{"id":"A","title":"Kitap","addedAt":725760000}"""
        val d = AppJson.decodeFromString<DocumentRecord>(json)
        assertEquals(1704067200000L, d.addedAt)
        val back = AppJson.encodeToString(d)
        assertTrue(back, back.contains("\"addedAt\":7.2576E8") || back.contains("\"addedAt\":725760000"))
    }

    @Test fun unknownFieldsAreIgnored() {
        val d = AppJson.decodeFromString<DocumentRecord>("""{"id":"B","title":"X","someFutureField":[1,2],"addedAt":0}""")
        assertEquals("X", d.title)
    }

    @Test fun sentencesAndBlocks() {
        val text = "Birinci cümle. İkinci cümle!\nYeni paragraf burada.\n"
        val nav = TextNav(text)
        assertEquals(2, nav.blocks.size)
        val r = nav.sentenceRange(text.indexOf("İkinci"))!!
        assertEquals("İkinci cümle!", nav.substring(r).trim())
        assertEquals(1, nav.blockIndex(text.indexOf("Yeni")))
        assertEquals("paragraf", nav.substring(nav.wordRange(text.indexOf("paragraf") + 2)))
    }

    @Test fun languageGuess() {
        assertEquals("tr", LanguageGuess.detect("Bu bir deneme metnidir ve okuma için yazılmıştır, çünkü ben de okurum."))
        assertEquals("en", LanguageGuess.detect("This is a test text and it was written for the reader, because they read."))
    }
}
