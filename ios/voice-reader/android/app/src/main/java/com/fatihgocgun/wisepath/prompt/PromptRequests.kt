// The prompts of İstem oluşturucu and Genişlet (port of PromptRequest / ExpandRequest in Views/PromptBuilder.swift and
// Views/ExpandPrompt.swift). Both ask for text made for the ear: Markdown headings only (they become the table of
// contents), plain prose, units written out, no tables, lists, links or footnotes.
package com.fatihgocgun.wisepath.prompt

import com.fatihgocgun.wisepath.model.Chapter
import com.fatihgocgun.wisepath.model.DocumentContent
import com.fatihgocgun.wisepath.model.DocumentRecord
import java.text.NumberFormat
import java.util.Locale
import kotlin.math.roundToInt

private fun thousands(n: Int): String = NumberFormat.getIntegerInstance(Locale("tr", "TR")).format(n)

data class PromptRequest(
    val topic: String = "",
    val details: String = "",
    val length: Length = Length.medium,
    val form: Form = Form.lesson,
    val english: Boolean = false,
) {
    enum class Length(val words: Int, val label: String) {
        short(1500, "Kısa · ~1.500 kelime"), medium(4000, "Orta · ~4.000 kelime"), long(7000, "Uzun · ~7.000 kelime");
        /** Minutes at Voice Dream's 330 words a minute. */
        val minutes: Int get() = (words / 330.0).roundToInt()
    }

    enum class Form(val label: String, val instruction: String) {
        lesson("Ders", "Bir ders gibi kur: önce konunun neden önemli olduğunu söyleyen bir giriş, sonra temelden ileriye giden bölümler, her bölümde somut bir örnek, sonda kısa bir toparlama."),
        narrative("Anlatı", "Bir deneme ya da anlatı gibi yaz: bir sahne ya da soruyla aç, düşünceyi akış içinde geliştir, bölümleri birbirine bağla."),
        summary("Kitap özeti", "Bir kitabın ya da eserin derinlikli özeti olarak yaz: ana tez, bölüm bölüm iddialar ve gerekçeleri, eserin etkisi ve ona yöneltilen en güçlü itiraz."),
        dialogue("Söyleşi", "İki kişinin söyleşisi olarak yaz; konuşanı her paragrafın başında adıyla ve iki noktayla belirt (örnek: Ayşe: …). Konuşma çizgisi, tırnak ya da sahne notu kullanma."),
    }

    val prompt: String get() {
        val lang = if (english) "İngilizce (English)" else "Türkçe"
        val sb = StringBuilder()
        sb.append("Sesli okuma (text-to-speech) için bir metin yaz. Metin bir okuma uygulamasında yüksek hızda dinlenecek; bu yüzden yalnız kulağa göre yazılmış düz metin istiyorum.\n\n")
        sb.append("Konu: ${topic.trim()}")
        val d = details.trim()
        if (d.isNotEmpty()) sb.append("\nAyrıntılar ve teknik istekler: $d")
        sb.append("\n\nBiçim: ${form.instruction}\n")
        sb.append("Dil: $lang. Uzunluk: yaklaşık ${thousands(length.words)} kelime (dinlemesi ≈ ${length.minutes} dakika). Uzunluğu doldurmak için tekrar etme; konu daha kısa sürede bitiyorsa kısa bırak.\n\n")
        sb.append("""Biçim kuralları (hepsine uy):
1. Yalnız Markdown başlık kullan: ilk satır "# " ile metnin adı, bölümler "## " ile. Başka hiçbir Markdown işareti (kalın, italik, madde, numaralı liste, tablo, kod, alıntı bloğu, yatay çizgi) kullanma.
2. Her paragraf tam cümlelerden oluşsun ve noktalama işaretiyle bitsin. Paragrafları tek boş satırla ayır; bir cümleyi satır sonuyla bölme.
3. Sayıları ve yılları okunduğu gibi yazmak zorunda değilsin, ama birim ve simgeleri yazıyla ver: "yüzde 40", "metre", "dolar" (%, m, ${'$'} değil). Kısaltmaları ilk geçtiği yerde açık yaz.
4. Bağlantı, dipnot, kaynak numarası, parantez içi atıf, emoji ve özel simge (→, •, ✓, *) kullanma. Bir kaynağı anmak gerekiyorsa cümlenin içinde adıyla an.
5. Cümleler çoğunlukla 10 ile 25 kelime arasında olsun; çok uzun iç içe yan cümlelerden kaçın.
6. Giriş cümlesi ("Elbette", "İşte metniniz" gibi) ya da sonda açıklama ekleme; doğrudan başlıkla başla, metnin son cümlesiyle bitir.""")
        return sb.toString()
    }
}

