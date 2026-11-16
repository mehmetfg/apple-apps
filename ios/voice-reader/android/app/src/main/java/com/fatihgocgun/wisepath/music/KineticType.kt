// Kinetik: a sentence as kinetic typography (port of KineticType.swift). It is cut into short phrases (at punctuation,
// three to five words); each phrase is set as one composition and its words land one by one. Four compositions, as
// in lyric and title sequences: a justified stack (every word as wide as the column), a vertical key word on the side
// with the rest stacked beside it, a giant key word with the small words spaced above and below, and the stack tilted.
// Small words (ve, bir, ile…) are set small in capitals with wide spacing; the phrase's key word is the largest and
// warm-coloured. The iOS image dictionary (SF Symbols behind key words) is left out: Android has no such symbol set.
package com.fatihgocgun.wisepath.music

import android.os.Build
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleOut
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fatihgocgun.wisepath.AppModel
import java.util.Locale

private val tr = Locale("tr", "TR")

data class KineticPhrase(val id: Int, val words: List<String>, val key: Int, val layout: Layout) {
    enum class Layout { stack, side, giant, tilt }

    /** Beats the phrase takes in Müzik modu: one a word. */
    val beats: Int get() = words.size

    companion object {
        val small: Set<String> = setOf("ve", "bir", "bu", "şu", "o", "da", "de", "ile", "ki", "için", "gibi", "ne", "en", "çok", "daha",
            "her", "mi", "mı", "ama", "ya", "olan", "olarak", "değil", "kadar", "sonra", "önce", "hem", "ise", "veya", "the", "a", "an",
            "of", "to", "and", "in", "is", "on", "bütün", "tüm", "nasıl", "neden", "çünkü", "eğer", "yani", "artık", "hiç", "biz", "ben", "sen")

        fun clean(w: String): String = w.trim { !it.isLetterOrDigit() }.lowercase(tr)

        /** A sentence into phrases: a phrase ends at a comma, colon, dash or full stop, or after five words. */
        fun phrases(text: String, seed: Int): List<KineticPhrase> {
            val words = text.split(' ', '\n').filter { it.isNotEmpty() }
            val groups = ArrayList<MutableList<String>>()
            var cur = ArrayList<String>()
            for (w in words) {
                cur.add(w)
                val ends = w.lastOrNull()?.let { it in ",;:.!?—–" } ?: false
                if (cur.size >= 5 || (ends && cur.size >= 2)) { groups.add(cur); cur = ArrayList() }
            }
            if (cur.isNotEmpty()) {
                if (cur.size == 1 && groups.isNotEmpty()) groups.last().addAll(cur) else groups.add(cur)
            }
            return groups.mapIndexed { i, g ->
                val key = g.indices.maxByOrNull { j -> val c = clean(g[j]); if (c in small) -1 else c.length } ?: 0
                var layout = Layout.entries[Math.floorMod(seed * 3 + i, 4)]
                if (layout == Layout.side && (clean(g[key]).length < 4 || g.size < 2)) layout = Layout.stack
                KineticPhrase(i, g, key, layout)
            }
        }
    }
}

/** A word that fills `width` (shrinking from `maxSize` until it fits on one line). */
@Composable
fun FitText(
    text: String, width: Dp, maxSize: Float, color: Color, weight: FontWeight, family: FontFamily = FontFamily.Default,
    italic: Boolean = false, shadow: Color? = null, modifier: Modifier = Modifier,
) {
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    val style = TextStyle(fontSize = maxSize.sp, fontWeight = weight, fontFamily = family,
        fontStyle = if (italic) FontStyle.Italic else FontStyle.Normal)
    val size = remember(text, width, maxSize, weight, family, italic) {
        val w = measurer.measure(text, style, maxLines = 1, softWrap = false).size.width.toFloat()
        val avail = with(density) { width.toPx() }
        if (w <= 0f) maxSize else (maxSize * minOf(1f, avail / w) * 0.98f).coerceAtLeast(maxSize * 0.08f)
    }
    Text(text, modifier, color = color, maxLines = 1, softWrap = false,
        style = style.copy(fontSize = size.sp, lineHeight = (size * 1.08f).sp,
            shadow = shadow?.let { Shadow(it, Offset.Zero, 36f) }))
}

