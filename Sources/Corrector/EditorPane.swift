import AppKit

enum HighlightStyle {
    /// A word in the original that the correction changed.
    case misspelling
    /// A word in the corrected text that differs from the original.
    case correction
}

/// A centered message shown in a pane instead of its text.
struct PaneMessage {
    var symbol: String
    var title: String
    var detail: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    /// Shows a spinner in place of the symbol.
    var showsProgress = false

    fileprivate func looksLike(_ other: PaneMessage) -> Bool {
        symbol == other.symbol && title == other.title && detail == other.detail
            && actionTitle == other.actionTitle && showsProgress == other.showsProgress
    }
}

/// A titled text column: a header with a detail on the trailing side, then the scrolling text.
@MainActor
final class EditorPane: NSView {
    let textView: EditorTextView
    let scrollView = NSScrollView()

    var detailText = "" {
        didSet {
            guard detailText != oldValue else { return }
            detailLabel.stringValue = detailText
            detailLabel.isHidden = detailText.isEmpty
        }
    }
    var detailSymbol: String? {
        didSet {
            guard detailSymbol != oldValue else { return }
            detailImage.image = detailSymbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
            detailImage.isHidden = detailImage.image == nil
        }
    }
    var detailTint: NSColor? {
        didSet { detailImage.contentTintColor = detailTint ?? .secondaryLabelColor }
    }
    var isBusy = false {
        didSet {
            guard isBusy != oldValue else { return }
            spinner.isHidden = !isBusy
            isBusy ? spinner.startAnimation(nil) : spinner.stopAnimation(nil)
        }
    }
    /// Fades the text, for a result that no longer matches the original.
    var isDimmed = false {
        didSet {
            guard isDimmed != oldValue else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                scrollView.animator().alphaValue = isDimmed ? 0.4 : 1
            }
        }
    }
    /// Replaces the text with a centered message. The text and its highlights are kept for when it returns.
    var message: PaneMessage? {
        didSet {
            messageView.action = message?.action
            if let message {
                if oldValue.map({ message.looksLike($0) }) != true { messageView.show(message) }
            } else if oldValue == nil {
                return
            }
            messageView.isHidden = message == nil
            scrollView.isHidden = message != nil
            updateHeaderSeparator()
        }
    }
    /// Display magnification of the text, clamped to `Preferences.textZoomRange`.
    var zoom: CGFloat = 1 {
        didSet {
            zoom = min(max(zoom, Preferences.textZoomRange.lowerBound), Preferences.textZoomRange.upperBound)
            if scrollView.magnification != zoom { magnify(to: zoom) }
        }
    }
    /// Called when the user changes the zoom with a trackpad pinch.
    var onZoomChange: ((CGFloat) -> Void)?

    private let header = NSView()
    private let titleLabel: NSTextField
    private let detailLabel = NSTextField(labelWithString: "")
    private let detailImage = NSImageView()
    private let spinner = NSProgressIndicator()
    private let headerSeparator = NSBox()
    private let messageView = EditorMessageView()

    init(title: String, textView: EditorTextView) {
        self.textView = textView
        titleLabel = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        textView.setAccessibilityLabel(title)
        buildHeader()
        buildScrollView()
        messageView.isHidden = true
        messageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(messageView)
        NSLayoutConstraint.activate([
            messageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            // Slightly above the true center, which reads as centered.
            messageView.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor, constant: -12)
                .withPriority(.defaultHigh),
            messageView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            messageView.topAnchor.constraint(greaterThanOrEqualTo: header.bottomAnchor, constant: 8)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func buildHeader() {
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        detailLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.isHidden = true
        detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        detailImage.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        detailImage.contentTintColor = .secondaryLabelColor
        detailImage.isHidden = true
        detailImage.setAccessibilityElement(false)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.isHidden = true

        let trailing = NSStackView(views: [spinner, detailImage, detailLabel])
        trailing.orientation = .horizontal
        trailing.alignment = .centerY
        trailing.spacing = 5
        trailing.setCustomSpacing(8, after: spinner)
        trailing.setHuggingPriority(.required, for: .horizontal)

        headerSeparator.boxType = .separator
        headerSeparator.isHidden = true

        for view in [titleLabel, trailing, headerSeparator] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            header.addSubview(view)
        }
        header.translatesAutoresizingMaskIntoConstraints = false
        addSubview(header)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: topAnchor),
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 34),
            titleLabel.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: Self.textInset),
            titleLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            trailing.leadingAnchor.constraint(greaterThanOrEqualTo: titleLabel.trailingAnchor, constant: 12),
            trailing.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -Self.textInset),
            trailing.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            headerSeparator.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            headerSeparator.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            headerSeparator.bottomAnchor.constraint(equalTo: header.bottomAnchor)
        ])
    }

    /// Distance from the pane edge to the text, so the header lines up with it.
    private static var textInset: CGFloat { 20 }

    private func buildScrollView() {
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.allowsMagnification = true
        scrollView.minMagnification = Preferences.textZoomRange.lowerBound
        scrollView.maxMagnification = Preferences.textZoomRange.upperBound
        scrollView.documentView = textView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])

        let clipView = scrollView.contentView
        clipView.postsBoundsChangedNotifications = true
        clipView.postsFrameChangedNotifications = true
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(clipViewDidChange),
                           name: NSView.boundsDidChangeNotification, object: clipView)
        center.addObserver(self, selector: #selector(clipViewDidChange),
                           name: NSView.frameDidChangeNotification, object: clipView)
        center.addObserver(self, selector: #selector(didEndMagnifying),
                           name: NSScrollView.didEndLiveMagnifyNotification, object: scrollView)
    }

    @objc private func clipViewDidChange(_ notification: Notification) {
        // Autoresizing ignores magnification, so keep the text as wide as what is visible. The tolerance
        // avoids a feedback loop with the clip view's rounding of magnified bounds.
        let width = scrollView.contentView.bounds.width
        if width > 0, abs(textView.frame.width - width) > 0.5 {
            textView.setFrameSize(NSSize(width: width, height: textView.frame.height))
        }
        updateHeaderSeparator()
    }

    @objc private func didEndMagnifying(_ notification: Notification) {
        zoom = scrollView.magnification
        onZoomChange?(zoom)
    }

    /// Zooms while keeping the first visible line at the top, instead of zooming around the center.
    private func magnify(to magnification: CGFloat) {
        let topLine = firstVisibleCharacter()
        scrollView.magnification = magnification
        // Rewrapping and the text view's own layout both move the scroll position; settle them first.
        if let layoutManager = textView.layoutManager, let container = textView.textContainer {
            layoutManager.ensureLayout(for: container)
        }
        scrollView.layoutSubtreeIfNeeded()
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: topLine.map(lineTop) ?? 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func firstVisibleCharacter() -> Int? {
        let top = scrollView.documentVisibleRect.minY
        guard top > 0, let layoutManager = textView.layoutManager, let container = textView.textContainer,
              layoutManager.numberOfGlyphs > 0 else { return nil }
        let point = NSPoint(x: 0, y: top - textView.textContainerOrigin.y)
        let glyph = layoutManager.glyphIndex(for: point, in: container)
        // Within the first line, the top inset is still in view and should stay there.
        guard layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY > 0 else { return nil }
        return layoutManager.characterIndexForGlyph(at: glyph)
    }

    private func lineTop(_ character: Int) -> CGFloat {
        guard let layoutManager = textView.layoutManager else { return 0 }
        let glyph = layoutManager.glyphIndexForCharacter(at: character)
        return layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY + textView.textContainerOrigin.y
    }

    private func updateHeaderSeparator() {
        let scrolled = !scrollView.isHidden && scrollView.documentVisibleRect.minY > 1
        if headerSeparator.isHidden == scrolled { headerSeparator.isHidden = !scrolled }
    }

    override func layout() {
        messageView.maxWidth = min(300, max(120, bounds.width - 48))
        super.layout()
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        dirtyRect.fill()
    }

    override func mouseDown(with event: NSEvent) {
        if textView.isEditable, message == nil {
            window?.makeFirstResponder(textView)
        } else {
            super.mouseDown(with: event)
        }
    }
}

