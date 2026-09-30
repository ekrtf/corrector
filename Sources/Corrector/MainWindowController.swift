import AppKit

typealias CorrectionService = @Sendable (_ text: String, _ apiKey: String, _ model: String) async throws -> String

@MainActor
final class MainWindowController: NSWindowController {
    private let correctText: CorrectionService
    private let readAPIKey: () -> String?
    private let resolveAutomaticModel: @Sendable () async -> String

    private let sourceView = EditorTextView.make(editable: true)
    private let resultView = EditorTextView.make(editable: false)
    private let sourcePane: EditorPane
    private let resultPane: EditorPane
    private let splitView = NSSplitView()
    private let modelPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let formatPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private var scrollSynchronizer: ScrollSynchronizer?
    private var observers: [NSObjectProtocol] = []
    private var defaultTypingAttributes: [NSAttributedString.Key: Any] = [:]

    private var state = State.idle { didSet { render() } }
    private var sourceWasRichText = false
    private var cachedAPIKey: String?
    private var checkTask: Task<Void, Never>?
    private var typingCheck: Task<Void, Never>?
    private var revision = 0
    private var isApplyingCorrections = false
    private var shownResult: NSAttributedString?
    private var renderedEmptySource = true
    private var statusSubtitle = ""
    private var flashTask: Task<Void, Never>?
    private var listedModels: [ModelOption] = []
    private var appliedModel = Preferences.selectedModel
    private var appliedFormat = Preferences.format

    private static let zoomLevels: [CGFloat] = [0.75, 0.85, 1, 1.15, 1.3, 1.5, 1.75, 2, 2.5]

