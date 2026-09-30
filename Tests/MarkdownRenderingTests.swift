import AppKit

@main
struct MarkdownRenderingTests {
    static func main() throws {
        checkRendering()
        checkTypography()
        checkDetection()
        checkMarking()
        print("Markdown rendering checks passed")
    }

    static func checkRendering() {
        let value = MarkdownRenderer.render("# Titre\n**bonjour** [ici](https://example.com)\n- item\n")!
        precondition(value.string == "Titre\nbonjour ici\n• item\n")
        let wordRange = (value.string as NSString).range(of: "bonjour")
        let wordFont = value.attribute(.font, at: wordRange.location, effectiveRange: nil) as? NSFont
        precondition(wordFont?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        let linkRange = (value.string as NSString).range(of: "ici")
        precondition(value.attribute(.link, at: linkRange.location, effectiveRange: nil) as? URL == URL(string: "https://example.com"))
    }

    static func checkTypography() {
        let markdown = """
        # Titre
        Texte
        - un élément
          - imbriqué
        12. douze
        > citation
        ```
        let x = 1
        ```
        ***fort*** ~~barré~~ `code`
        """
        let value = MarkdownRenderer.render(markdown)!
        let string = value.string as NSString
        precondition(value.string == "Titre\nTexte\n• un élément\n• imbriqué\n12. douze\ncitation\n\nlet x = 1\n\nfort barré code")
        func location(_ word: String) -> Int { string.range(of: word).location }
        func font(_ word: String) -> NSFont { value.attribute(.font, at: location(word), effectiveRange: nil) as! NSFont }
        func style(_ word: String) -> NSParagraphStyle? {
            value.attribute(.paragraphStyle, at: location(word), effectiveRange: nil) as? NSParagraphStyle
        }
        func width(_ text: String) -> CGFloat { (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 14)]).width }

        precondition(font("Titre").pointSize == 24 && font("Titre").fontDescriptor.symbolicTraits.contains(.bold))
        let heading = style("Titre")!
        precondition(heading.paragraphSpacingBefore > 0 && heading.paragraphSpacing > 0)
        precondition(value.attribute(.paragraphStyle, at: location("Titre") + 5, effectiveRange: nil) as? NSParagraphStyle == heading)
        precondition(style("Texte") == nil && font("Texte").pointSize == 14)

        let item = style("un élément")!
        precondition(item.firstLineHeadIndent == 0 && abs(item.headIndent - width("• ")) < 0.01)
        let nested = style("imbriqué")!
        precondition(nested.firstLineHeadIndent > item.firstLineHeadIndent && nested.headIndent > item.headIndent)
        let numbered = style("douze")!
        precondition(numbered.firstLineHeadIndent == 0 && abs(numbered.headIndent - width("12. ")) < 0.01)

        let quote = style("citation")!
        precondition(quote.firstLineHeadIndent > 0 && quote.headIndent == quote.firstLineHeadIndent)
        precondition(font("citation").fontDescriptor.symbolicTraits.contains(.italic))

        precondition(font("let x").fontDescriptor.symbolicTraits.contains(.monoSpace))
        precondition(style("let x")!.headIndent > 0)
        precondition(font("fort").fontDescriptor.symbolicTraits.isSuperset(of: [.bold, .italic]))
        precondition(value.attribute(.strikethroughStyle, at: location("barré"), effectiveRange: nil) as? Int == NSUnderlineStyle.single.rawValue)
        precondition(font("code").fontDescriptor.symbolicTraits.contains(.monoSpace))

        // Copied as rich text: every character, line breaks included, needs a font, and no backgrounds.
        let whole = NSRange(location: 0, length: value.length)
        value.enumerateAttribute(.font, in: whole) { font, _, _ in precondition(font != nil) }
        value.enumerateAttribute(.backgroundColor, in: whole) { color, _, _ in precondition(color == nil) }
        let rtf = try! value.data(from: whole, documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        precondition(!String(decoding: rtf, as: UTF8.self).contains(".AppleSystem"), "Copied fonts must have public names")
    }

