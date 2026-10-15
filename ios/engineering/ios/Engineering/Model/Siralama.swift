import Foundation

// Sıralama motoru. Her algoritma bir kare dizisi (iz) üretir: dizinin o anki hâli, vurgular, kod etiketi,
// İngilizce açıklama, sayaçlar. İzle adımı kareleri oynatır; "Sen CPU'sun" aynı izde karar karelerinde durur;
// Tahmin, durak karelerinden soru kurar. Kod etiketleri (`cmp`, `swap`…) dersler_siralama.py'deki #@etiketlerle aynıdır.

enum Algoritma: String, CaseIterable, Identifiable, Hashable {
    case bubble, selection, insertion, merge, quick, heap, counting
    var id: String { rawValue }

    var ad: String {
        switch self {
        case .bubble: "Bubble sort"
        case .selection: "Selection sort"
        case .insertion: "Insertion sort"
        case .merge: "Merge sort"
        case .quick: "Quicksort"
        case .heap: "Heap sort"
        case .counting: "Counting sort"
        }
    }
    var kisa: String {
        switch self {
        case .bubble: "Bubble"
        case .selection: "Selection"
        case .insertion: "Insertion"
        case .merge: "Merge"
        case .quick: "Quick"
        case .heap: "Heap"
        case .counting: "Counting"
        }
    }
    /// Kopya kâğıdı: en iyi · ortalama · en kötü · ek bellek · kararlı
    var ozellik: (iyi: String, ort: String, kotu: String, bellek: String, kararli: Bool) {
        switch self {
        case .bubble: ("n", "n²", "n²", "1", true)
        case .selection: ("n²", "n²", "n²", "1", false)
        case .insertion: ("n", "n²", "n²", "1", true)
        case .merge: ("n log n", "n log n", "n log n", "n", true)
        case .quick: ("n log n", "n log n", "n²", "log n", false)
        case .heap: ("n log n", "n log n", "n log n", "1", false)
        case .counting: ("n + k", "n + k", "n + k", "k", true)
        }
    }
}

enum Isaret: Hashable { case karsilastir, takas, pivot, anahtar, yaz, min }

struct Karar: Hashable {
    let soru: String
    let secenekler: [String]
    let dogru: Int
    let aciklama: String
}

struct Kare: Hashable {
    var dizi: [Int]
    var isaret: [Int: Isaret] = [:]
    var sirali: Set<Int> = []
    var aralik: ClosedRange<Int>? = nil
    var etiket: String? = nil
    var aciklama: String = ""
    var karsilastirma = 0
    var yazma = 0
    var ek: [Int]? = nil
    var ekIsaret: Set<Int> = []
    var heapBoyu: Int? = nil
    var durak: String? = nil
    var karar: Karar? = nil
}

enum Girdi: String, CaseIterable, Identifiable {
    case rastgele = "Random", neredeyse = "Nearly sorted", ters = "Reversed", sirali = "Sorted", tekrarli = "Few unique"
    var id: String { rawValue }

    func uret(_ n: Int) -> [Int] {
        switch self {
        case .rastgele: return Array(1...n).shuffled()
        case .sirali: return Array(1...n)
        case .ters: return Array((1...n).reversed())
        case .neredeyse:
            var a = Array(1...n)
            for _ in 0..<max(1, n / 8) {
                let i = Int.random(in: 0..<(n - 1)); a.swapAt(i, i + 1)
            }
            return a
        case .tekrarli:
            let k = max(3, n / 5)
            return (0..<n).map { _ in Int.random(in: 1...k) * (n / k) }
        }
    }
}

/// Oyunlar için küçük, değerleri farklı girdi (seçenekler değerle adlandırılır).
func oyunGirdisi(_ algoritma: Algoritma, n: Int = 6) -> [Int] {
    if algoritma == .counting { return (0..<(n + 1)).map { _ in Int.random(in: 1...5) } }
    return Array(Array(1...9).shuffled().prefix(n))
}

