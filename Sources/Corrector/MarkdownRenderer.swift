import AppKit

enum MarkdownRenderer {
    static func render(_ markdown: String) -> NSAttributedString? {
        let output = NSMutableAttributedString(string: "")
        let lines = markdown.components(separatedBy: "\n")
        var inCodeBlock = false

        for (index, line) in lines.enumerated() {
            if index > 0 { output.append(NSAttributedString(string: "\n")) }
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inCodeBlock.toggle()
                continue
            }
            if inCodeBlock {
                output.append(NSAttributedString(string: line, attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
                ]))
                continue
            }

            let (content, prefix, font) = lineStyle(for: line)
            if !prefix.isEmpty {
                output.append(NSAttributedString(string: prefix, attributes: [.font: font]))
            }
            guard let parsed = try? AttributedString(
                markdown: content,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            ) else { return nil }

            for run in parsed.runs {
                let substring = String(parsed[run.range].characters)
                var attributes: [NSAttributedString.Key: Any] = [.font: font]
                if let intent = run.inlinePresentationIntent {
                    let bold = intent.contains(.stronglyEmphasized)
                    let italic = intent.contains(.emphasized)
                    if intent.contains(.code) {
                        attributes[.font] = NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular)
                    } else if bold || italic {
                        let manager = NSFontManager.shared
                        var traits: NSFontTraitMask = []
                        if bold { traits.insert(.boldFontMask) }
                        if italic { traits.insert(.italicFontMask) }
                        attributes[.font] = manager.convert(font, toHaveTrait: traits)
                    }
                }
                if let link = run.link {
                    attributes[.link] = link
                    attributes[.foregroundColor] = NSColor.linkColor
                    attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
                }
                output.append(NSAttributedString(string: substring, attributes: attributes))
            }
        }
        return output
    }

    private static func lineStyle(for line: String) -> (String, String, NSFont) {
        let regular = NSFont.systemFont(ofSize: 14)
        if let match = line.range(of: #"^#{1,6} +"#, options: .regularExpression) {
            let level = line[match].prefix(while: { $0 == "#" }).count
            let size = max(15, 24 - CGFloat(level - 1) * 2)
            return (String(line[match.upperBound...]), "", NSFont.boldSystemFont(ofSize: size))
        }
        if let match = line.range(of: #"^\s*[-*+] +"#, options: .regularExpression) {
            return (String(line[match.upperBound...]), "• ", regular)
        }
        if let match = line.range(of: #"^\s*\d+\. +"#, options: .regularExpression) {
            let number = line[match].trimmingCharacters(in: .whitespaces)
            return (String(line[match.upperBound...]), "\(number) ", regular)
        }
        if let match = line.range(of: #"^> +"#, options: .regularExpression) {
            return (String(line[match.upperBound...]), "│ ", regular)
        }
        return (line, "", regular)
    }
}