    static func checkDetection() {
        for text in [
            "# Titre", "Intro\n## Section", "- item", "* item", "+ item", "  - imbriqué", "1. premier", "10. dix",
            "Un mot **gras** ici", "Un mot *italique* ici", "Un mot _italique_ ici", "Du ~~barré~~",
            "> citation", "Code :\n```\nx\n```", "Lancer `make` ici", "Voir [le lien](https://example.com)"
        ] {
            precondition(MarkdownRenderer.looksLikeMarkdown(text), "Not detected: \(text.debugDescription)")
        }
        for text in [
            "5 - 3 = 2", "3 pommes et 2 poires.", "2024. Une année record.", "Il est #1 en France.",
            "Le prix est de 5 * 3 euros.", "Calcul : 2 ** 8 ** 2", "C'est l`eau et l`air.", "mon_fichier_final.txt",
            "__init__", "Voir [1] (page 3).", "> 18 ans : tarif plein", "- ", "Bonjour,\nÀ bientôt.\n— Emile",
            "jean.dupont@example.com", "https://example.com/a_b_c", "*Offre valable, *hors boissons"
        ] {
            precondition(!MarkdownRenderer.looksLikeMarkdown(text), "False positive: \(text.debugDescription)")
        }
    }

    static func checkMarking() {
        expect("Un mot mal ecrit.", marking: ["ecrit"], rendered: ["ecrit"])
        expect("Un **ecrit** ici", marking: ["ecrit"], rendered: ["ecrit"])
        expect("- premier ecrit\n- second", marking: ["ecrit"], rendered: ["ecrit"])
        expect("- a\n  - ecrit", marking: ["ecrit"], rendered: ["ecrit"])
        expect("## Titre ecrit\ntexte", marking: ["Titre", "ecrit"], rendered: ["Titre", "ecrit"])
        expect("Voir [le lien ecrit](https://example.com) ici", marking: ["ecrit", "ici"], rendered: ["ecrit", "ici"])
        expect("> une citation ecrite", marking: ["ecrite"], rendered: ["ecrite"])
        expect("```\nlet ecrit = 1\n```", marking: ["ecrit"], rendered: ["ecrit"])
        expect("😀 **café** et ecrit", marking: ["café", "ecrit"], rendered: ["café", "ecrit"])
        // Words touching emphasis markers keep the emphasis they had.
        expect("**ecrit**, *mal*ecrit et mot**ecrit** _fin_.",
               marking: ["ecrit", "mal", "ecrit", "mot", "ecrit", "fin"],
               rendered: ["ecrit", "mal", "ecrit", "mot", "ecrit", "fin"])
        // A mark in a link destination disappears from the rendering; the others survive.
        expect("[voir](page-ecrit) puis ecrit", marking: ["ecrit", "ecrit"], rendered: ["ecrit"])
        // A mark that breaks an entity changes the rendered text, so no mark is trusted.
        expect("caf&eacute; ecrit", marking: ["eacute", "ecrit"], rendered: [])

        let adjacent = MarkdownRenderer.render("abcdef", marking: [NSRange(location: 0, length: 3), NSRange(location: 3, length: 3)])!
        precondition(adjacent.marked == [NSRange(location: 0, length: 3), NSRange(location: 3, length: 3)])
        let invalid = MarkdownRenderer.render("abc", marking: [
            NSRange(location: 100, length: 3), NSRange(location: 1, length: 0),
            NSRange(location: NSNotFound, length: 1), NSRange(location: 2, length: 5)
        ])!
        precondition(invalid.marked.isEmpty && invalid.text.string == "abc")
    }

    /// Marks the given words (found left to right) and expects the rendering to mark `rendered` (found left to right).
    static func expect(_ markdown: String, marking words: [String], rendered expected: [String]) {
        let result = MarkdownRenderer.render(markdown, marking: ranges(of: words, in: markdown))!
        let clean = MarkdownRenderer.render(markdown)!
        precondition(result.text.isEqual(to: clean), "Rendering differs for \(markdown.debugDescription)")
        precondition(!result.text.string.unicodeScalars.contains { $0.value >= 0xF0000 })
        let wanted = ranges(of: expected, in: clean.string)
        precondition(result.marked == wanted, "\(markdown.debugDescription): marked \(result.marked), expected \(wanted)")
    }

    static func ranges(of words: [String], in text: String) -> [NSRange] {
        let string = text as NSString
        var cursor = 0
        return words.map { word in
            let range = string.range(of: word, range: NSRange(location: cursor, length: string.length - cursor))
            precondition(range.location != NSNotFound, "\(word) not in \(text.debugDescription)")
            cursor = NSMaxRange(range)
            return range
        }
    }
}
