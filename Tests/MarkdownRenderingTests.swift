import AppKit

@main
struct MarkdownRenderingTests {
    static func main() throws {
        let value = MarkdownRenderer.render("# Titre\n**bonjour** [ici](https://example.com)\n- item\n")!
        precondition(value.string == "Titre\nbonjour ici\n• item\n")
        let wordRange = (value.string as NSString).range(of: "bonjour")
        let wordFont = value.attribute(.font, at: wordRange.location, effectiveRange: nil) as? NSFont
        precondition(wordFont?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        let linkRange = (value.string as NSString).range(of: "ici")
        precondition(value.attribute(.link, at: linkRange.location, effectiveRange: nil) as? URL == URL(string: "https://example.com"))
        print("Markdown rendering checks passed")
    }
}
