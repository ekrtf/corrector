import AppKit

enum MarkdownRenderer {
    private static let bodySize: CGFloat = 14
    private static let indentStep: CGFloat = 18
    private static let openSentinel: UInt32 = 0xF0000
    private static let closeSentinel: UInt32 = 0x100000

    private static let detectionPattern = [
        #"(?m)^[ \t]{0,3}(?:#{1,6}[ \t]+\S|[-*+][ \t]+\S|\d{1,3}\.[ \t]+\S|>[ \t]+[^\s\d]|```)"#,
        #"\*\*[^\s*](?:[^*\n]*[^\s*])?\*\*"#,
        #"(?<![\w*])\*[^\s*](?:[^*\n]*[^\s*])?\*(?![\w*])"#,
        #"(?<![\w_])_[^\s_](?:[^_\n]*[^\s_])?_(?![\w_])"#,
        #"~~[^\s~](?:[^~\n]*[^\s~])?~~"#,
        #"(?<![\w`])`[^`\n]+`(?![\w`])"#,
        #"\[[^\]\n]+\]\([^)\n]+\)"#
    ].joined(separator: "|")

    static func looksLikeMarkdown(_ text: String) -> Bool {
        text.range(of: detectionPattern, options: .regularExpression) != nil
    }

    /// Renders Markdown and reports where the given ranges of the Markdown source ended up.
    /// Ranges that cannot be located reliably are left out; `text` always equals `render(markdown)`.
    static func render(_ markdown: String, marking ranges: [NSRange]) -> (text: NSAttributedString, marked: [NSRange])? {
        guard let text = render(markdown) else { return nil }
        guard ranges.count <= Int(closeSentinel - openSentinel) else { return (text, []) }

        // Each range is wrapped in its own pair of private-use characters. Markdown treats them like
        // letters, so emphasis and block parsing are unchanged, and they come out where the range went.
        let source = markdown as NSString
        var events: [(position: Int, scalar: Unicode.Scalar)] = []
        for (index, range) in ranges.enumerated()
        where range.location >= 0 && range.length > 0 && range.location <= source.length - range.length {
            guard let open = Unicode.Scalar(openSentinel + UInt32(index)),
                  let close = Unicode.Scalar(closeSentinel + UInt32(index)) else { continue }
            events.append((range.location, open))
            events.append((NSMaxRange(range), close))
        }
        events.sort { $0.position < $1.position }

        var marked = String.UnicodeScalarView()
        var cursor = 0
        for event in events {
            marked.append(contentsOf: source.substring(with: NSRange(location: cursor, length: event.position - cursor)).unicodeScalars)
            marked.append(event.scalar)
            cursor = event.position
        }
        marked.append(contentsOf: source.substring(from: cursor).unicodeScalars)
        guard let rendered = render(String(marked)) else { return (text, []) }

        var positions: [UInt32: [Int]] = [:]
        var stripped = String.UnicodeScalarView()
        var offset = 0
        for scalar in rendered.string.unicodeScalars {
            if scalar.value >= openSentinel {
                positions[scalar.value, default: []].append(offset)
            } else {
                stripped.append(scalar)
                offset += UTF16.width(scalar)
            }
        }
        // A sentinel that broke parsing (inside an HTML entity, say) changes the text; then no position can be trusted.
        guard String(stripped).utf16.elementsEqual(text.string.utf16) else { return (text, []) }

        let found = ranges.indices.compactMap { index -> NSRange? in
            guard let starts = positions[openSentinel + UInt32(index)], let ends = positions[closeSentinel + UInt32(index)],
                  starts.count == 1, ends.count == 1, ends[0] > starts[0] else { return nil }
            return NSRange(location: starts[0], length: ends[0] - starts[0])
        }
        return (text, found)
    }