    init(correct: @escaping CorrectionService = { try await OpenRouterClient().correct($0, apiKey: $1, model: $2) },
         apiKey: @escaping () -> String? = { KeychainStore.readKey() },
         automaticModel: @escaping @Sendable () async -> String = { await ModelSelector.shared.fastestAvailable() }) {
        correctText = correct
        readAPIKey = apiKey
        resolveAutomaticModel = automaticModel
        sourcePane = EditorPane(title: "Original", textView: sourceView)
        resultPane = EditorPane(title: "Corrected", textView: resultView)
        super.init(window: nil)
        shouldCascadeWindows = false
        configureEditors()
        configurePopups()
        window = makePanel()
        observeNotifications()
        updateWordCount()
        state = restingState
        render()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var hasAPIKey: Bool { apiKey != nil }

    var stateDescriptionForTesting: String { state.name }

    /// Shows the window, activates the app, and focuses the original text.
    func showAndFocus() {
        guard let window else { return }
        window.makeKeyAndOrderFront(nil)
        if #available(macOS 14, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        if window.attachedSheet == nil { window.makeFirstResponder(sourceView) }
    }

    /// Replaces the original text as if it had been pasted, without starting a check.
    func loadSourceForTesting(_ text: NSAttributedString, rich: Bool) {
        sourceWasRichText = rich
        sourceView.textStorage?.setAttributedString(text)
        sourceTextDidChange()
    }

    /// Starts a correction of the original text now.
    @objc func checkSpelling(_ sender: Any?) {
        check()
    }

    // MARK: - Setup

    private func makePanel() -> NSPanel {
        let panel = MainPanel(contentRect: NSRect(x: 0, y: 0, width: 920, height: 560),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        panel.title = "Corrector"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 640, height: 380)
        panel.isReleasedWhenClosed = false
        panel.isExcludedFromWindowsMenu = false
        panel.tabbingMode = .disallowed
        panel.toolbarStyle = .unified
        panel.titlebarSeparatorStyle = .line

        let toolbar = NSToolbar(identifier: "CorrectorMainToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        panel.toolbar = toolbar

        panel.contentView = makeContentView()
        panel.initialFirstResponder = sourceView
        panel.center()
        panel.setFrameAutosaveName("CorrectorMainWindow")
        return panel
    }

    private func makeContentView() -> NSView {
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = self
        // Explicit starting frames give equal panes until the autosaved divider position exists.
        splitView.frame = NSRect(x: 0, y: 0, width: 920, height: 508)
        for pane in [sourcePane, resultPane] {
            pane.frame = NSRect(x: 0, y: 0, width: 460, height: 508)
            splitView.addArrangedSubview(pane)
        }
        splitView.adjustSubviews()
        splitView.autosaveName = "CorrectorSplitView"
        splitView.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(splitView)
        NSLayoutConstraint.activate([
            splitView.topAnchor.constraint(equalTo: content.safeAreaLayoutGuide.topAnchor),
            splitView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        return content
    }

    private func configureEditors() {
        sourceView.placeholder = "Paste or type French or English text"
        sourceView.onPasteboardKind = { [weak self] rich in self?.sourceWillPaste(rich: rich) }
        sourceView.didPaste = { [weak self] in self?.sourceDidPaste() }
        sourceView.nextKeyView = resultView
        resultView.nextKeyView = sourceView
        defaultTypingAttributes = sourceView.typingAttributes
        applyZoom(Preferences.textZoom)
        scrollSynchronizer = ScrollSynchronizer(sourcePane.scrollView, resultPane.scrollView)
    }

    private func configurePopups() {
        modelPopup.bezelStyle = .toolbar
        modelPopup.autoenablesItems = false
        modelPopup.translatesAutoresizingMaskIntoConstraints = false
        // Long custom model IDs truncate instead of crowding the toolbar.
        modelPopup.widthAnchor.constraint(lessThanOrEqualToConstant: 220).isActive = true
        modelPopup.toolTip = "Model"
        modelPopup.setAccessibilityLabel("Model")
        modelPopup.target = self
        modelPopup.action = #selector(modelPopupDidChange(_:))

        formatPopup.bezelStyle = .toolbar
        formatPopup.autoenablesItems = false
        formatPopup.translatesAutoresizingMaskIntoConstraints = false
        formatPopup.toolTip = "Format"
        formatPopup.setAccessibilityLabel("Format")
        formatPopup.target = self
        formatPopup.action = #selector(formatPopupDidChange(_:))
        for format in CorrectionFormat.allCases {
            let item = NSMenuItem(title: format.title, action: nil, keyEquivalent: "")
            item.tag = format.rawValue
            formatPopup.menu?.addItem(item)
            if format == .detect { formatPopup.menu?.addItem(.separator()) }
        }
        syncWithPreferences()
    }

    private func observeNotifications() {
        let center = NotificationCenter.default
        observers = [
            // Delivered synchronously so edits made by Apply Corrections can be told apart.
            center.addObserver(forName: NSText.didChangeNotification, object: sourceView, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated { self?.sourceTextDidChange() }
            },
            center.addObserver(forName: .apiKeyDidChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.apiKeyDidChange() }
            },
            center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.preferencesDidChange() }
            }
        ]
    }

    // MARK: - Correction flow

    private var apiKey: String? {
        if cachedAPIKey == nil, let key = readAPIKey(), !key.isEmpty { cachedAPIKey = key }
        return cachedAPIKey
    }

    private func check() {
        typingCheck?.cancel()
        checkTask?.cancel()
        revision += 1
        let source = NSAttributedString(attributedString: sourceView.attributedString())
        guard source.length > 0 else {
            state = restingState
            return
        }
        guard let key = apiKey else {
            state = .missingKey
            return
        }
        let checkRevision = revision
        let sourceWasRich = sourceWasRichText
        let chosenModel = Preferences.selectedModel
        let correct = correctText
        let resolveModel = resolveAutomaticModel
        let started = Date()
        state = .checking(model: chosenModel)
        checkTask = Task { [weak self] in
            do {
                let model: String
                if let chosenModel {
                    model = chosenModel
                } else {
                    model = await resolveModel()
                }
                try Task.checkCancellation()
                self?.modelResolved(model, revision: checkRevision)
                let corrected = try await correct(source.string, key, model)
                try Task.checkCancellation()
                guard let self, revision == checkRevision else { return }
                let outcome = try FormattingGuard.correct(corrected: corrected, original: source)
                state = .done(Correction(source: source, sourceWasRich: sourceWasRich, outcome: outcome, model: model,
                                         duration: Date().timeIntervalSince(started), format: Preferences.format))
            } catch is CancellationError {
            } catch {
                // URLSession reports cancellation as an error too; the revision check covers it.
                guard let self, !Task.isCancelled, revision == checkRevision else { return }
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// The state to show when nothing is checked or checking.
    private var restingState: State {
        hasAPIKey ? .idle : .missingKey
    }

    private func modelResolved(_ model: String, revision checkRevision: Int) {
        guard revision == checkRevision, case .checking = state else { return }
        state = .checking(model: model)
    }

    private func sourceWillPaste(rich: Bool) {
        let everything = NSRange(location: 0, length: (sourceView.string as NSString).length)
        sourceWasRichText = rich || (sourceWasRichText && sourceView.selectedRange() != everything)
    }

    private func sourceDidPaste() {
        guard Preferences.checksAfterPaste, !sourceView.string.isEmpty else { return }
        check()
    }

    private func sourceTextDidChange() {
        updateWordCount()
        guard !isApplyingCorrections else { return }
        revision += 1
        checkTask?.cancel()
        typingCheck?.cancel()
        let text = sourceView.attributedString()
        if text.length == 0 { sourceWasRichText = false }

        switch state {
        case .done(let correction), .stale(let correction):
            if text.length == 0 {
                state = restingState
            } else {
                // Undoing back to the checked text brings the result back.
                let current = text.isEqual(to: correction.source)
                if current != state.isDone { state = current ? .done(correction) : .stale(correction) }
            }
        case .checking, .failed:
            state = restingState
        case .idle:
            if renderedEmptySource != (text.length == 0) { render() }
        case .missingKey:
            break
        }

        if Preferences.checksWhileTyping, text.length > 0, !state.isDone { scheduleTypingCheck() }
    }

    private func scheduleTypingCheck() {
        typingCheck = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled, let self, !sourceView.hasMarkedText() else { return }
            check()
        }
    }

    private func apiKeyDidChange() {
        cachedAPIKey = nil
        let hasKey = hasAPIKey
        switch state {
        case .missingKey where hasKey:
            if sourceView.string.isEmpty { state = .idle } else { check() }
        case .failed where hasKey:
            check()
        case .idle where !hasKey:
            state = .missingKey
        default:
            break
        }
    }

    private func preferencesDidChange() {
        syncWithPreferences()
        if Preferences.textZoom != sourcePane.zoom { applyZoom(Preferences.textZoom) }
        if !Preferences.checksWhileTyping { typingCheck?.cancel() }

        let model = Preferences.selectedModel
        let format = Preferences.format
        let modelChanged = model != appliedModel
        let formatChanged = format != appliedFormat
        appliedModel = model
        appliedFormat = format
        if modelChanged {
            switch state {
            case .checking, .done, .stale, .failed: check()
            case .idle, .missingKey: break
            }
        } else if formatChanged, var correction = state.correction {
            // The format only changes how the result is shown and copied, so no new request is needed.
            correction.present(as: format)
            state = state.isStale ? .stale(correction) : .done(correction)
        }
    }

    private func syncWithPreferences() {
        let options = MainMenu.modelOptions()
        if options != listedModels || modelPopup.numberOfItems == 0 {
            listedModels = options
            modelPopup.removeAllItems()
            if let menu = modelPopup.menu { MainMenu.addModelItems(to: menu, choose: nil, other: nil) }
        }
        let selected = Preferences.selectedModel
        modelPopup.select(modelPopup.itemArray.first {
            !$0.isSeparatorItem && $0.tag != MainMenu.otherModelTag && $0.representedObject as? String == selected
        })
        formatPopup.selectItem(withTag: Preferences.format.rawValue)
    }

    // MARK: - Presentation

    private func render() {
        let sourceIsEmpty = sourceView.string.isEmpty
        renderedEmptySource = sourceIsEmpty
        flashTask?.cancel()

        var message: PaneMessage?
        var detail = ""
        var symbol: String?
        var tint: NSColor?
        switch state {
        case .idle where sourceIsEmpty:
            message = PaneMessage(symbol: "text.badge.checkmark", title: "Nothing to check",
                                  detail: "Paste text on the left. Corrections appear here.")
            statusSubtitle = "Paste or type text to check"
        case .idle:
            message = PaneMessage(symbol: "text.badge.checkmark", title: "Ready to check",
                                  detail: "Press ⌘↩ to check the spelling.", actionTitle: "Check Spelling",
                                  action: { [weak self] in self?.check() })
            statusSubtitle = "Not checked yet"
        case .missingKey:
            message = PaneMessage(symbol: "key", title: "Add your OpenRouter API key",
                                  detail: "Corrector sends text to OpenRouter to check it.", actionTitle: "Open Settings…",
                                  action: { SettingsWindowController.shared.show(focusingAPIKey: true) })
            statusSubtitle = "OpenRouter API key needed"
        case .checking(let model):
            let name = model.map { ModelCatalog.displayName(for: $0) }
            message = PaneMessage(symbol: "text.badge.checkmark", title: "Checking spelling…",
                                  detail: name.map { "Using \($0)" } ?? "Choosing the fastest model…", showsProgress: true)
            statusSubtitle = name.map { "Checking with \($0)…" } ?? "Checking…"
        case .done(let correction):
            detail = correction.changes.isEmpty ? "No corrections" : Correction.count(correction.changes.count, "correction")
            symbol = "checkmark.circle.fill"
            tint = .systemGreen
            statusSubtitle = correction.summary
        case .stale:
            detail = "Out of date"
            symbol = "arrow.clockwise"
            statusSubtitle = "Text changed — press ⌘↩ to check again"
        case .failed(let error):
            message = PaneMessage(symbol: "exclamationmark.triangle", title: "Couldn’t check spelling", detail: error,
                                  actionTitle: "Try Again", action: { [weak self] in self?.check() })
            statusSubtitle = "Check failed"
        }

        resultPane.message = message
        resultPane.detailText = detail
        resultPane.detailSymbol = symbol
        resultPane.detailTint = tint
        resultPane.isBusy = { if case .checking = state { true } else { false } }()
        resultPane.isDimmed = state.isStale
        showResult(state.correction)
        if case .done(let correction) = state {
            sourceView.setHighlights(correction.changes.map(\.sourceRange), style: .misspelling)
        } else {
            sourceView.clearHighlights()
        }
        window?.subtitle = statusSubtitle
        window?.toolbar?.validateVisibleItems()
    }

    private func showResult(_ correction: Correction?) {
        let text = correction?.display
        if text !== shownResult {
            shownResult = text
            resultView.textStorage?.setAttributedString(text ?? NSAttributedString())
        }
        if let correction {
            resultView.setHighlights(correction.displayHighlights, style: .correction)
        } else {
            resultView.clearHighlights()
        }
    }

    /// Shows a short confirmation in the subtitle, then returns to the status.
    private func flash(_ text: String) {
        flashTask?.cancel()
        window?.subtitle = text
        flashTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            window?.subtitle = statusSubtitle
        }
    }

    private func updateWordCount() {
        let text = sourceView.string
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in
            count += 1
        }
        sourcePane.detailText = count == 0 ? "" : Correction.count(count, "word")
    }

    private func applyZoom(_ zoom: CGFloat) {
        sourcePane.zoom = zoom
        resultPane.zoom = zoom
    }

    private func setZoom(_ zoom: CGFloat) {
        Preferences.textZoom = zoom
        applyZoom(Preferences.textZoom)
    }

    // MARK: - Actions

    @objc func checkText(_ sender: Any?) {
        check()
    }

    @objc func copyCorrectedText(_ sender: Any?) {
        guard case .done(let correction) = state else { return }
        let board = NSPasteboard.general
        board.clearContents()
        let copied = correction.copiesRichText
            ? board.writeObjects([correction.display])
            : board.setString(correction.display.string, forType: .string)
        guard copied else {
            NSSound.beep()
            flash("Couldn’t copy the text")
            return
        }
        if Preferences.hidesAfterCopy {
            NSApp.hide(nil)
        } else {
            flash("Copied to clipboard")
        }
    }

    @objc func applyCorrections(_ sender: Any?) {
        guard case .done(var correction) = state, !correction.changes.isEmpty,
              let storage = sourceView.textStorage else { return }
        let everything = NSRange(location: 0, length: storage.length)
        guard sourceView.shouldChangeText(in: everything, replacementString: correction.text.string) else { return }
        let selection = sourceView.selectedRange()
        let scrollOrigin = sourcePane.scrollView.contentView.bounds.origin
        isApplyingCorrections = true
        storage.replaceCharacters(in: everything, with: correction.text)
        sourceView.didChangeText()
        isApplyingCorrections = false
        sourceView.undoManager?.setActionName("Apply Corrections")
        sourceView.setSelectedRange(NSRange(location: min(selection.location, storage.length), length: 0))
        sourcePane.scrollView.contentView.scroll(to: scrollOrigin)
        sourcePane.scrollView.reflectScrolledClipView(sourcePane.scrollView.contentView)

        correction.markApplied(source: NSAttributedString(attributedString: storage), format: Preferences.format)
        state = .done(correction)
        flash("Corrections applied")
    }

    @objc func newDocument(_ sender: Any?) {
        if let storage = sourceView.textStorage, storage.length > 0 {
            let everything = NSRange(location: 0, length: storage.length)
            if sourceView.shouldChangeText(in: everything, replacementString: "") {
                storage.replaceCharacters(in: everything, with: "")
                sourceView.didChangeText()
                sourceView.undoManager?.setActionName("Clear")
            }
        }
        sourceView.typingAttributes = defaultTypingAttributes
        sourceWasRichText = false
        checkTask?.cancel()
        typingCheck?.cancel()
        revision += 1
        state = restingState
        window?.makeFirstResponder(sourceView)
    }

    @objc func chooseModel(_ sender: NSMenuItem) {
        Preferences.selectedModel = sender.representedObject as? String
        preferencesDidChange()
    }

    @objc func chooseOtherModel(_ sender: Any?) {
        guard let window, window.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.messageText = "Use Another Model"
        alert.informativeText = "Enter an OpenRouter model ID, for example provider/model-name."
        alert.addButton(withTitle: "Use Model")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: Preferences.customModel ?? "")
        field.placeholderString = "provider/model-name"
        field.frame = NSRect(x: 0, y: 0, width: 300, height: 22)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            let model = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !model.isEmpty else { return }
            if !ModelCatalog.presets.contains(where: { $0.id == model }) { Preferences.customModel = model }
            Preferences.selectedModel = model
            self?.preferencesDidChange()
        }
    }

    @objc func chooseFormat(_ sender: NSMenuItem) {
        Preferences.format = CorrectionFormat(rawValue: sender.tag) ?? .detect
        preferencesDidChange()
    }

    @objc func toggleChecksAfterPaste(_ sender: Any?) {
        Preferences.checksAfterPaste.toggle()
    }

    @objc func toggleChecksWhileTyping(_ sender: Any?) {
        Preferences.checksWhileTyping.toggle()
        preferencesDidChange()
    }

    @objc func zoomIn(_ sender: Any?) {
        let zoom = sourcePane.zoom
        if let next = Self.zoomLevels.first(where: { $0 > zoom + 0.01 }) { setZoom(next) }
    }

    @objc func zoomOut(_ sender: Any?) {
        let zoom = sourcePane.zoom
        if let previous = Self.zoomLevels.last(where: { $0 < zoom - 0.01 }) { setZoom(previous) }
    }

    @objc func zoomToActualSize(_ sender: Any?) {
        setZoom(1)
    }

    @objc func focusOriginal(_ sender: Any?) {
        window?.makeFirstResponder(sourceView)
    }

    @objc func focusCorrected(_ sender: Any?) {
        window?.makeFirstResponder(resultView)
    }

    @objc private func modelPopupDidChange(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem else { return }
        if item.tag == MainMenu.otherModelTag {
            syncWithPreferences()
            chooseOtherModel(sender)
        } else {
            chooseModel(item)
        }
    }

    @objc private func formatPopupDidChange(_ sender: NSPopUpButton) {
        if let item = sender.selectedItem { chooseFormat(item) }
    }

    private func canPerform(_ action: Selector?) -> Bool {
        guard let action else { return true }
        let zoom = sourcePane.zoom
        switch action {
        case #selector(checkText(_:)), #selector(checkSpelling(_:)):
            return !sourceView.string.isEmpty
        case #selector(copyCorrectedText(_:)):
            return state.isDone
        case #selector(applyCorrections(_:)):
            return state.isDone && state.correction?.changes.isEmpty == false
        case #selector(focusCorrected(_:)):
            return state.correction != nil
        case #selector(chooseOtherModel(_:)):
            return window?.attachedSheet == nil
        case #selector(zoomIn(_:)):
            return Self.zoomLevels.contains { $0 > zoom + 0.01 }
        case #selector(zoomOut(_:)):
            return Self.zoomLevels.contains { $0 < zoom - 0.01 }
        case #selector(zoomToActualSize(_:)):
            return abs(zoom - 1) > 0.01
        default:
            return true
        }
    }
}

