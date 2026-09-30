import Foundation

/// A word that the correction changed.
struct WordChange: Equatable {
    /// Range of the misspelled word in the original string.
    let sourceRange: NSRange
    /// Range of the replacement in `CorrectionOutcome.text`.
    let resultRange: NSRange
    let original: String
    let replacement: String
}

struct CorrectionOutcome {
    /// The original attributed text with corrected words. It matches the model's answer except that words
    /// differing only in composed/decomposed accents keep their original form.
    let text: NSAttributedString
    /// Visible word changes, in reading order.
    let changes: [WordChange]
}