/// Aynı indekse iki vurgu düşebilir (ör. quicksort'ta i == j); sözlük literali o durumda çöker. Sonraki kazanır.
func isaret(_ ciftler: (Int, Isaret)...) -> [Int: Isaret] {
    var s: [Int: Isaret] = [:]
    for (i, v) in ciftler { s[i] = v }
    return s
}

// MARK: - Kaydedici

final class Iz {
    private(set) var kareler: [Kare] = []
    private var a: [Int]
    private var cmp = 0, yaz = 0
    private var sirali = Set<Int>()
    private var aralik: ClosedRange<Int>?
    private var ek: [Int]?
    private var heapBoyu: Int?
    private var birlesme = 0, bolme = 0

    init(_ algoritma: Algoritma, _ girdi: [Int]) {
        a = girdi
        kare(nil, "Start. \(girdi.count) items.")
        switch algoritma {
        case .bubble: bubble()
        case .selection: selection()
        case .insertion: insertion()
        case .merge: mergeSort(0, a.count - 1); sirali = Set(a.indices)
        case .quick: quick(0, a.count - 1)
        case .heap: heap()
        case .counting: counting()
        }
        sirali = Set(a.indices); aralik = nil; ek = nil; heapBoyu = nil
        kare(nil, "Sorted: \(cmp) comparisons, \(yaz) writes.")
    }

    private func kare(_ etiket: String?, _ aciklama: String, _ isaret: [Int: Isaret] = [:],
                      ekIsaret: Set<Int> = [], durak: String? = nil, karar: Karar? = nil) {
        kareler.append(Kare(dizi: a, isaret: isaret, sirali: sirali, aralik: aralik, etiket: etiket,
                            aciklama: aciklama, karsilastirma: cmp, yazma: yaz, ek: ek, ekIsaret: ekIsaret,
                            heapBoyu: heapBoyu, durak: durak, karar: karar))
    }

    // MARK: bubble
    private func bubble() {
        let n = a.count
        var son = n - 1, gecis = 1
        while son > 0 {
            kare("pass", "Pass \(gecis): walk up to position \(son).")
            var takas = false
            for i in 0..<son {
                cmp += 1
                let buyuk = a[i] > a[i + 1]
                kare("cmp", "Compare neighbors \(a[i]) and \(a[i + 1]).", [i: .karsilastir, i + 1: .karsilastir],
                     karar: Karar(soru: "\(a[i]) and \(a[i + 1]) — swap them?", secenekler: ["Swap", "Keep"],
                                  dogru: buyuk ? 0 : 1,
                                  aciklama: buyuk ? "\(a[i]) > \(a[i + 1]): the bigger one moves right."
                                                  : "\(a[i]) ≤ \(a[i + 1]): already in order. Equal items never swap."))
                if buyuk {
                    a.swapAt(i, i + 1); yaz += 1; takas = true
                    kare("swap", "\(a[i + 1]) is bigger: swap.", [i: .takas, i + 1: .takas])
                }
            }
            sirali.insert(son)
            kare(nil, "\(a[son]) has bubbled to its final place.", durak: "pass \(gecis)")
            if !takas { kare("stop", "No swaps in this pass: the list is sorted. Stop early."); return }
            son -= 1; gecis += 1
        }
    }

    // MARK: selection
    private func selection() {
        let n = a.count
        for i in 0..<(n - 1) {
            let parca = Array(a[i...])
            let m = i + parca.firstIndex(of: parca.min()!)!
            let secenek = parca.map(String.init)
            kare("pass", "Pass \(i + 1): find the smallest item from position \(i).", [i: .anahtar],
                 karar: Karar(soru: "Which is the smallest in the unsorted part?", secenekler: secenek,
                              dogru: m - i, aciklama: "\(a[m]) is the minimum of \(parca.map(String.init).joined(separator: ", "))."))
            var en = i
            for j in (i + 1)..<n {
                cmp += 1
                kare("cmp", "Is \(a[j]) smaller than \(a[en]), the smallest so far?", [j: .karsilastir, en: .min])
                if a[j] < a[en] { en = j; kare("min", "New smallest: \(a[en]).", [en: .min]) }
            }
            if en != i {
                a.swapAt(i, en); yaz += 1
                kare("swap", "Swap \(a[i]) to the front of the unsorted part.", [i: .takas, en: .takas])
            } else {
                kare("swap", "\(a[i]) is already in front. No swap needed.", [i: .min])
            }
            sirali.insert(i)
            kare(nil, "The sorted part is \(i + 1) item\(i == 0 ? "" : "s") long.", durak: "pass \(i + 1)")
        }
    }