// MARK: - Validation

extension MainWindowController: NSMenuItemValidation, NSToolbarItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(chooseModel(_:))?:
            item.state = item.representedObject as? String == Preferences.selectedModel ? .on : .off
        case #selector(chooseFormat(_:))?:
            item.state = item.tag == Preferences.format.rawValue ? .on : .off
        case #selector(toggleChecksAfterPaste(_:))?:
            item.state = Preferences.checksAfterPaste ? .on : .off
        case #selector(toggleChecksWhileTyping(_:))?:
            item.state = Preferences.checksWhileTyping ? .on : .off
        default:
            break
        }
        return canPerform(item.action)
    }

    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        canPerform(item.action)
    }
}

// MARK: - Toolbar

extension MainWindowController: NSToolbarDelegate {
    private enum ToolbarID {
        static let model = NSToolbarItem.Identifier("model")
        static let format = NSToolbarItem.Identifier("format")
        static let check = NSToolbarItem.Identifier("check")
        static let copy = NSToolbarItem.Identifier("copy")
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.flexibleSpace, ToolbarID.model, ToolbarID.format, .space, ToolbarID.check, ToolbarID.copy]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch identifier {
        case ToolbarID.model:
            return popupItem(identifier, label: "Model", popup: modelPopup)
        case ToolbarID.format:
            return popupItem(identifier, label: "Format", popup: formatPopup)
        case ToolbarID.check:
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.label = "Check"
            item.toolTip = "Check Spelling (⌘↩)"
            item.image = NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: "Check Spelling")
            item.isBordered = true
            item.target = self
            item.action = #selector(checkText(_:))
            item.visibilityPriority = .high
            return item
        case ToolbarID.copy:
            let button = NSButton(title: "Copy",
                                  image: NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil) ?? NSImage(),
                                  target: self, action: #selector(copyCorrectedText(_:)))
            button.bezelStyle = .toolbar
            button.translatesAutoresizingMaskIntoConstraints = false
            button.imagePosition = .imageLeading
            button.contentTintColor = .controlAccentColor
            button.toolTip = "Copy Corrected Text (⇧⌘C)"
            let item = ValidatedToolbarItem(itemIdentifier: identifier)
            item.view = button
            item.label = "Copy"
            item.toolTip = button.toolTip
            item.visibilityPriority = .high
            item.isValid = { [weak self] in self?.canPerform(#selector(MainWindowController.copyCorrectedText(_:))) ?? false }
            return item
        default:
            return nil
        }
    }

