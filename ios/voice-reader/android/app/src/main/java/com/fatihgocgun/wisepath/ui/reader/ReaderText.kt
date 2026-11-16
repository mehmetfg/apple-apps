// The page (port of Views/ReaderTextView.swift): the whole document as a lazy column of paragraphs, so long books
// stay fast. The spoken sentence carries a band and the spoken word a marker; highlights are drawn under the text.
// Only the paragraph holding the spoken word recomposes when the word moves.
//
// The page follows the voice like a book: when the spoken line leaves its place, the page slides so the line sits at
// the chosen height again (Üstte / Ortada). Dragging the text stops following until "Konuşma imlecine git".
package com.fatihgocgun.wisepath.ui.reader

import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.scrollBy
import androidx.compose.foundation.gestures.animateScrollBy
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.State
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fatihgocgun.wisepath.model.Highlight
import com.fatihgocgun.wisepath.settings.PageDim
import com.fatihgocgun.wisepath.settings.ReaderTheme
import com.fatihgocgun.wisepath.settings.Settings
import com.fatihgocgun.wisepath.speech.Spoken
import com.fatihgocgun.wisepath.speech.TextNav
import kotlinx.coroutines.flow.distinctUntilChanged

/** The page's follow state, shared with the reader's "go to the cursor" key. */
class PageFollow {
    var following by mutableStateOf(true)
    /** Set while the page itself scrolls (so a programmatic scroll does not count as the reader's drag). */
    var programmatic = false
}

@Composable
fun ReaderText(
    nav: TextNav,
    spoken: State<Spoken>,
    highlights: List<Highlight>,
    noteMarks: Set<Int>,
    settings: Settings,
    theme: ReaderTheme,
    playing: Boolean,
    listState: LazyListState,
    follow: PageFollow,
    reveal: Int?,
    onRevealed: () -> Unit,
    onTap: (Int) -> Unit,
    onLongPress: (Int) -> Unit,
    contentPadding: PaddingValues,
) {
    val density = LocalDensity.current
    val chapterStarts = remember(nav) { nav.chapters.associateBy { it.offset } }
    val layouts = remember(nav) { mutableStateMapOf<Int, TextLayoutResult>() }
    val baseStyle = TextStyle(
        fontFamily = settings.font.family,
        fontSize = settings.fontSize.sp,
        lineHeight = (settings.fontSize * 1.32 + settings.lineSpacing).sp,
        letterSpacing = (settings.characterSpacing * 0.05).sp,
        color = theme.text,
    )
    val wordColor = settings.wordColor.color
    val lineColor = if (settings.lineColor == com.fatihgocgun.wisepath.settings.MarkColor.paper) theme.band else settings.lineColor.color.copy(alpha = 0.28f)
    val dim = if (settings.focusMode && settings.pageDim == PageDim.off) PageDim.fade else settings.pageDim
    val dimStrength = settings.pageDimStrength.toFloat()

    // the paragraph the voice is in
    val currentBlock by remember(nav) { derivedStateOf { spoken.value.word?.first?.let { nav.blockIndex(it) } ?: spoken.value.sentence?.first?.let { nav.blockIndex(it) } } }

    BoxWithConstraints(Modifier.fillMaxSize()) {
        val viewport = with(density) { maxHeight.toPx() }
        val anchor = viewport * settings.cursorPosition.fraction

        // the reader's own drag stops following
        LaunchedEffect(listState) {
            snapshotFlow { listState.isScrollInProgress }.distinctUntilChanged().collect { scrolling ->
                if (scrolling && !follow.programmatic) follow.following = false
            }
        }
        // following the voice: the spoken line's top kept at the anchor
        LaunchedEffect(nav, follow.following) {
            if (!follow.following) return@LaunchedEffect
            snapshotFlow {
                val w = spoken.value.word ?: spoken.value.sentence
                val at = w?.first ?: return@snapshotFlow null
                val bi = nav.blockIndex(at)
                val layout = layouts[bi]
                val line = layout?.let { l -> l.getLineForOffset((at - nav.blocks[bi].first).coerceIn(0, maxOf(0, l.layoutInput.text.length - 1))) }
                Triple(bi, line ?: 0, layout?.getLineTop(line ?: 0) ?: 0f)
            }.distinctUntilChanged().collect { t ->
                t ?: return@collect
                val (bi, _, lineTop) = t
                val info = listState.layoutInfo.visibleItemsInfo.firstOrNull { it.index == bi }
                val target = if (info != null) info.offset + lineTop else null
                follow.programmatic = true
                try {
                    if (target == null) { listState.scrollToItem(bi, 0); listState.scrollBy(lineTop - anchor) }
                    else {
                        val delta = target - anchor
                        // move only when the line has left the band around its place
                        if (delta > viewport * 0.30f || delta < -viewport * 0.05f) listState.animateScrollBy(delta)
                    }
                } finally { follow.programmatic = false }
            }
        }
        // a place to show (a search hit, a mark, a note): brought on screen without moving the reading place
        LaunchedEffect(reveal) {
            val at = reveal ?: return@LaunchedEffect
            follow.following = false
            val bi = nav.blockIndex(at)
            follow.programmatic = true
            listState.scrollToItem(bi, 0)
            follow.programmatic = false
            onRevealed()
        }

        LazyColumn(state = listState, contentPadding = contentPadding, modifier = Modifier.fillMaxSize()) {
            items(nav.blocks.size, key = { it }) { bi ->
                val range = nav.blocks[bi]
                val heading = chapterStarts[range.first]
                val local by remember(bi, nav) {
                    derivedStateOf {
                        val s = spoken.value
                        val w = s.word?.takeIf { it.first in range || it.last in range }
                        val sen = s.sentence?.takeIf { it.first <= range.last && it.last >= range.first }
                        w to sen
                    }
                }
                val isCurrent = currentBlock == bi
                val annotated = remember(range, highlights, local, settings.showSpokenWord, settings.showSpokenLine, wordColor, lineColor, playing, theme, noteMarks) {
                    build(nav.text, range, highlights, noteMarks, local.first.takeIf { settings.showSpokenWord }, local.second.takeIf { settings.showSpokenLine },
                        wordColor, lineColor, theme, dimmedOutsideSentence = playing && dim != PageDim.off && isCurrent, dimStrength)
                }
                val alpha = if (playing && dim != PageDim.off && currentBlock != null && !isCurrent) {
                    val dist = kotlin.math.abs(bi - (currentBlock ?: bi))
                    when (dim) {
                        PageDim.window -> if (dist <= 1) 1f else 1f - dimStrength
                        PageDim.spotlight -> (1f - dimStrength * minOf(1f, dist / 4f)).coerceAtLeast(0.1f)
                        else -> 1f - dimStrength
                    }
                } else 1f
                val style = if (heading != null) baseStyle.copy(
                    fontWeight = FontWeight.Bold,
                    fontSize = (settings.fontSize * if (heading.level <= 1) 1.35 else 1.15).sp,
                    lineHeight = (settings.fontSize * (if (heading.level <= 1) 1.35 else 1.15) * 1.3).sp,
                ) else baseStyle
                Box(
                    Modifier.fillMaxWidth()
                        .graphicsLayer { this.alpha = alpha }
                        .padding(horizontal = 22.dp)
                        .padding(top = if (heading != null) 22.dp else 0.dp, bottom = (settings.fontSize * 0.6).dp)
                ) {
                    Text(
                        annotated, style = style,
                        onTextLayout = { layouts[bi] = it },
                        modifier = Modifier.pointerInput(range) {
                            detectTapGestures(
                                onTap = { p -> layouts[bi]?.let { onTap(range.first + it.getOffsetForPosition(p)) } },
                                onLongPress = { p -> layouts[bi]?.let { onLongPress(range.first + it.getOffsetForPosition(p)) } },
                            )
                        },
                    )
                }
                if (dim == PageDim.dusk && playing && !isCurrent) Unit
            }
        }
    }
}

