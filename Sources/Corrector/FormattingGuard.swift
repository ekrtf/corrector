import AppKit

enum FormattingGuardError: LocalizedError {
    case changedStructure
    case changedProtectedText

    var errorDescription: String? {
        switch self {
        case .changedStructure: return "The model changed punctuation or spacing. Please retry the correction."
        case .changedProtectedText: return "The model changed a URL or code span. Please retry the correction."
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
        for (source, result) in zip(sourceWords, resultWords).reversed() {
            let word = before.substring(with: source)
            let replacement = after.substring(with: result)
            if identical(word, replacement) { continue }
            if protectedRanges.contains(where: { NSIntersectionRange($0, source).length > 0 }) {
                throw FormattingGuardError.changedProtectedText
            }
            let attributes = original.attributes(at: source.location, effectiveRange: nil)
            output.replaceCharacters(in: source, with: NSAttributedString(string: replacement, attributes: attributes))
            // A composed/decomposed accent swap looks identical, so it is applied but not reported.
            if word != replacement {
                changes.append(WordChange(sourceRange: source, resultRange: result, original: word, replacement: replacement))
            }
        }
        return CorrectionOutcome(text: output, changes: changes.reversed())
    }

    /// `==` treats canonically equivalent strings as equal, but the output must match the corrected string exactly.
    private static func identical(_ first: String, _ second: String) -> Bool {
        first.utf16.elementsEqual(second.utf16)
    }
}
