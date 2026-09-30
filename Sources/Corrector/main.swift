import AppKit

final class PasteAwareTextView: NSTextView {
    var didPaste: (() -> Void)?
    var onPasteboardKind: ((Bool) -> Void)?

    override func paste(_ sender: Any?) {
        let board = NSPasteboard.general
        onPasteboardKind?(board.availableType(from: [.rtf, .html]) != nil)
        super.paste(sender)
        DispatchQueue.main.async { [weak self] in self?.didPaste?() }
    }
}

@MainActor
final class CorrectorApp: NSObject, NSApplicationDelegate, NSWindowDelegate, NSTextViewDelegate {
    private var panel: NSPanel!
    private let sourceView = PasteAwareTextView(frame: .zero)
    private let resultView = NSTextView(frame: .zero)
    private let statusLabel = NSTextField(labelWithString: "Paste French or English text to begin.")
    private let copyButton = NSButton(title: "Copy corrected text", target: nil, action: nil)
    private let modelChoice = NSPopUpButton(frame: .zero, pullsDown: false)
    private let formatChoice = NSPopUpButton(frame: .zero, pullsDown: false)
    private var sourceWasRichText = false
    private var result: NSAttributedString?
    private var correctionTask: Task<Void, Never>?
    private var revision = 0
    private let client = OpenRouterClient()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildWindow()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeFirstResponder(sourceView)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeFirstResponder(sourceView)
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        panel.orderOut(nil)
        return false
    }

    private func buildWindow() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 830, height: 490),
                        styleMask: [.titled, .closable, .resizable, .utilityWindow],
                        backing: .buffered, defer: false)
        panel.title = "Corrector"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 650, height: 360)
        panel.center()
        panel.delegate = self

        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 12
        root.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        root.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView?.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor),
            root.topAnchor.constraint(equalTo: panel.contentView!.topAnchor),
            root.bottomAnchor.constraint(equalTo: panel.contentView!.bottomAnchor)
        ])

        let controls = NSStackView()
        controls.orientation = .horizontal
        controls.spacing = 8
        controls.alignment = .centerY
        let modelLabel = NSTextField(labelWithString: "Model")
        let models: [(String, String?)] = [
            ("Automatic (fastest)", nil),
            ("DeepSeek V4.1 Flash", "deepseek/deepseek-v4.1-flash"),
            ("Mistral Small", "mistralai/mistral-small-2603"),
            ("Gemini 3.5 Flash Lite", "google/gemini-3.5-flash-lite"),
            ("GPT-6 Luna", "openai/gpt-6-luna")
        ]
        for (name, slug) in models {
            modelChoice.addItem(withTitle: name)
            modelChoice.lastItem?.representedObject = slug
        }
        if let custom = UserDefaults.standard.string(forKey: "customModel"), !custom.isEmpty {
            modelChoice.addItem(withTitle: custom)
            modelChoice.lastItem?.representedObject = custom
        }
        modelChoice.addItem(withTitle: "Other model…")
        modelChoice.target = self
        modelChoice.action = #selector(modelChanged)
        if let saved = UserDefaults.standard.string(forKey: "selectedModel") {
            let match = modelChoice.itemArray.first { ($0.representedObject as? String) == saved }
            if let match { modelChoice.select(match) }
        }
        formatChoice.addItems(withTitles: ["Detect format", "Plain text", "Markdown", "Rich text"])
        formatChoice.target = self
        formatChoice.action = #selector(formatChanged)
        let keyButton = NSButton(title: "API key…", target: self, action: #selector(editAPIKey))
        controls.addArrangedSubview(modelLabel)
        controls.addArrangedSubview(modelChoice)
        controls.addArrangedSubview(formatChoice)
        controls.addArrangedSubview(NSView())
        controls.addArrangedSubview(keyButton)
        root.addArrangedSubview(controls)

        let columns = NSStackView()
        columns.orientation = .horizontal
        columns.spacing = 12
        columns.distribution = .fillEqually
        let sourceColumn = makeColumn(title: "Original", textView: sourceView, editable: true)
        let resultColumn = makeColumn(title: "Corrected", textView: resultView, editable: false)
        columns.addArrangedSubview(sourceColumn)
        columns.addArrangedSubview(resultColumn)
        root.addArrangedSubview(columns)
        columns.setContentHuggingPriority(.defaultLow, for: .vertical)
        NSLayoutConstraint.activate([
            columns.heightAnchor.constraint(greaterThanOrEqualToConstant: 260),
            sourceColumn.widthAnchor.constraint(equalTo: resultColumn.widthAnchor)
        ])

        let footer = NSStackView()
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 10
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        copyButton.target = self
        copyButton.action = #selector(copyResult)
        copyButton.isEnabled = false
        footer.addArrangedSubview(statusLabel)
        footer.addArrangedSubview(copyButton)
        root.addArrangedSubview(footer)

        sourceView.didPaste = { [weak self] in self?.startCorrection() }
        sourceView.onPasteboardKind = { [weak self] rich in self?.sourceWasRichText = rich }
        sourceView.delegate = self
        if KeychainStore.readKey() == nil {
            DispatchQueue.main.async { [weak self] in self?.requestAPIKey() }
        }
    }

    func textDidChange(_ notification: Notification) {
        guard notification.object as? NSTextView === sourceView else { return }
        correctionTask?.cancel()
        revision += 1
        result = nil
        resultView.string = ""
        copyButton.isEnabled = false
        statusLabel.stringValue = "Paste text to correct it."
    }

    private func makeColumn(title: String, textView: NSTextView, editable: Bool) -> NSView {
        let column = NSStackView()
        column.orientation = .vertical
        column.spacing = 6
        column.addArrangedSubview(NSTextField(labelWithString: title))
        let scroll = NSScrollView()
        scroll.borderType = .bezelBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        textView.frame = NSRect(x: 0, y: 0, width: 380, height: 300)
        textView.isRichText = true
        textView.isEditable = editable
        textView.isSelectable = true
        textView.allowsUndo = editable
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        scroll.documentView = textView
        column.addArrangedSubview(scroll)
        scroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        return column
    }

    @objc private func editAPIKey() { requestAPIKey() }

    @discardableResult
    private func requestAPIKey() -> Bool {
        let alert = NSAlert()
        alert.messageText = "OpenRouter API key"
        alert.informativeText = "Your key is stored in the macOS Keychain. Pasted text is sent to OpenRouter for correction."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "sk-or-v1-…"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return false }
        let key = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, KeychainStore.saveKey(key) else {
            statusLabel.stringValue = "Could not save the API key."
            return false
        }
        statusLabel.stringValue = "API key saved. Paste text to correct it."
        return true
    }

    @objc private func modelChanged() {
        if modelChoice.selectedItem?.title == "Other model…" {
            let alert = NSAlert()
            alert.messageText = "Use a specific OpenRouter model"
            alert.informativeText = "Enter a model ID, for example provider/model-name."
            alert.addButton(withTitle: "Use model")
            alert.addButton(withTitle: "Cancel")
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
            field.placeholderString = "provider/model-name"
            field.stringValue = UserDefaults.standard.string(forKey: "customModel") ?? ""
            alert.accessoryView = field
            if alert.runModal() == .alertFirstButtonReturn {
                let model = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !model.isEmpty {
                    if let previous = UserDefaults.standard.string(forKey: "customModel"),
                       previous != model,
                       let item = modelChoice.itemArray.first(where: { ($0.representedObject as? String) == previous }),
                       modelChoice.index(of: item) >= 5 {
                        modelChoice.removeItem(at: modelChoice.index(of: item))
                    }
                    UserDefaults.standard.set(model, forKey: "customModel")
                    if let existing = modelChoice.itemArray.first(where: { ($0.representedObject as? String) == model }) {
                        modelChoice.select(existing)
                    } else {
                        let index = modelChoice.numberOfItems - 1
                        modelChoice.insertItem(withTitle: model, at: index)
                        modelChoice.item(at: index)?.representedObject = model
                        modelChoice.selectItem(at: index)
                    }
                    UserDefaults.standard.set(model, forKey: "selectedModel")
                } else { modelChoice.selectItem(at: 0) }
            } else { modelChoice.selectItem(at: 0) }
        } else {
            UserDefaults.standard.set(modelChoice.selectedItem?.representedObject as? String, forKey: "selectedModel")
        }
    }

    @objc private func formatChanged() {
        if let raw = result, !raw.string.isEmpty {
            // A new paste starts the next correction with the selected format.
            statusLabel.stringValue = "Format will apply to the next paste."
        }
    }

    private var selectedModelOverride: String? {
        modelChoice.selectedItem?.representedObject as? String
    }

    private var renderMarkdown: Bool {
        switch formatChoice.indexOfSelectedItem {
        case 1, 3: return false
        case 2: return true
        default:
            guard !sourceWasRichText else { return false }
            let text = sourceView.string
            return text.range(of: #"(?m)^\s{0,3}(?:#{1,6}\s|[-*+]\s|\d+\.\s)|\*\*[^*]+\*\*|\[[^]]+\]\([^)]+\)"#,
                              options: .regularExpression) != nil
        }
    }

    private func startCorrection() {
        correctionTask?.cancel()
        revision += 1
        let currentRevision = revision
        let original = NSAttributedString(attributedString: sourceView.attributedString())
        let input = original.string
        guard !input.isEmpty else { return }
        guard let key = KeychainStore.readKey() ?? (requestAPIKey() ? KeychainStore.readKey() : nil) else {
            statusLabel.stringValue = "Add an OpenRouter API key to correct text."
            return
        }
        result = nil
        resultView.string = ""
        copyButton.isEnabled = false
        statusLabel.stringValue = "Correcting…"
        let markdown = renderMarkdown
        let override = selectedModelOverride
        correctionTask = Task { [weak self] in
            guard let self else { return }
            do {
                let model: String
                if let override {
                    model = override
                } else {
                    model = await ModelSelector.shared.fastestAvailable()
                }
                try Task.checkCancellation()
                statusLabel.stringValue = "Correcting with \(model)…"
                let corrected = try await client.correct(input, apiKey: key, model: model)
                try Task.checkCancellation()
                let formatted = try FormattingGuard.apply(corrected: corrected, to: original)
                guard revision == currentRevision else { return }
                let display = markdown ? (MarkdownRenderer.render(corrected) ?? formatted) : formatted
                result = display
                resultView.textStorage?.setAttributedString(display)
                copyButton.isEnabled = true
                statusLabel.stringValue = corrected == input ? "No spelling changes found." : "Ready to copy."
            } catch is CancellationError {
                return
            } catch {
                guard revision == currentRevision else { return }
                statusLabel.stringValue = error.localizedDescription
            }
        }
    }

    @objc private func copyResult() {
        guard let result else { return }
        let board = NSPasteboard.general
        board.clearContents()
        if board.writeObjects([result]) {
            statusLabel.stringValue = "Copied corrected text."
        } else {
            statusLabel.stringValue = "Could not copy the text."
        }
    }
}

MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = CorrectorApp()
    application.delegate = delegate
    application.run()
}