    // MARK: insertion
    private func insertion() {
        sirali = [0]
        for i in 1..<a.count {
            let key = a[i]
            let onu = Array(a[0..<i])
            let hedef = onu.firstIndex { $0 > key }
            var secenek = onu.map { "Before \($0)" }
            secenek.append("Stay where it is")
            kare("key", "Take \(key) as the key.", [i: .anahtar],
                 karar: Karar(soru: "Where does \(key) go in the sorted part?", secenekler: secenek,
                              dogru: hedef ?? onu.count,
                              aciklama: hedef.map { "\(key) goes before \(onu[$0]): every bigger item shifts right." }
                                ?? "Nothing on the left is bigger than \(key), so it stays."))
            var j = i - 1
            while j >= 0 {
                cmp += 1
                kare("cmp", "Is \(a[j]) bigger than \(key)?", [j: .karsilastir, j + 1: .anahtar])
                if a[j] > key {
                    a.swapAt(j, j + 1); yaz += 1
                    kare("shift", "\(a[j + 1]) shifts one place right.", [j: .anahtar, j + 1: .yaz])
                    j -= 1
                } else { break }
            }
            sirali = Set(0...i)
            kare("insert", "\(key) drops into the gap.", [j + 1: .anahtar], durak: "pass \(i)")
        }
    }

    // MARK: merge
    private func mergeSort(_ lo: Int, _ hi: Int) {
        guard lo < hi else { return }
        let mid = (lo + hi) / 2
        aralik = lo...hi
        kare("split", "Split positions \(lo)–\(hi) into two halves.")
        mergeSort(lo, mid)
        mergeSort(mid + 1, hi)
        merge(lo, mid, hi)
    }

    private func merge(_ lo: Int, _ mid: Int, _ hi: Int) {
        let sol = Array(a[lo...mid]), sag = Array(a[(mid + 1)...hi])
        var tampon = Array(repeating: 0, count: a.count)
        for k in lo...hi { tampon[k] = a[k] }
        ek = tampon; aralik = lo...hi
        var i = 0, j = 0, k = lo
        while i < sol.count && j < sag.count {
            cmp += 1
            let solMu = sol[i] <= sag[j]
            kare("cmp", "Heads: \(sol[i]) on the left, \(sag[j]) on the right.", [k: .yaz],
                 ekIsaret: [lo + i, mid + 1 + j],
                 karar: Karar(soru: "Which head is written next?", secenekler: ["\(sol[i])  ·  left", "\(sag[j])  ·  right"],
                              dogru: solMu ? 0 : 1,
                              aciklama: sol[i] == sag[j] ? "A tie: take the left one first. That keeps merge sort stable."
                                                         : "Always take the smaller head: \(min(sol[i], sag[j]))."))
            if solMu {
                a[k] = sol[i]; i += 1; yaz += 1
                kare("takeL", "Write \(a[k]) from the left half.", [k: .yaz], ekIsaret: [lo + i - 1])
            } else {
                a[k] = sag[j]; j += 1; yaz += 1
                kare("takeR", "Write \(a[k]) from the right half.", [k: .yaz], ekIsaret: [mid + j])
            }
            k += 1
        }
        while i < sol.count { a[k] = sol[i]; i += 1; yaz += 1; kare("rest", "Copy the rest: \(a[k]).", [k: .yaz]); k += 1 }
        while j < sag.count { a[k] = sag[j]; j += 1; yaz += 1; kare("rest", "Copy the rest: \(a[k]).", [k: .yaz]); k += 1 }
        ek = nil
        birlesme += 1
        kare(nil, "Positions \(lo)–\(hi) are merged and sorted.",
             durak: birlesme == 1 ? "the first merge" : "the first \(birlesme) merges")
    }

