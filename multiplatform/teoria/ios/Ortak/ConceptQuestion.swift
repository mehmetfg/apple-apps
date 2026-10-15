import Foundation

/// A multiple-choice question that makes a concept do work: recognise it in an example,
/// tell it from a neighbour, apply it. Used by the "Dönüştür" line, levels 1–2.
struct ConceptQuestion: Codable, Identifiable, Hashable {
    let id: String
    let concept: String
    let question: String
    var context: String?
    let options: [String]
    let answer: String
    let explanation: String
}
