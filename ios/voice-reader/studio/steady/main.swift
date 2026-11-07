// Kararlı ölçü for a studio pack's audio, with the app's own code (Speech/Steady.swift, Speech/Neural/PitchShift.swift).
//   steady measure <in.f32>                      → "<median Hz> <melody width in semitones>"
//   steady apply <in.f32> <out.f32> <keep> <toward Hz> <gain dB>
// Raw 48 kHz mono float32. The length never changes, so the pack's word times stay right.
// Build: swiftc -O -o steady main.swift ../../ios/VoiceReader/Speech/Steady.swift ../../ios/VoiceReader/Speech/Neural/PitchShift.swift
import Foundation
let a = CommandLine.arguments
func read(_ p: String) -> [Float] { (try! Data(contentsOf: URL(fileURLWithPath: p))).withUnsafeBytes { Array($0.bindMemory(to: Float.self)) } }
if a[1] == "measure" {
    if let m = Steady.melody(read(a[2])) { print(String(format: "%.2f %.2f", m.hz, m.spread)) } else { print("0 0") }
} else {
    var x = read(a[2])
    x = PitchShift.flatten(x, keep: Double(a[4])!, toward: Double(a[5])!)
    x = Steady.even(x)
    let g = Float(pow(10, Double(a[6])! / 20))
    var peak: Float = 0
    for i in x.indices { x[i] *= g; peak = max(peak, abs(x[i])) }
    if peak > 0.97 { let k = 0.97 / peak; for i in x.indices { x[i] *= k } }
    x.withUnsafeBufferPointer { try! Data(buffer: $0).write(to: URL(fileURLWithPath: a[3])) }
}
