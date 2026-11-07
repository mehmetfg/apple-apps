import Foundation

enum VoteCountFormatter {
    static func text(_ votes: Int) -> String {
        switch votes {
        case 1_000_000...:
            let value = (Double(votes) / 1_000_000).formatted(.number.precision(.fractionLength(1)))
            return "\(value) Mn oy"
        case 1_000...:
            return "\(votes / 1_000) B oy"
        default:
            return "\(votes) oy"
        }
    }
}