/// Symbol, title, detail and an optional button, stacked and centered.
@MainActor
private final class EditorMessageView: NSView {
    var action: (() -> Void)?
    var maxWidth: CGFloat = 300 {
        didSet {
            guard maxWidth != oldValue else { return }
            titleLabel.preferredMaxLayoutWidth = maxWidth
            detailLabel.preferredMaxLayoutWidth = maxWidth
            widthLimit.constant = maxWidth
        }
    }

    private let symbolView = NSImageView()
    private let spinner = NSProgressIndicator()
    private let titleLabel = NSTextField(wrappingLabelWithString: "")
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private let button = NSButton(title: "", target: nil, action: nil)
    private let stack = NSStackView()
    private lazy var widthLimit = stack.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth)

    init() {
        super.init(frame: .zero)
        symbolView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 34, weight: .regular)
        symbolView.contentTintColor = .tertiaryLabelColor
        symbolView.setAccessibilityElement(false)

        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.isDisplayedWhenStopped = false

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = .labelColor
        detailLabel.font = .systemFont(ofSize: 13)
        detailLabel.textColor = .secondaryLabelColor
        for label in [titleLabel, detailLabel] {
            label.alignment = .center
            label.isSelectable = false
            label.preferredMaxLayoutWidth = maxWidth
        }

        button.bezelStyle = .rounded
        button.target = self
        button.action = #selector(performAction)

        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 4
        stack.setViews([symbolView, spinner, titleLabel, detailLabel, button], in: .center)
        stack.setCustomSpacing(12, after: symbolView)
        stack.setCustomSpacing(12, after: spinner)
        stack.setCustomSpacing(16, after: detailLabel)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            widthLimit
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show(_ message: PaneMessage) {
        symbolView.image = NSImage(systemSymbolName: message.symbol, accessibilityDescription: nil)
        symbolView.isHidden = message.showsProgress || symbolView.image == nil
        spinner.isHidden = !message.showsProgress
        message.showsProgress ? spinner.startAnimation(nil) : spinner.stopAnimation(nil)
        titleLabel.stringValue = message.title
        detailLabel.stringValue = message.detail ?? ""
        detailLabel.isHidden = message.detail?.isEmpty ?? true
        button.title = message.actionTitle ?? ""
        button.isHidden = message.actionTitle == nil
        // After the detail the button needs room; without one the detail ends the stack.
        stack.setCustomSpacing(detailLabel.isHidden ? 16 : 4, after: titleLabel)
    }

    @objc private func performAction() {
        action?()
    }
}