    private func popupItem(_ identifier: NSToolbarItem.Identifier, label: String, popup: NSPopUpButton) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.paletteLabel = label
        item.toolTip = label
        item.view = popup
        return item
    }
}

// MARK: - Split view

extension MainWindowController: NSSplitViewDelegate {
    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat,
                   ofSubviewAt dividerIndex: Int) -> CGFloat {
        proposedMinimumPosition + 240
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat,
                   ofSubviewAt dividerIndex: Int) -> CGFloat {
        proposedMaximumPosition - 240
    }
}

private final class MainPanel: NSPanel {
    // Panels cannot become main by default; being main keeps the window's menu items working while Settings is key.
    override var canBecomeMain: Bool { true }

    // Hiding the app, not just the panel, returns focus to the app the text came from.
    override func cancelOperation(_ sender: Any?) {
        NSApp.hide(nil)
    }

    // The original utility panel reported this subrole, which is what makes AeroSpace float the window.
    override func accessibilitySubrole() -> NSAccessibility.Subrole? {
        .floatingWindow
    }
}

/// Validates a toolbar item that hosts a custom control, which AppKit does not do on its own.
private final class ValidatedToolbarItem: NSToolbarItem {
    var isValid: () -> Bool = { true }

    override func validate() {
        let valid = isValid()
        isEnabled = valid
        (view as? NSControl)?.isEnabled = valid
    }
}