/** A word landing: from big, turned a little and blurred, down onto its place (Vuruş); or rising from behind a line (Perde). */
@Composable
private fun Land(big: Boolean, mask: Boolean, bar: Color?, content: @Composable () -> Unit) {
    val t = remember { Animatable(0f) }
    LaunchedEffect(Unit) {
        t.animateTo(1f, if (mask) tween(if (bar != null) 300 else 260, easing = FastOutSlowInEasing)
                         else spring(dampingRatio = 0.62f, stiffness = Spring.StiffnessMediumLow))
    }
    val v = t.value
    if (mask) {
        Box(Modifier
            .drawBehind { if (bar != null) drawRect(bar, Offset(-10.dp.toPx(), 0f), Size((size.width + 20.dp.toPx()) * minOf(1f, v / 0.6f), size.height)) }
            .clipToBounds()) {
            Box(Modifier.graphicsLayer { translationY = (1 - v) * size.height * 1.08f }) { content() }
        }
    } else {
        val blurOk = Build.VERSION.SDK_INT >= 31 && v < 0.98f
        Box(Modifier
            .graphicsLayer {
                val s = 1 + (1 - v).coerceAtLeast(0f) * (if (big) 1.4f else 0.8f)
                scaleX = s; scaleY = s
                rotationZ = (1 - v) * (if (big) -8f else 4f)
                alpha = v.coerceIn(0f, 1f)
            }
            .then(if (blurOk) Modifier.blur(((1 - v) * 12).coerceAtLeast(0f).dp) else Modifier)) { content() }
    }
}

/** One phrase set as a composition; `shown` words of it are on screen. */
@Composable
fun KineticPhraseView(
    phrase: KineticPhrase, shown: Int, size: DpSize, accent: Color, paper: Color,
    glow: Boolean = true, mask: Boolean = false, page: Color = Color.Black,
) {
    Box(Modifier.size(size), contentAlignment = Alignment.Center) {
        when {
            phrase.layout == KineticPhrase.Layout.stack -> Stack(phrase, shown, size.width, accent, paper, glow, mask, page, tilt = false)
            phrase.layout == KineticPhrase.Layout.tilt ->
                Box(Modifier.rotate(-7f)) { Stack(phrase, shown, size.width * 0.9f, accent, paper, glow, mask, page, tilt = true) }
            phrase.layout == KineticPhrase.Layout.side && mask -> Stack(phrase, shown, size.width, accent, paper, glow, mask, page, tilt = false)
            phrase.layout == KineticPhrase.Layout.side -> Side(phrase, shown, size, accent, paper, glow)
            else -> Giant(phrase, shown, size, accent, paper, glow, mask, page)
        }
        if (mask) {
            // Perde: a rule under the stage fills as the phrase is heard
            val f = minOf(shown, phrase.words.size).toFloat() / maxOf(1, phrase.words.size)
            Box(Modifier.align(Alignment.BottomStart).width(size.width * f).height(3.dp).drawBehind { drawRect(accent.copy(alpha = 0.85f)) })
        }
    }
}

private fun bare(w: String): String = w.trimEnd(',', ';', ':')
private fun isSmall(p: KineticPhrase, i: Int) = KineticPhrase.clean(p.words[i]) in KineticPhrase.small

@Composable
private fun Word(p: KineticPhrase, i: Int, width: Dp, maxSize: Float, accent: Color, paper: Color, glow: Boolean, mask: Boolean, page: Color, tilt: Boolean) {
    if (isSmall(p, i) && i != p.key) {
        Text(p.words[i].uppercase(tr), Modifier.width(width), color = paper.copy(alpha = 0.7f), fontSize = 15.sp,
            fontWeight = FontWeight.SemiBold, fontFamily = FontFamily.Monospace, letterSpacing = 6.sp, maxLines = 2)
    } else {
        val key = i == p.key
        val barred = mask
        FitText(bare(p.words[i]), width, maxSize,
            color = if (key) (if (barred) page else accent) else paper,
            weight = if (key) FontWeight.Black else FontWeight.ExtraBold,
            family = if (key) FontFamily.Serif else FontFamily.Default,
            italic = key && tilt,
            shadow = if (key && glow && !mask) accent.copy(alpha = 0.5f) else null,
            modifier = Modifier.width(width))
    }
}

@Composable
private fun Stack(p: KineticPhrase, shown: Int, width: Dp, accent: Color, paper: Color, glow: Boolean, mask: Boolean, page: Color, tilt: Boolean) {
    Column(Modifier.width(width), verticalArrangement = Arrangement.spacedBy((-4).dp)) {
        for (i in 0 until minOf(shown, p.words.size)) key(i) {
            Land(big = i == p.key, mask = mask, bar = if (mask && i == p.key) accent else null) {
                Word(p, i, width, 220f, accent, paper, glow, mask, page, tilt)
            }
        }
    }
}

@Composable
private fun key(i: Int, content: @Composable () -> Unit) = androidx.compose.runtime.key(i) { content() }