private suspend fun LazyListState.animateScrollBy(delta: Float) {
    (this as androidx.compose.foundation.gestures.ScrollableState).animateScrollBy(delta, androidx.compose.animation.core.tween(380))
}

private fun build(
    text: String, range: IntRange, highlights: List<Highlight>, noteMarks: Set<Int>, word: IntRange?, sentence: IntRange?,
    wordColor: Color, lineColor: Color, theme: ReaderTheme, dimmedOutsideSentence: Boolean, dimStrength: Float,
): AnnotatedString {
    val start = range.first
    val end = range.last + 1
    fun local(a: Int, b: Int): Pair<Int, Int>? {
        val x = maxOf(a, start) - start
        val y = minOf(b, end) - start
        return if (y > x) x to y else null
    }
    return buildAnnotatedString {
        append(text, start, end)
        if (dimmedOutsideSentence && sentence != null) {
            val faded = SpanStyle(color = theme.text.copy(alpha = 1f - dimStrength))
            local(start, sentence.first)?.let { addStyle(faded, it.first, it.second) }
            local(sentence.last + 1, end)?.let { addStyle(faded, it.first, it.second) }
        }
        if (sentence != null) local(sentence.first, sentence.last + 1)?.let { addStyle(SpanStyle(background = lineColor), it.first, it.second) }
        for (h in highlights) {
            if (h.end <= start || h.location >= end) continue
            local(h.location, h.end)?.let {
                addStyle(SpanStyle(background = Color(h.color.argb).copy(alpha = if (theme.isDark) 0.45f else 0.55f)), it.first, it.second)
                if (h.note != null || h.location in noteMarks) addStyle(SpanStyle(textDecoration = androidx.compose.ui.text.style.TextDecoration.Underline), it.first, it.second)
            }
        }
        for (n in noteMarks) local(n, n + 1)?.let { addStyle(SpanStyle(textDecoration = androidx.compose.ui.text.style.TextDecoration.Underline), it.first, it.second) }
        if (word != null) local(word.first, word.last + 1)?.let {
            val onWord = if (wordColor.luminance() > 0.5f) Color.Black else Color.White
            addStyle(SpanStyle(background = wordColor, color = onWord), it.first, it.second)
        }
    }
}

private fun Color.luminance(): Float = 0.2126f * red + 0.7152f * green + 0.0722f * blue

@Suppress("unused") private val unusedSize = 1.sp
