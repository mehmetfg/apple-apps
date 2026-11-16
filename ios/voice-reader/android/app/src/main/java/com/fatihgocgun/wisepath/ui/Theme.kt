// The app's colours (port of Views/Palette.swift): one accent (navy by default, measured from Voice Dream) that the
// user changes in Görsel Ayarlar › Renk; the page colours come from the reader theme. The play key is always #FF3601.
package com.fatihgocgun.wisepath.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import com.fatihgocgun.wisepath.AppModel
import com.fatihgocgun.wisepath.settings.ReaderTheme

object Palette {
    val play = Color(0xFFFF3601)
    val gold = Color(0xFFD4A62A)
    val ink = Color(0xFF0B1A2A)
}

/** The theme in effect for the reading page (and the app's light / dark). */
val LocalReaderTheme = staticCompositionLocalOf { ReaderTheme.light }
/** The accent, lightened in dark mode so a deep navy stays readable. */
val LocalAccent = staticCompositionLocalOf { Color(0xFF003D61) }

@Composable
fun WisePathTheme(app: AppModel, content: @Composable () -> Unit) {
    val s = app.settings
    val theme = s.effectiveTheme(isSystemInDarkTheme())
    val raw = s.accent
    val accent = if (theme.isDark) lerp(raw, Color.White, 0.45f) else raw
    val scheme = if (theme.isDark) darkColorScheme(
        primary = accent, secondary = accent, tertiary = Palette.play,
        background = theme.background, surface = theme.chrome, surfaceVariant = theme.band,
        onBackground = theme.text, onSurface = theme.text, outline = theme.hairline,
        surfaceContainer = theme.chrome, surfaceContainerHigh = theme.band, surfaceContainerLow = theme.background,
    ) else lightColorScheme(
        primary = accent, secondary = accent, tertiary = Palette.play,
        background = theme.background, surface = theme.chrome, surfaceVariant = lerp(theme.background, Color.Black, 0.04f),
        onBackground = theme.text, onSurface = theme.text, outline = theme.hairline,
        surfaceContainer = theme.chrome, surfaceContainerHigh = theme.band, surfaceContainerLow = theme.background,
    )
    CompositionLocalProvider(LocalReaderTheme provides theme, LocalAccent provides accent) {
        MaterialTheme(colorScheme = scheme, content = content)
    }
}
