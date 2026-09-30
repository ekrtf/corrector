import AppKit

@main
struct FormattingGuardTests {
    static func main() throws {
        try checkApply()
        try checkChanges()
        try checkRejections()
        print("Formatting guard checks passed")
    }

    static func checkApply() throws {
        let source = NSMutableAttributedString(string: "Un mot mal ecrit.\n**helo** [lien](https://example.com)")
        let boldRange = (source.string as NSString).range(of: "ecrit")
        source.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 15), range: boldRange)
        let corrected = try FormattingGuard.apply(
            corrected: "Un mot mal écrit.\n**hello** [lien](https://example.com)",
            to: source
        )
        precondition(corrected.string == "Un mot mal écrit.\n**hello** [lien](https://example.com)")
        let correctedRange = (corrected.string as NSString).range(of: "écrit")
        let correctedFont = corrected.attribute(.font, at: correctedRange.location, effectiveRange: nil) as? NSFont
        precondition(correctedFont?.fontDescriptor.symbolicTraits.contains(.bold) == true)

        do {
            _ = try FormattingGuard.apply(corrected: "Un mot mal écrit!\n**hello** [lien](https://example.com)", to: source)
            fatalError("Punctuation change was accepted")
        } catch FormattingGuardError.changedStructure {}

        do {
            _ = try FormattingGuard.apply(corrected: "Un mot mal  écrit.\n**hello** [lien](https://example.com)", to: source)
            fatalError("Whitespace change was accepted")
        } catch FormattingGuardError.changedStructure {}

        do {
            _ = try FormattingGuard.apply(corrected: "Un mot mal écrit.\n**hello** [lien](https://exemple.com)", to: source)
            fatalError("URL change was accepted")
        } catch FormattingGuardError.changedProtectedText {}
    }

    static func checkChanges() throws {
        let text = "😀 Il a ecrit aujourdhui, c'est l'ete. Ecrit ecrit!"
        let corrected = "😀 Il a écrit aujourd’hui, c'est l'été. Écrit écrit!"
        let source = NSMutableAttributedString(string: text)
        source.addAttribute(.font, value: NSFont.systemFont(ofSize: 13), range: NSRange(location: 0, length: source.length))
        let outcome = try FormattingGuard.correct(corrected: corrected, original: source)
        precondition(outcome.text.string == corrected)
        let applied = try FormattingGuard.apply(corrected: corrected, to: source)
        precondition(applied.isEqual(to: outcome.text))
        precondition(outcome.changes.map(\.original) == ["ecrit", "aujourdhui", "l'ete", "Ecrit", "ecrit"])
        precondition(outcome.changes.map(\.replacement) == ["écrit", "aujourd’hui", "l'été", "Écrit", "écrit"])
        for change in outcome.changes {
            precondition((text as NSString).substring(with: change.sourceRange) == change.original)
            precondition((corrected as NSString).substring(with: change.resultRange) == change.replacement)
        }
        // The emoji is two UTF-16 units; the repeated word keeps its own position.
        precondition(outcome.changes[0].sourceRange == NSRange(location: 8, length: 5))
        precondition(outcome.changes[4].sourceRange == (text as NSString).range(of: "ecrit", options: .backwards))
        precondition(outcome.changes[4].resultRange == (corrected as NSString).range(of: "écrit", options: .backwards))

        let unchanged = try FormattingGuard.correct(corrected: text, original: source)
        precondition(unchanged.changes.isEmpty)
        precondition(unchanged.text.isEqual(to: source))

        let empty = try FormattingGuard.correct(corrected: "", original: NSAttributedString(string: ""))
        precondition(empty.changes.isEmpty && empty.text.length == 0)

        // Decomposed accent → composed accent: the text follows the model exactly, but nothing visible changed.
        let composed = try FormattingGuard.correct(corrected: "un caf\u{E9} froid", original: NSAttributedString(string: "un cafe\u{301} froid"))
        precondition(composed.text.string.utf16.elementsEqual("un caf\u{E9} froid".utf16))
        precondition(composed.changes.isEmpty)
    }

    static func checkRejections() throws {
        let source = NSAttributedString(string: "Voir `ecrit` et https://example.com/ecrit, puis ecrit.")
        let accepted = try FormattingGuard.correct(corrected: "Voir `ecrit` et https://example.com/ecrit, puis écrit.", original: source)
        precondition(accepted.changes.map(\.replacement) == ["écrit"])

        for corrected in [
            "Voir `écrit` et https://example.com/ecrit, puis écrit.",
            "Voir `ecrit` et https://example.com/écrit, puis écrit."
        ] {
            do {
                _ = try FormattingGuard.correct(corrected: corrected, original: source)
                fatalError("Accent change in protected text was accepted: \(corrected)")
            } catch FormattingGuardError.changedProtectedText {}
        }

        for corrected in [
            "Voir `ecrit` et https://example.com/ecrit, puis bien écrit.",
            "Voir `ecrit` et https://example.com/ecrit; puis écrit.",
            "Voir `ecrit` et https://example.com/ecrit, puis écrit.\n"
        ] {
            do {
                _ = try FormattingGuard.correct(corrected: corrected, original: source)
                fatalError("Structure change was accepted: \(corrected.debugDescription)")
            } catch FormattingGuardError.changedStructure {}
        }
    }
}
