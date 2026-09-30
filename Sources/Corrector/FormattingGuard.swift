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
        let before = original.string as NSString
        let after = corrected as NSString
        let sourceWords = wordPattern.matches(in: original.string, range: NSRange(location: 0, length: before.length))
        let resultWords = wordPattern.matches(in: corrected, range: NSRange(location: 0, length: after.length))
        guard sourceWords.count == resultWords.count else { throw FormattingGuardError.changedStructure }

        var sourceCursor = 0
        var resultCursor = 0
        for (source, result) in zip(sourceWords, resultWords) {
            let sourceGap = before.substring(with: NSRange(location: sourceCursor, length: source.range.location - sourceCursor))
            let resultGap = after.substring(with: NSRange(location: resultCursor, length: result.range.location - resultCursor))
            guard sourceGap == resultGap else { throw FormattingGuardError.changedStructure }
            sourceCursor = NSMaxRange(source.range)
            resultCursor = NSMaxRange(result.range)
        }
        guard before.substring(from: sourceCursor) == after.substring(from: resultCursor) else {
            throw FormattingGuardError.changedStructure
        }

        let output = NSMutableAttributedString(attributedString: original)
        let protectedRanges = protectedPattern.matches(in: original.string, range: NSRange(location: 0, length: before.length)).map(\.range)
        for (source, result) in zip(sourceWords, resultWords).reversed() {
            let replacement = after.substring(with: result.range)
            if replacement == before.substring(with: source.range) { continue }
            if protectedRanges.contains(where: { NSIntersectionRange($0, source.range).length > 0 }) {
                throw FormattingGuardError.changedProtectedText
            }
            let attributes = original.attributes(at: source.range.location, effectiveRange: nil)
            output.replaceCharacters(in: source.range, with: NSAttributedString(string: replacement, attributes: attributes))
        }
        return output
    }
}
