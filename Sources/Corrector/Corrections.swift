import AppKit

struct TextChange: Equatable {
    /// Range of the replaced text in the original string; empty when the model only inserted text.
    let sourceRange: NSRange
    /// Range of the new text in `CorrectionOutcome.text`; empty when the model only removed text.
    let resultRange: NSRange
    let original: String
    let replacement: String
}

struct CorrectionOutcome {
    /// The model's answer, keeping the original's attributes wherever the text is unchanged. Words that
    /// differ only in composed/decomposed accents keep their original form.
    let text: NSAttributedString
    let changes: [TextChange]
}

/// Compares the model's answer with the original text, token by token, to find what changed.
enum CorrectionDiff {
    // Words (with inner apostrophes), whitespace runs, or any other single character. Together the
    // tokens cover the whole string.
    private static let tokenPattern = try! NSRegularExpression(
        pattern: #"[\p{L}\p{M}\p{N}]+(?:['’][\p{L}\p{M}\p{N}]+)*|\s+|."#, options: .dotMatchesLineSeparators)

    static func merge(corrected: String, into original: NSAttributedString) -> CorrectionOutcome {
        let source = tokens(in: original.string)
        let result = tokens(in: corrected)
        // `==` on String treats composed and decomposed accents as equal, so those are not changes.
        let difference = result.map(\.text).difference(from: source.map(\.text))
        var removed = Set<Int>()
        var inserted = Set<Int>()
        for step in difference {
            switch step {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }

        let output = NSMutableAttributedString()
        var changes: [TextChange] = []
        var s = 0
        var r = 0
        while s < source.count || r < result.count {
            if s < source.count, r < result.count, !removed.contains(s), !inserted.contains(r) {
                output.append(original.attributedSubstring(from: source[s].range))
                s += 1
                r += 1
                continue
            }
            let sourceStart = s
            let resultStart = r
            while s < source.count, removed.contains(s) { s += 1 }
            while r < result.count, inserted.contains(r) { r += 1 }

            let sourceRange = span(of: source, from: sourceStart, to: s, textLength: original.length)
            let resultSpan = span(of: result, from: resultStart, to: r, textLength: (corrected as NSString).length)
            let replacement = (corrected as NSString).substring(with: resultSpan)
            let resultRange = NSRange(location: output.length, length: (replacement as NSString).length)
            output.append(NSAttributedString(string: replacement, attributes: attributes(near: sourceRange, in: original)))
            changes.append(TextChange(sourceRange: sourceRange, resultRange: resultRange,
                                      original: original.attributedSubstring(from: sourceRange).string,
                                      replacement: replacement))
        }
        return CorrectionOutcome(text: output, changes: changes)
    }

    private struct Token {
        let text: String
        let range: NSRange
    }

    private static func tokens(in string: String) -> [Token] {
        let text = string as NSString
        return tokenPattern.matches(in: string, range: NSRange(location: 0, length: text.length)).map {
            Token(text: text.substring(with: $0.range), range: $0.range)
        }
    }

    /// The range covered by tokens `start..<end`, or an empty range where they would be.
    private static func span(of tokens: [Token], from start: Int, to stop: Int, textLength: Int) -> NSRange {
        let location = start < tokens.count ? tokens[start].range.location : textLength
        let upper = stop < tokens.count ? tokens[stop].range.location : textLength
        return NSRange(location: location, length: upper - location)
    }

    /// New text takes the attributes of the text it replaces, or of the character before an insertion.
    private static func attributes(near range: NSRange, in original: NSAttributedString) -> [NSAttributedString.Key: Any] {
        guard original.length > 0 else { return [:] }
        let anchor = range.length > 0 ? range.location : min(max(range.location - 1, 0), original.length - 1)
        return original.attributes(at: anchor, effectiveRange: nil)
    }
}
