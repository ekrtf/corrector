import AppKit

@main
struct FormattingGuardTests {
    static func main() throws {
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

        print("Formatting guard checks passed")
    }
}