    static func render(_ markdown: String) -> NSAttributedString? {
        let output = NSMutableAttributedString()
        let lines = markdown.components(separatedBy: "\n")
        var inCodeBlock = false
        var listColumns: [Int] = []

        for (index, text) in lines.enumerated() {
            let line: Line
            if text.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inCodeBlock.toggle()
                listColumns = []
                line = Line(content: "", parsesInline: false)
            } else if inCodeBlock {
                line = Line(content: text, font: codeFont(size: bodySize - 1, bold: false), paragraph: indented(12), parsesInline: false)
            } else {
                line = style(of: text, listColumns: &listColumns)
            }

            let paragraph = NSMutableAttributedString(string: line.prefix, attributes: [.font: line.font])
            if line.parsesInline {
                guard let inline = inlineText(line.content, font: line.font) else { return nil }
                paragraph.append(inline)
            } else {
                paragraph.append(NSAttributedString(string: line.content, attributes: [.font: line.font]))
            }
            // The line break belongs to its paragraph: same font (line height) and paragraph style.
            if index < lines.count - 1 {
                paragraph.append(NSAttributedString(string: "\n", attributes: [.font: line.font]))
            }
            if let style = line.paragraph {
                paragraph.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: paragraph.length))
            }
            output.append(paragraph)
        }
        return output
    }

    private struct Line {
        var content: String
        var font = NSFont.systemFont(ofSize: MarkdownRenderer.bodySize)
        var prefix = ""
        var paragraph: NSParagraphStyle?
        var parsesInline = true
    }

    private static func style(of text: String, listColumns: inout [Int]) -> Line {
        if let match = text.range(of: #"^[ \t]*(?:[-*+]|\d+\.) +"#, options: .regularExpression) {
            let marker = text[match].trimmingCharacters(in: .whitespaces)
            let prefix = marker.first?.isNumber == true ? "\(marker) " : "• "
            let columns = text.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
            while let last = listColumns.last, last > columns { listColumns.removeLast() }
            if listColumns.last != columns { listColumns.append(columns) }
            let font = NSFont.systemFont(ofSize: bodySize)
            let paragraph = NSMutableParagraphStyle()
            paragraph.firstLineHeadIndent = CGFloat(listColumns.count - 1) * indentStep
            // Wrapped lines line up with the text after the marker.
            paragraph.headIndent = paragraph.firstLineHeadIndent + (prefix as NSString).size(withAttributes: [.font: font]).width
            return Line(content: String(text[match.upperBound...]), font: font, prefix: prefix, paragraph: paragraph)
        }
        if !text.trimmingCharacters(in: .whitespaces).isEmpty { listColumns = [] }

        if let match = text.range(of: #"^#{1,6} +"#, options: .regularExpression) {
            let level = text[match].prefix(while: { $0 == "#" }).count
            let size = max(15, 24 - CGFloat(level - 1) * 2)
            let paragraph = NSMutableParagraphStyle()
            paragraph.paragraphSpacingBefore = (size * 0.4).rounded()
            paragraph.paragraphSpacing = (size * 0.2).rounded()
            return Line(content: String(text[match.upperBound...]), font: .boldSystemFont(ofSize: size), paragraph: paragraph)
        }
        if let match = text.range(of: #"^ {0,3}(?:> ?)+"#, options: .regularExpression) {
            let depth = text[match].filter { $0 == ">" }.count
            let font = NSFontManager.shared.convert(.systemFont(ofSize: bodySize), toHaveTrait: .italicFontMask)
            return Line(content: String(text[match.upperBound...]), font: font, paragraph: indented(CGFloat(depth) * indentStep))
        }
        return Line(content: text)
    }

    private static func indented(_ indent: CGFloat) -> NSParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.firstLineHeadIndent = indent
        paragraph.headIndent = indent
        return paragraph
    }

    // The system monospaced font is exported under a private name that other apps cannot resolve when pasted.
    private static func codeFont(size: CGFloat, bold: Bool) -> NSFont {
        NSFont(name: bold ? "Menlo-Bold" : "Menlo-Regular", size: size)
            ?? .monospacedSystemFont(ofSize: size, weight: bold ? .bold : .regular)
    }

    private static func inlineText(_ content: String, font: NSFont) -> NSAttributedString? {
        guard let parsed = try? AttributedString(
            markdown: content,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else { return nil }

        let output = NSMutableAttributedString()
        for run in parsed.runs {
            var attributes: [NSAttributedString.Key: Any] = [.font: font]
            if let intent = run.inlinePresentationIntent {
                if intent.contains(.code) {
                    attributes[.font] = codeFont(size: font.pointSize - 1, bold: font.fontDescriptor.symbolicTraits.contains(.bold))
                } else {
                    var traits: NSFontTraitMask = []
                    if intent.contains(.stronglyEmphasized) { traits.insert(.boldFontMask) }
                    if intent.contains(.emphasized) { traits.insert(.italicFontMask) }
                    if !traits.isEmpty { attributes[.font] = NSFontManager.shared.convert(font, toHaveTrait: traits) }
                }
                if intent.contains(.strikethrough) {
                    attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
                }
            }
            if let link = run.link {
                attributes[.link] = link
                attributes[.foregroundColor] = NSColor.linkColor
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            output.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attributes))
        }
        return output
    }
}
