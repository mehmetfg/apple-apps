// Yelda ölçüsü for a voice that is rendered at its natural pace (the neural voices: Elif, Kaan): the steadiness,
// the even level, the uneven shortening and the firm endings that the system voice path gives Yelda, in one call.
//
// Why: Yelda and Cem take their speed from the engine (a clean step up to 336 words a minute) and only the last
// 1.15 to 1.5 times from FastSpeech. A neural voice has no such step. It speaks at its own pace and everything
// above that is shortening, 2.75 times for 330 words a minute and 4.2 for 500. Shortened evenly (the profile path:
// TimeStretch.compress), the melody stays as wide as the voice makes it and the voiced sound thins out.
//
// Measured on the phone's own recordings of Elif and Kaan (iOS 27.0.1, the build of 2026-11-12, the Berkeley
// paragraph; studio/stability.py), against Yelda at Voice Dream's setting:
//
//                         melody (semitones)   voiced share   level over 400 ms (dB)
//     Yelda  330                4.2                0.95              1.7
//     Elif   330  before        6.9                0.83              3.3
//     Elif   330  here          3.6                0.89              1.9
//     Elif   432  before        6.4                0.79              2.6
//     Elif   432  here          3.6                0.89              2.5
//     Kaan   330  before        6.0                0.78              2.2
//     Kaan   330  here          3.3                0.82              1.4
//     Kaan   432  before        5.6                0.68              1.8
//     Kaan   432  here          3.5                0.80              1.8
//
// At the natural pace the phrases' middle pitches came from 1.30 (Elif) and 1.35 (Kaan) semitones apart to 0.76
// and 0.74 (Yelda 0.88), and the level over 400 ms from 5.2 and 3.8 dB to 2.4 and 1.8 (Yelda 3.2).
//
// The order matters: steady first, on the natural-pace sound where every period is whole, then the shortening.
// The other way round (shorten, then narrow the melody) lost voiced sound: Elif at 432 words a minute 0.78 against
// 0.88. Whisper heard the same words either way (it cannot tell voices apart above 330 words a minute), so the
// choice rests on these numbers and then on the ear.
import Foundation

enum SteadyFast {
    /// How much of the shortening is uneven (vowels more, consonants less); the rest is the same for every sound.
    /// 1.6 is where the user's ear approved FastSpeech on Yelda (up to 1.5 times from her clean speed).
    static let uneven = 1.6

    /// `r`: the voice at its natural pace, 48 kHz, with its word starts. `tempo`: how many times shorter it must
    /// become (1 = as it is). `wordsPerMinute`: the speed heard after it, for how firmly the phrase ends close.
    /// `steady` 0…1 as the Düzlük setting: 0 leaves the melody, 1 brings it to Yelda's width (`Steady.spread`).
    /// The level stage (Level.apply or VoiceMaster) stays with the caller, after this.
    static func shape(_ r: RenderedSpeech, tempo: Double, wordsPerMinute: Double, steady: Double = 1) -> RenderedSpeech {
        var r = r
        guard r.samples.count > 4800 else { return r }
        // 1. melody: narrowed toward Yelda's width, never under the floor where periods stop being clean
        if steady > 0.01, let m = Steady.melody(r.samples) {
            let full = Steady.keep(for: m.spread)
            let keep = 1 - min(max(steady, 0), 1) * (1 - full)
            if keep < 0.99 { r.samples = PitchShift.flatten(r.samples, keep: keep) }
        }
        // 2. level: every 400 ms toward the piece's middle loudness (the length does not change)
        if steady > 0.01 { r.samples = Steady.even(r.samples) }
        // 3. speed: pauses to a small fixed length, the first 1.6 times uneven, the rest even; word times moved
        if tempo > 1.01 {
            let q = FastSpeech.squeeze(r.samples, tempo: tempo, uneven: uneven)
            r.words = r.words.map { (q.moved($0.sample), $0.range) }
            // 4. endings: the fall after a phrase's last syllable made firm again
            r.samples = FastSpeech.tighten(q.samples, target: FastSpeech.closing(at: wordsPerMinute), ends: q.phraseEnds.map(q.moved))
        }
        return r
    }
}
