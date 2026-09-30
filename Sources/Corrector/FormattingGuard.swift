import AppKit

enum FormattingGuardError: LocalizedError {
    case changedStructure
    case changedProtectedText

    var errorDescription: String? {
        switch self {
        case .changedStructure: return "The model changed punctuation or spacing, so its answer was discarded."
        case .changedProtectedText: return "The model changed a URL or code span, so its answer was discarded."
        }
    }
}

enum FormattingGuard {
    private static let wordPattern = try! NSRegularExpression(pattern: #"[\p{L}\p{M}]+(?:['’][\p{L}\p{M}]+)*"#)
    private static let protectedPattern = try! NSRegularExpression(pattern: #"(?s)```.*?```|`[^`\n]*`|https?://[^\s)]+"#)

    /// Applies word substitutions to the original attributed text. This keeps
    /// paragraph formatting, whitespace, punctuation, and untouched text runs.
    static func apply(corrected: String, to original: NSAttributedString) throws -> NSAttributedString {
        try correct(corrected: corrected, original: original).text
    }

    /// Like `apply(corrected:to:)`, and also reports which words changed.
    static func correct(corrected: String, original: NSAttributedString) throws -> CorrectionOutcome {
        let before = original.string as NSString
        let after = corrected as NSString
        let sourceWords = wordPattern.matches(in: original.string, range: NSRange(location: 0, length: before.length)).map(\.range)
        let resultWords = wordPattern.matches(in: corrected, range: NSRange(location: 0, length: after.length)).map(\.range)
        guard sourceWords.count == resultWords.count else { throw FormattingGuardError.changedStructure }

        var sourceCursor = 0
        var resultCursor = 0
        for (source, result) in zip(sourceWords, resultWords) {
            let sourceGap = before.substring(with: NSRange(location: sourceCursor, length: source.location - sourceCursor))
            let resultGap = after.substring(with: NSRange(location: resultCursor, length: result.location - resultCursor))
            guard identical(sourceGap, resultGap) else { throw FormattingGuardError.changedStructure }
            sourceCursor = NSMaxRange(source)
            resultCursor = NSMaxRange(result)
        }
        guard identical(before.substring(from: sourceCursor), after.substring(from: resultCursor)) else {
            throw FormattingGuardError.changedStructure
        }

        let output = NSMutableAttributedString(attributedString: original)
        let protectedRanges = protectedPattern.matches(in: original.string, range: NSRange(location: 0, length: before.length)).map(\.range)
        var changes: [WordChange] = []
        var offset = 0
        for (source, result) in zip(sourceWords, resultWords) {
            let word = before.substring(with: source)
            let replacement = after.substring(with: result)
            // `==` ignores composed/decomposed accent differences; such words keep their original bytes,
            // which matters inside URLs and code spans.
            if word == replacement { continue }
            if protectedRanges.contains(where: { NSIntersectionRange($0, source).length > 0 }) {
                throw FormattingGuardError.changedProtectedText
            }
            let target = NSRange(location: source.location + offset, length: source.length)
            let attributes = original.attributes(at: source.location, effectiveRange: nil)
            output.replaceCharacters(in: target, with: NSAttributedString(string: replacement, attributes: attributes))
            let length = (replacement as NSString).length
            changes.append(WordChange(sourceRange: source, resultRange: NSRange(location: target.location, length: length),
                                      original: word, replacement: replacement))
            offset += length - source.length
        }
        return CorrectionOutcome(text: output, changes: changes)
    }

    /// `==` treats canonically equivalent strings as equal; punctuation and spacing must match exactly.
    private static func identical(_ first: String, _ second: String) -> Bool {
        first.utf16.elementsEqual(second.utf16)
    }
}
