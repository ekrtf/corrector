import AppKit

@main
struct CorrectionDiffTests {
    static func main() {
        checkFormatting()
        checkChanges()
        checkAnyEditIsShown()
        print("Correction diff checks passed")
    }

    static func checkFormatting() {
        let source = NSMutableAttributedString(string: "Un mot mal ecrit.\n**helo** [lien](https://example.com)")
        let boldRange = (source.string as NSString).range(of: "ecrit")
        source.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 15), range: boldRange)
        let corrected = "Un mot mal écrit.\n**hello** [lien](https://example.com)"
        let outcome = CorrectionDiff.merge(corrected: corrected, into: source)
        precondition(outcome.text.string == corrected)
        let correctedRange = (corrected as NSString).range(of: "écrit")
        let font = outcome.text.attribute(.font, at: correctedRange.location, effectiveRange: nil) as? NSFont
        precondition(font?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    }

    static func checkChanges() {
        let text = "😀 Il a ecrit aujourdhui, c'est l'ete. Ecrit ecrit!"
        let corrected = "😀 Il a écrit aujourd’hui, c'est l'été. Écrit écrit!"
        let outcome = CorrectionDiff.merge(corrected: corrected, into: NSAttributedString(string: text))
        precondition(outcome.text.string == corrected)
        precondition(outcome.changes.map(\.original) == ["ecrit", "aujourdhui", "l'ete", "Ecrit", "ecrit"])
        precondition(outcome.changes.map(\.replacement) == ["écrit", "aujourd’hui", "l'été", "Écrit", "écrit"])
        for change in outcome.changes {
            precondition((text as NSString).substring(with: change.sourceRange) == change.original)
            precondition((outcome.text.string as NSString).substring(with: change.resultRange) == change.replacement)
        }
        // The emoji is two UTF-16 units; the repeated word keeps its own position.
        precondition(outcome.changes[0].sourceRange == NSRange(location: 8, length: 5))
        precondition(outcome.changes[4].sourceRange == (text as NSString).range(of: "ecrit", options: .backwards))

        let unchanged = CorrectionDiff.merge(corrected: text, into: NSAttributedString(string: text))
        precondition(unchanged.changes.isEmpty && unchanged.text.string == text)
        let empty = CorrectionDiff.merge(corrected: "", into: NSAttributedString(string: ""))
        precondition(empty.changes.isEmpty && empty.text.length == 0)

        // Composed and decomposed accents are the same text: the original bytes stay and nothing is reported.
        let decomposed = "un cafe\u{301} froid, `re\u{301}sume\u{301}.txt` et ecrit"
        let composed = CorrectionDiff.merge(corrected: "un caf\u{E9} froid, `r\u{E9}sum\u{E9}.txt` et écrit",
                                            into: NSAttributedString(string: decomposed))
        precondition(composed.text.string.utf16.elementsEqual("un cafe\u{301} froid, `re\u{301}sume\u{301}.txt` et écrit".utf16))
        precondition(composed.changes.map(\.replacement) == ["écrit"])
        precondition((composed.text.string as NSString).substring(with: composed.changes[0].resultRange) == "écrit")
    }

    /// Punctuation, spacing, URLs and added or removed words are shown, not rejected.
    static func checkAnyEditIsShown() {
        let source = NSAttributedString(string: "Voir https://example.com/ecrit, puis  ecrit.")
        let corrected = "Voir https://exemple.com/écrit, puis écrit !"
        let outcome = CorrectionDiff.merge(corrected: corrected, into: source)
        precondition(outcome.text.string == corrected)
        // Neighbouring edits form one change: "  ecrit." → " écrit !".
        precondition(outcome.changes.map(\.replacement) == ["exemple", "écrit", " écrit !"])
        for change in outcome.changes {
            precondition((source.string as NSString).substring(with: change.sourceRange) == change.original)
            precondition((corrected as NSString).substring(with: change.resultRange) == change.replacement)
        }

        let inserted = CorrectionDiff.merge(corrected: "Bonjour, Claire", into: NSAttributedString(string: "Bonjour Claire"))
        precondition(inserted.changes.count == 1 && inserted.changes[0].sourceRange.length == 0)
        precondition(inserted.changes[0].replacement == ",")

        let removed = CorrectionDiff.merge(corrected: "Merci", into: NSAttributedString(string: "Merci merci"))
        precondition(removed.changes.count == 1 && removed.changes[0].resultRange.length == 0)
        precondition(removed.changes[0].original == " merci" && removed.text.string == "Merci")
    }
}