    // MARK: quick
    private func quick(_ lo: Int, _ hi: Int) {
        if lo < hi {
            let p = partition(lo, hi)
            quick(lo, p - 1)
            quick(p + 1, hi)
        } else if lo == hi {
            sirali.insert(lo)
        }
    }

    private func partition(_ lo: Int, _ hi: Int) -> Int {
        aralik = lo...hi
        let pivot = a[hi]
        kare("pivot", "Partition \(lo)–\(hi). The pivot is the last item: \(pivot).", [hi: .pivot])
        var i = lo
        for j in lo..<hi {
            cmp += 1
            let kucuk = a[j] < pivot
            kare("cmp", "Is \(a[j]) smaller than the pivot \(pivot)?", isaret((i, .min), (hi, .pivot), (j, .karsilastir)),
                 karar: Karar(soru: "Is \(a[j]) smaller than the pivot \(pivot)?",
                              secenekler: ["Yes — move it to the small side", "No — leave it"], dogru: kucuk ? 0 : 1,
                              aciklama: kucuk ? "\(a[j]) < \(pivot): it joins the small side on the left."
                                              : "\(a[j]) ≥ \(pivot): it stays on the big side."))
            if kucuk {
                if i != j { a.swapAt(i, j); yaz += 1 }
                kare("swap", "\(a[i]) joins the small side.", isaret((hi, .pivot), (i, .takas), (j, .takas)))
                i += 1
            }
        }
        if i != hi { a.swapAt(i, hi); yaz += 1 }
        sirali.insert(i)
        bolme += 1
        kare("place", "Pivot \(pivot) lands in its final place. Smaller on its left, bigger on its right.", [i: .pivot],
             durak: bolme == 1 ? "the first partition" : nil)
        return i
    }

    // MARK: heap
    private func heap() {
        let n = a.count
        heapBoyu = n
        for i in stride(from: n / 2 - 1, through: 0, by: -1) {
            kare("build", "Build: fix the subtree under \(a[i]).", [i: .anahtar])
            siftDown(i, n)
        }
        kare(nil, "The heap is built. The biggest item, \(a[0]), is at the top.", [0: .pivot], durak: "building the heap")
        for son in stride(from: n - 1, to: 0, by: -1) {
            a.swapAt(0, son); yaz += 1
            sirali.insert(son); heapBoyu = son
            kare("swaproot", "Move the biggest, \(a[son]), to the end. The heap shrinks.", [0: .takas, son: .takas])
            siftDown(0, son)
        }
    }

    private func siftDown(_ bas: Int, _ n: Int) {
        var i = bas
        while true {
            let l = 2 * i + 1, r = 2 * i + 2
            guard l < n else { return }
            var big = i
            cmp += 1; if a[l] > a[big] { big = l }
            if r < n { cmp += 1; if a[r] > a[big] { big = r } }
            var secenek = ["Swap with \(a[l])"]
            if r < n { secenek.append("Swap with \(a[r])") }
            secenek.append("Stop — the parent is biggest")
            let dogru = big == l ? 0 : (big == r ? 1 : secenek.count - 1)
            var vurgu: [Int: Isaret] = [i: .anahtar, l: .karsilastir]
            if r < n { vurgu[r] = .karsilastir }
            kare(r < n ? "cmpR" : "cmpL",
                 "Parent \(a[i]), children \(a[l])\(r < n ? " and \(a[r])" : "").", vurgu,
                 karar: Karar(soru: "Parent \(a[i]) · children \(a[l])\(r < n ? " and \(a[r])" : ""). What now?",
                              secenekler: secenek, dogru: dogru,
                              aciklama: big == i ? "\(a[i]) is at least as big as its children: the heap rule holds."
                                                 : "Swap with the bigger child, \(a[big]), so the parent is biggest."))
            if big == i { kare("stop", "\(a[i]) fits here. Stop.", [i: .min]); return }
            a.swapAt(i, big); yaz += 1
            kare("swap", "\(a[big]) sinks, \(a[i]) rises.", [i: .takas, big: .takas])
            i = big
        }
    }