private extension NSLayoutConstraint {
    func withPriority(_ priority: NSLayoutConstraint.Priority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}

/// Keeps two scroll views at the same relative vertical position.
@MainActor
final class ScrollSynchronizer: NSObject {
    private weak var first: NSScrollView?
    private weak var second: NSScrollView?
    private var isSynchronizing = false

    init(_ first: NSScrollView, _ second: NSScrollView) {
        self.first = first
        self.second = second
        super.init()
        for scrollView in [first, second] {
            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(boundsDidChange),
                                                   name: NSView.boundsDidChangeNotification,
                                                   object: scrollView.contentView)
        }
    }

    @objc private func boundsDidChange(_ notification: Notification) {
        guard !isSynchronizing, let first, let second else { return }
        let source = (notification.object as? NSClipView) === first.contentView ? first : second
        let target = source === first ? second : first
        isSynchronizing = true
        defer { isSynchronizing = false }

        let sourceRange = Self.scrollableHeight(source)
        let targetRange = Self.scrollableHeight(target)
        let fraction = sourceRange > 0 ? min(max(source.contentView.bounds.minY / sourceRange, 0), 1) : 0
        var origin = target.contentView.bounds.origin
        let y = (fraction * targetRange).rounded()
        guard abs(origin.y - y) >= 1 else { return }
        origin.y = y
        target.contentView.scroll(to: origin)
        target.reflectScrolledClipView(target.contentView)
    }

    private static func scrollableHeight(_ scrollView: NSScrollView) -> CGFloat {
        max(0, (scrollView.documentView?.frame.height ?? 0) - scrollView.contentView.bounds.height)
    }
}