/** What a Genişlet prompt is made from. */
sealed class ExpandSource {
    abstract val doc: String
    data class Passage(override val doc: String, val start: Int, val end: Int) : ExpandSource()   // [start, end)
    data class Marks(override val doc: String) : ExpandSource()
    data class ChapterAt(override val doc: String, val offset: Int) : ExpandSource()

    val id: String get() = when (this) {
        is Passage -> "p-$doc-$start-${end - start}"
        is Marks -> "m-$doc"
        is ChapterAt -> "c-$doc-$offset"
    }

    companion object {
        /** The route's offsets: start..end a passage, start alone (end -1) the chapter there, both -1 every mark. */
        fun of(doc: String, start: Int, end: Int): ExpandSource = when {
            start >= 0 && end > start -> Passage(doc, start, end)
            start >= 0 -> ChapterAt(doc, start)
            else -> Marks(doc)
        }
    }
}

data class ExpandRequest(
    val purpose: Purpose = Purpose.deepen,
    val length: Length = Length.medium,
    val english: Boolean = false,
    val note: String = "",
) {
    enum class Purpose(val label: String, val instruction: String) {
        deepen("Derinleştir", "Bu kısmı derinleştir: içindeki iddiayı ve kavramları tek tek aç, gerekçelerini göster, yazarın bunu neden söylediğini ve bu düşüncenin hangi soruya cevap olduğunu anlat. Konunun daha az bilinen, ince yanlarına in."),
        simplify("Basitçe anlat", "Bu kısmı hiç bilmeyen birine anlatır gibi açıkla: önce gündelik bir benzetmeyle sezgiyi kur, sonra kavramları adım adım tanıt, en sonda kısmın kendi diline dön ve onu yeniden oku."),
        examples("Örneklerle", "Bu kısmı somut örneklerle aç: farklı alanlardan (gündelik hayat, tarih, bilim, iş) en az beş örnek ver; her örnekte fikrin nasıl işlediğini göster, son örnekte fikrin sınırına dokun."),
        counter("Karşı görüş", "Bu kısma yöneltilmiş en güçlü itirazları anlat: kim itiraz etti, hangi gerekçeyle; sonra yazarın ya da savunucularının cevabını ver ve tartışmanın bugün nerede durduğunu söyle. Taraf tutma, iki tarafın en iyi hâlini kur."),
        apply("Hayatıma uygula", "Bu kısmı gündelik hayata, iş hayatına ve karar vermeye uygula: fikir bugün nerede işe yarar, hangi hatayı önler, nasıl bir alışkanlığa dönüşür. Sonda dinleyenin bu hafta deneyebileceği tek bir somut alıştırma öner."),
        history("Tarihçe ve bağlam", "Bu kısmın tarihçesini ve bağlamını anlat: fikir nereden geldi, kimlerden etkilendi, yazıldığı dönemde neye cevap veriyordu, sonra kimler onu sürdürdü ya da değiştirdi."),
        compile("Derleme", "Bu kitapta işaretlediğim kısımları bir araya getir: onları birbirine bağlayan ana düşünceyi bul, işaretleri bir anlatının içinde sırayla açıkla, aralarındaki boşlukları kitabın bütünüyle doldur. İşaretlerin neden önemli olduğu anlaşılsın."),
        review("Pekiştirme", "Bu bölümü pekiştirmek için bir metin yaz: önce bölümün ana fikrini ve akışını kısaca toparla, sonra bölümden çıkan on soruyu birer birer sor; her sorudan sonra kısa bir sessizlik cümlesi koy (\"Cevabı düşün.\") ve ardından cevabı açıkla. Sonda bölümün en önemli üç fikrini yeniden söyle.");

        companion object {
            fun choices(s: ExpandSource): List<Purpose> = when (s) {
                is ExpandSource.Passage -> listOf(deepen, simplify, examples, counter, apply, history)
                is ExpandSource.Marks -> listOf(compile, deepen, apply, counter)
                is ExpandSource.ChapterAt -> listOf(review, deepen, simplify, examples)
            }
        }
    }

    enum class Length(val words: Int, val label: String) {
        short(2300, "Kısa"), medium(5000, "Orta"), long(10000, "Uzun");
        val minutes: Int get() = (words / 330.0).roundToInt()
        val detail: String get() = "≈ $minutes dk · ${thousands(words)} kelime"
    }

    /** The context gathered from the book. */
    data class Context(
        val book: String = "",
        val author: String? = null,
        val chapter: String? = null,
        val focus: String = "",                 // the passage, the marks or the chapter
        val before: String = "",
        val after: String = "",
    )

    fun prompt(c: Context, source: ExpandSource): String {
        val lang = if (english) "İngilizce (English)" else "Türkçe"
        val p = StringBuilder("Sesli okuma (text-to-speech) için bir metin yaz. Metin bir okuma uygulamasında yüksek hızda dinlenecek; bu yüzden yalnız kulağa göre yazılmış düz metin (TXT) istiyorum.\n\n")
        p.append("Kaynak kitap: ${c.book}")
        if (!c.author.isNullOrEmpty()) p.append(" (${c.author})")
        if (!c.chapter.isNullOrEmpty()) p.append("\nBölüm: ${c.chapter}")
        when (source) {
            is ExpandSource.Passage -> {
                p.append("\n\nKonu, kitapta işaretlediğim şu kısım:\n«${c.focus}»")
                if (c.before.isNotEmpty()) p.append("\n\nKısmın hemen öncesi (bağlam için):\n${c.before}")
                if (c.after.isNotEmpty()) p.append("\n\nKısmın hemen sonrası (bağlam için):\n${c.after}")
            }
            is ExpandSource.Marks -> p.append("\n\nKitapta işaretlediğim kısımlar (sırayla):\n${c.focus}")
            is ExpandSource.ChapterAt -> p.append("\n\nBölümün metni:\n${c.focus}")
        }
        val n = note.trim()
        p.append("\n\nAmaç: ${purpose.instruction}")
        if (n.isNotEmpty()) p.append("\nAyrıca şunu istiyorum: $n")
        p.append("\n\nDil: $lang. Uzunluk: yaklaşık ${thousands(length.words)} kelime (dinlemesi ≈ ${length.minutes} dakika). Kısmı ya da kitabı özetleyip bırakma; onun üzerinden yeni bilgi, açıklama ve bağlam kat. Uzunluğu doldurmak için tekrar etme.")
        if (length == Length.long) {
            p.append("\nMetin uzun olduğu için iki cevapta yazabilirsin: ilk cevapta metnin yarısını yaz ve son satıra tek başına DEVAMI VAR yaz. Ben \"devam\" yazınca kaldığın yerden sürdür; başlığı ve girişi tekrarlama. Tek cevaba sığarsa tek cevapta yaz.")
        }
        p.append("""

Biçim kuralları (hepsine uy):
1. Düz metin yaz. Yalnız başlık satırlarında işaret kullan: ilk satır "# " ile metnin adı, bölümler "## " ile (bunlar içindekiler olur). Kalın, italik, madde, numaralı liste, tablo, kod, alıntı bloğu ve yatay çizgi kullanma.
2. Her paragraf tam cümlelerden oluşsun ve noktalama işaretiyle bitsin. Paragrafları tek boş satırla ayır; bir cümleyi satır sonuyla bölme.
3. Birim ve simgeleri yazıyla ver: "yüzde 40", "metre", "dolar". Kısaltmaları ilk geçtiği yerde açık yaz.
4. Bağlantı, dipnot, kaynak numarası, parantez içi atıf, emoji ve özel simge kullanma. Bir kaynağı anmak gerekiyorsa cümlenin içinde adıyla an.
5. Cümleler çoğunlukla 10 ile 25 kelime arasında olsun.
6. Giriş cümlesi ("Elbette", "İşte metniniz") ya da sonda açıklama ekleme; doğrudan başlıkla başla, metnin son cümlesiyle bitir.""")
        return p.toString()
    }

    companion object {
        /** The context for a source, out of the book's text. */
        fun context(source: ExpandSource, doc: DocumentRecord, content: DocumentContent?): Context {
            val text = content?.text ?: ""
            val chapters = content?.chapters?.sortedBy { it.offset } ?: emptyList()
            fun chapterAt(i: Int): Chapter? = chapters.lastOrNull { it.offset <= i }
            fun clip(from: Int, to: Int): String {
                if (text.isEmpty()) return ""
                val lo = from.coerceIn(0, text.length)
                val hi = to.coerceIn(lo, text.length)
                return text.substring(lo, hi).trim()
            }
            val base = Context(book = doc.title, author = doc.author)
            return when (source) {
                is ExpandSource.Passage -> {
                    val ch = chapterAt(source.start)
                    val start = maxOf(ch?.offset ?: 0, source.start - 900)
                    base.copy(
                        focus = clip(source.start, source.end),
                        chapter = ch?.title,
                        before = wholeParagraphs(clip(start, source.start), fromEnd = true),
                        after = wholeParagraphs(clip(source.end, source.end + 500), fromEnd = false),
                    )
                }
                is ExpandSource.Marks -> {
                    val lines = mutableListOf<String>()
                    var last: String? = null
                    for (h in doc.highlights.sortedBy { it.location }.take(60)) {
                        val t = chapterAt(h.location)?.title
                        if (t != null && t != last) { lines.add("\n[$t]"); last = t }
                        var line = "— ${h.text.trim()}"
                        if (!h.note.isNullOrEmpty()) line += " (notum: ${h.note})"
                        lines.add(line)
                    }
                    base.copy(focus = lines.joinToString("\n").trim())
                }
                is ExpandSource.ChapterAt -> {
                    val i = chapters.indexOfLast { it.offset <= source.offset }
                    val start = if (i >= 0) chapters[i].offset else 0
                    val end = if (i >= 0 && i + 1 < chapters.size) chapters[i + 1].offset else text.length
                    // a chapter of at most ~4.000 words, so the prompt fits any AI's box
                    base.copy(chapter = if (i >= 0) chapters[i].title else null, focus = clip(start, start + minOf(end - start, 26_000)))
                }
            }
        }

        /** Cuts a bit of text at a paragraph (or at least a sentence) so the context starts and ends cleanly. */
        fun wholeParagraphs(s: String, fromEnd: Boolean): String {
            if (s.isEmpty()) return s
            if (fromEnd) {
                s.indexOf('\n').takeIf { it >= 0 }?.let { return s.substring(it + 1).trim() }
                s.indexOf(". ").takeIf { it >= 0 }?.let { return s.substring(it + 2) }
            } else {
                s.lastIndexOf('\n').takeIf { it >= 0 }?.let { return s.substring(0, it).trim() }
                s.lastIndexOf(". ").takeIf { it >= 0 }?.let { return s.substring(0, it + 1) }
            }
            return s
        }
    }
}