    // MARK: counting
    private func counting() {
        let k = a.max() ?? 0
        ek = Array(repeating: 0, count: k + 1)
        kare(nil, "Make \(k + 1) counters (0…\(k)), all zero.")
        for (idx, x) in a.enumerated() {
            var aday = [x, x - 1, x + 1, x + 2, x - 2].filter { $0 >= 0 && $0 <= k }
            aday = Array(aday.prefix(3))
            let karisik = aday.shuffled()
            kare("count", "Read \(x).", [idx: .karsilastir], ekIsaret: [x],
                 karar: Karar(soru: "Read \(x). Which counter goes up?", secenekler: karisik.map { "counter \($0)" },
                              dogru: karisik.firstIndex(of: x)!, aciklama: "The value is the index: counter \(x)."))
            ek![x] += 1; yaz += 1
            kare("count", "Counter \(x) is now \(ek![x]).", [idx: .karsilastir], ekIsaret: [x])
        }
        kare(nil, "Counting is done. No comparisons so far.", durak: "counting")
        a = Array(repeating: 0, count: a.count)
        kare("write", "Now write the values out, in order.")
        var yer = 0
        for v in 0...k {
            for _ in 0..<(ek![v]) {
                a[yer] = v; yaz += 1; sirali.insert(yer)
                kare("write", "Counter \(v): write \(v).", [yer: .yaz], ekIsaret: [v])
                yer += 1
            }
        }
    }
}

// MARK: - Tahmin sorusu

struct TahminSorusu {
    let algoritma: Algoritma
    let baslangic: [Int]
    let durak: String
    let secenekler: [[Int]]
    let dogru: Int
    let ekMi: Bool      // counting: sayaç dizisi sorulur
}

func tahminSorusu(_ algoritma: Algoritma) -> TahminSorusu {
    let girdi = oyunGirdisi(algoritma, n: algoritma == .counting ? 6 : 6)
    let iz = Iz(algoritma, girdi)
    let duraklar = iz.kareler.enumerated().filter { $0.element.durak != nil }
    let secim = duraklar.isEmpty ? (iz.kareler.count - 1, iz.kareler.last!) :
        duraklar[min(duraklar.count - 1, Int.random(in: 0...min(1, duraklar.count - 1)))]
    let ekMi = algoritma == .counting
    let cevap = ekMi ? (secim.1.ek ?? []) : secim.1.dizi
    var aday: [[Int]] = []
    if ekMi {
        for _ in 0..<12 {
            var c = cevap
            let i = Int.random(in: 0..<c.count), j = Int.random(in: 0..<c.count)
            if c[i] > 0 && i != j { c[i] -= 1; c[j] += 1 }
            aday.append(c)
        }
    } else {
        aday.append(girdi)
        aday.append(girdi.sorted())
        for d in duraklar where d.offset != secim.0 { aday.append(d.element.dizi) }
        for _ in 0..<8 {
            var c = cevap
            let i = Int.random(in: 0..<(c.count - 1)); c.swapAt(i, i + 1)
            aday.append(c)
            var d = cevap
            d.swapAt(Int.random(in: 0..<d.count), Int.random(in: 0..<d.count))
            aday.append(d)
        }
    }
    var secenek: [[Int]] = []
    for c in aday where c != cevap && !secenek.contains(c) { secenek.append(c); if secenek.count == 3 { break } }
    secenek.append(cevap)
    secenek.shuffle()
    return TahminSorusu(algoritma: algoritma, baslangic: girdi, durak: secim.1.durak ?? "sorting",
                        secenekler: secenek, dogru: secenek.firstIndex(of: cevap)!, ekMi: ekMi)
}