/** The key word turned on its side down the left edge, the other words stacked beside it. */
@Composable
private fun Side(p: KineticPhrase, shown: Int, size: DpSize, accent: Color, paper: Color, glow: Boolean) {
    val colW = size.width * 0.3f
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Box(Modifier.width(colW).height(size.height), contentAlignment = Alignment.Center) {
            if (shown > p.key) Land(big = true, mask = false, bar = null) {
                FitText(bare(p.words[p.key]), size.height * 0.92f, 220f, accent, FontWeight.Black, FontFamily.Serif,
                    shadow = if (glow) accent.copy(alpha = 0.5f) else null,
                    modifier = Modifier.wrapContentSize(unbounded = true).rotate(-90f))
            }
        }
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy((-2).dp)) {
            for (i in 0 until minOf(shown, p.words.size)) if (i != p.key) key(i) {
                Land(big = false, mask = false, bar = null) { Word(p, i, size.width - colW - 10.dp, 130f, accent, paper, glow, false, Color.Black, false) }
            }
        }
    }
}

/** The key word huge in the middle, the other words small above and below. */
@Composable
private fun Giant(p: KineticPhrase, shown: Int, size: DpSize, accent: Color, paper: Color, glow: Boolean, mask: Boolean, page: Color) {
    @Composable fun line(ids: List<Int>) {
        val t = ids.filter { it < shown }.joinToString(" ") { p.words[it] }.uppercase(tr)
        Text(t, color = paper.copy(alpha = 0.75f), fontSize = 16.sp, fontWeight = FontWeight.SemiBold, fontFamily = FontFamily.Monospace,
            letterSpacing = 5.sp, textAlign = TextAlign.Center)
    }
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        line((0 until p.key).toList())
        if (shown > p.key) Land(big = true, mask = mask, bar = if (mask) accent else null) {
            FitText(bare(p.words[p.key]), size.width, 260f, if (mask) page else accent, FontWeight.Black, FontFamily.Serif,
                shadow = if (glow && !mask) accent.copy(alpha = 0.55f) else null)
        }
        line(((p.key + 1) until p.words.size).toList())
    }
}

/** A phrase on screen with its leaving: it grows past the viewer (Vuruş) or lifts away (Perde). */
@Composable
fun KineticStage(
    phrase: KineticPhrase?, stageKey: String, shown: Int, size: DpSize, accent: Color, paper: Color,
    glow: Boolean, mask: Boolean, page: Color, modifier: Modifier = Modifier,
) {
    if (phrase == null) return
    AnimatedContent(
        targetState = stageKey to phrase, contentKey = { it.first }, modifier = modifier,
        transitionSpec = {
            fadeIn(tween(200)) togetherWith (if (mask) slideOutVertically(tween(280)) { -it / 4 } + fadeOut(tween(280))
                else scaleOut(tween(380), targetScale = 2.6f) + fadeOut(tween(380)))
        }, label = "phrase",
    ) { (k, p) ->
        KineticPhraseView(p, if (k == stageKey) shown else p.words.size, size, accent, paper, glow, mask, page)
    }
}

/**
 * The sentence being read, cut into phrases and set as kinetic type: the phrase holding the heard word is on screen,
 * its words land as the voice reaches them, and the next phrase flies in. Used by Yolda's Kinetik look and by
 * Müzik modu's "Dinle".
 */
@Composable
fun KineticListening(size: DpSize, accent: Color, paper: Color, glow: Boolean, mask: Boolean, page: Color, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val app = remember { AppModel.get(context) }
    val st by app.player.state.collectAsState()
    val spoken by app.player.spoken.collectAsState()
    val nav = app.player.nav
    val sentence = spoken.sentence ?: nav.sentenceRange(st.cursor) ?: return
    val text = remember(sentence, nav) { nav.substring(sentence).trim() }
    val phrases = remember(sentence.first, text) { KineticPhrase.phrases(text, sentence.first / 7) }
    if (phrases.isEmpty()) return
    // which phrase holds the heard word, and how many of its words are heard; not reading: the last phrase, whole
    val word = spoken.word
    var index = phrases.size - 1
    var shown = phrases.last().words.size
    if (word != null && word.first in sentence) {
        val before = nav.substring(sentence.first until word.first).trim()
        var n = if (before.isEmpty()) 0 else before.split(' ', '\n').count { it.isNotEmpty() }
        for ((i, ph) in phrases.withIndex()) {
            if (n < ph.words.size) { index = i; shown = n + 1; break }
            n -= ph.words.size
        }
    }
    val phrase = phrases[index]
    KineticStage(phrase, "${sentence.first}-${phrase.id}", shown, size, accent, paper, glow, mask, page, modifier)
}
