import AppKit

@MainActor
final class EditorTextView: NSTextView {
    var didPaste: (() -> Void)?
    /// Called just before a paste. The argument is true when the paste keeps rich text formatting.
    var onPasteboardKind: ((Bool) -> Void)?
    var placeholder: String? { didSet { needsDisplay = true } }
    /// Whether Copy, Cut and drags offer rich text. Plain text must stay plain so that pasting it back
    /// is not mistaken for a rich-text paste, and the display font never reaches other apps.
    var writesRichText = true

    override var writablePasteboardTypes: [NSPasteboard.PasteboardType] {
        writesRichText ? super.writablePasteboardTypes : [.string]
    }

    /// Attributes for text the app inserts itself, matching what the user gets when typing.
    nonisolated static var textAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.labelColor]
    }

    private static let richTypes: [NSPasteboard.PasteboardType] = [.rtf, .rtfd, .html]
    private let lineSpacing = LineSpacing()
    private var highlightedStyles: Set<HighlightStyle> = []
    private var isEmpty = true

    static func make(editable: Bool) -> EditorTextView {
        let view = EditorTextView(usingTextLayoutManager: false)
        view.configure(editable: editable)
        return view
    }

    private func configure(editable: Bool) {
        let layoutManager = HighlightLayoutManager()
        textContainer?.replaceLayoutManager(layoutManager)
        layoutManager.delegate = lineSpacing

        isEditable = editable
        isSelectable = true
        isRichText = true
        allowsUndo = editable
        usesFindBar = true
        isIncrementalSearchingEnabled = true
        font = .systemFont(ofSize: 14)
        textColor = .labelColor
        backgroundColor = .textBackgroundColor
        drawsBackground = true
        // Pasted rich text often has explicit black text; map it for dark mode when drawing only.
        usesAdaptiveColorMappingForDarkAppearance = true
        textContainerInset = NSSize(width: 15, height: 12)
        minSize = .zero
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        isVerticallyResizable = true
        isHorizontallyResizable = false
        // EditorPane sets the width itself; autoresizing ignores magnification and would fight it.
        autoresizingMask = []
        textContainer?.widthTracksTextView = true
        textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        // Corrector is the spell checker; silent substitutions would change the text being checked.
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticTextCompletionEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isAutomaticDataDetectionEnabled = false
        smartInsertDeleteEnabled = false

        NotificationCenter.default.addObserver(self, selector: #selector(storageDidProcessEditing),
                                               name: NSTextStorage.didProcessEditingNotification, object: textStorage)
    }

    // MARK: Paste

    override func paste(_ sender: Any?) {
        guard isEditable else { return super.paste(sender) }
        onPasteboardKind?(keepsRichText(from: .general))
        super.paste(sender)
        notifyPaste()
    }

    override func pasteAsPlainText(_ sender: Any?) {
        guard isEditable else { return super.pasteAsPlainText(sender) }
        onPasteboardKind?(false)
        super.pasteAsPlainText(sender)
        notifyPaste()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        // Moving text within this view is an edit, not a paste.
        let isPaste = isEditable && (sender.draggingSource as? NSView) !== self
        if isPaste { onPasteboardKind?(keepsRichText(from: sender.draggingPasteboard)) }
        let accepted = super.performDragOperation(sender)
        if isPaste && accepted { notifyPaste() }
        return accepted
    }

    private func keepsRichText(from pasteboard: NSPasteboard) -> Bool {
        isRichText && pasteboard.availableType(from: Self.richTypes) != nil
    }

    private func notifyPaste() {
        DispatchQueue.main.async { [weak self] in self?.didPaste?() }
    }

    override func cancelOperation(_ sender: Any?) {
        // NSTextView turns Esc into word completion; let the window handle it instead.
        nextResponder?.tryToPerform(#selector(NSResponder.cancelOperation(_:)), with: sender)
    }

    // MARK: Highlights

    /// Replaces the highlights of one style. They are drawn only, never stored in the text.
    func setHighlights(_ ranges: [NSRange], style: HighlightStyle) {
        guard let layoutManager, let length = textStorage?.length else { return }
        removeHighlights(style)
        let attributes = Self.attributes(for: style)
        for range in ranges where range.location >= 0 && range.location < length && range.length > 0 {
            let clamped = NSRange(location: range.location, length: min(range.length, length - range.location))
            layoutManager.addTemporaryAttributes(attributes, forCharacterRange: clamped)
            highlightedStyles.insert(style)
        }
    }

    func clearHighlights() {
        removeHighlights(.misspelling)
        removeHighlights(.correction)
    }

    private func removeHighlights(_ style: HighlightStyle) {
        guard highlightedStyles.remove(style) != nil, let layoutManager, let length = textStorage?.length else { return }
        let all = NSRange(location: 0, length: length)
        for key in Self.attributes(for: style).keys {
            layoutManager.removeTemporaryAttribute(key, forCharacterRange: all)
        }
        // Marked text (a pending accent, for example) is drawn with temporary attributes too.
        if hasMarkedText(), let marked = markedTextAttributes {
            layoutManager.addTemporaryAttributes(marked, forCharacterRange: markedRange())
        }
    }

    private static func attributes(for style: HighlightStyle) -> [NSAttributedString.Key: Any] {
        switch style {
        case .misspelling:
            // The system's own misspelling marker: red dots that skip nothing and scale with zoom.
            return [.spellingState: NSAttributedString.SpellingState.spelling.rawValue]
        case .correction:
            return [.backgroundColor: HighlightLayoutManager.correctionColor]
        }
    }

    // MARK: Placeholder

    @objc private func storageDidProcessEditing(_ notification: Notification) {
        let empty = textStorage?.length == 0
        guard empty != isEmpty else { return }
        isEmpty = empty
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let placeholder, !placeholder.isEmpty, textStorage?.length == 0 else { return }
        let padding = textContainer?.lineFragmentPadding ?? 0
        let origin = textContainerOrigin
        let rect = NSRect(x: origin.x + padding, y: origin.y,
                          width: bounds.width - 2 * (origin.x + padding), height: bounds.height - origin.y)
        let style = NSMutableParagraphStyle()
        style.lineSpacing = LineSpacing.value
        let font = typingAttributes[.font] as? NSFont ?? .systemFont(ofSize: 14)
        NSAttributedString(string: placeholder, attributes: [
            .font: font, .foregroundColor: NSColor.placeholderTextColor, .paragraphStyle: style
        ]).draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
}

/// Adds display-only line spacing, so the text storage (and the clipboard) never gets a paragraph style.
private final class LineSpacing: NSObject, NSLayoutManagerDelegate {
    static let value: CGFloat = 4

    func layoutManager(_ layoutManager: NSLayoutManager, lineSpacingAfterGlyphAt glyphIndex: Int,
                       withProposedLineFragmentRect rect: NSRect) -> CGFloat {
        Self.value
    }

    func layoutManager(_ layoutManager: NSLayoutManager,
                       shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>,
                       lineFragmentUsedRect: UnsafeMutablePointer<NSRect>,
                       baselineOffset: UnsafeMutablePointer<CGFloat>,
                       in textContainer: NSTextContainer, forGlyphRange glyphRange: NSRange) -> Bool {
        // The insertion point and correction highlights follow the used rect; keep them as tall as the text.
        lineFragmentUsedRect.pointee.size.height -= Self.value
        return true
    }
}

/// Draws correction highlights as rounded rectangles around the glyphs rather than full line-height bands.
private final class HighlightLayoutManager: NSLayoutManager {
    static let correctionColor = NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return NSColor.systemGreen.withAlphaComponent(dark ? 0.3 : 0.22)
    }

    override func fillBackgroundRectArray(_ rectArray: UnsafePointer<NSRect>, count rectCount: Int,
                                          forCharacterRange charRange: NSRange, color: NSColor) {
        guard color === Self.correctionColor else {
            return super.fillBackgroundRectArray(rectArray, count: rectCount, forCharacterRange: charRange, color: color)
        }
        color.setFill()
        for index in 0..<rectCount {
            NSBezierPath(roundedRect: rectArray[index].insetBy(dx: -2, dy: 0), xRadius: 4, yRadius: 4).fill()
        }
    }
}
