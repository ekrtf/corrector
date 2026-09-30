import AppKit

extension MainWindowController {
    /// Where the check of the original text stands. The corrected pane, the window subtitle,
    /// and the menus are all derived from this value.
    enum State {
        /// No result for the current text, which may be empty.
        case idle
        case missingKey
        /// The model is nil while the automatic model is being chosen.
        case checking(model: String?)
        case done(Correction)
        /// The original changed after the check; the old result stays visible but dimmed.
        case stale(Correction)
        case failed(String)

        var name: String {
            switch self {
            case .idle: "idle"
            case .missingKey: "missingKey"
            case .checking: "checking"
            case .done: "done"
            case .stale: "stale"
            case .failed: "failed"
            }
        }

        var correction: Correction? {
            switch self {
            case .done(let correction), .stale(let correction): correction
            default: nil
            }
        }

        var isDone: Bool {
            if case .done = self { true } else { false }
        }

        var isStale: Bool {
            if case .stale = self { true } else { false }
        }
    }

    struct Correction {
        /// The original text as it was when it was checked.
        private(set) var source: NSAttributedString
        let sourceWasRich: Bool
        /// The original with corrected words, keeping the original attributes.
        let text: NSAttributedString
        private(set) var changes: [WordChange]
        let model: String
        let duration: TimeInterval
        /// What the corrected pane shows and what Copy writes.
        private(set) var display = NSAttributedString()
        private(set) var displayHighlights: [NSRange] = []
        private(set) var copiesRichText = false

        init(source: NSAttributedString, sourceWasRich: Bool, outcome: CorrectionOutcome,
             model: String, duration: TimeInterval, format: CorrectionFormat) {
            self.source = source
            self.sourceWasRich = sourceWasRich
            text = outcome.text
            changes = outcome.changes
            self.model = model
            self.duration = duration
            present(as: format)
        }

        mutating func present(as format: CorrectionFormat) {
            let markdown: Bool
            switch format {
            case .plain, .rich: markdown = false
            case .markdown: markdown = true
            case .detect: markdown = !sourceWasRich && MarkdownRenderer.looksLikeMarkdown(source.string)
            }
            let ranges = changes.map(\.resultRange)
            if markdown, let rendered = MarkdownRenderer.render(text.string, marking: ranges) {
                (display, displayHighlights, copiesRichText) = (rendered.text, rendered.marked, true)
            } else {
                // Plain sources are copied as plain strings so the display font never reaches the clipboard.
                (display, displayHighlights, copiesRichText) = (text, ranges, sourceWasRich && format != .plain)
            }
        }

        /// The corrections now live in the original, so this result has nothing left to change.
        mutating func markApplied(source: NSAttributedString, format: CorrectionFormat) {
            self.source = source
            changes = []
            present(as: format)
        }

        /// The pane header already shows the count, so the subtitle says how the check ran.
        var summary: String {
            let seconds = duration.formatted(.number.precision(.fractionLength(1)))
            return "Checked with \(ModelCatalog.displayName(for: model)) in \(seconds) s"
        }

        static func count(_ value: Int, _ noun: String) -> String {
            value == 1 ? "1 \(noun)" : "\(value.formatted()) \(noun)s"
        }
    }
}
