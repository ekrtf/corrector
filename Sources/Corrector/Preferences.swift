import AppKit

enum CorrectionFormat: Int, CaseIterable {
    case detect, plain, markdown, rich

    var title: String {
        switch self {
        case .detect: return "Detect Format"
        case .plain: return "Plain Text"
        case .markdown: return "Markdown"
        case .rich: return "Rich Text"
        }
    }
}

struct ModelOption: Equatable {
    let title: String
    /// The OpenRouter model ID, or nil for automatic selection.
    let id: String?
}

enum ModelCatalog {
    static let automatic = ModelOption(title: "Automatic (Fastest)", id: nil)
    static let presets: [ModelOption] = [
        ModelOption(title: "DeepSeek V4.1 Flash", id: "deepseek/deepseek-v4.1-flash"),
        ModelOption(title: "Mistral Small", id: "mistralai/mistral-small-2603"),
        ModelOption(title: "Gemini 3.5 Flash Lite", id: "google/gemini-3.5-flash-lite"),
        ModelOption(title: "GPT-6 Luna", id: "openai/gpt-6-luna")
    ]

    /// A readable name for a model ID, or the ID itself for models outside the presets.
    static func displayName(for id: String) -> String {
        presets.first { $0.id == id }?.title ?? id
    }
}

extension Notification.Name {
    /// Posted after the OpenRouter API key is saved or removed.
    static let apiKeyDidChange = Notification.Name("CorrectorAPIKeyDidChange")
}

/// User settings stored in UserDefaults. The keys `selectedModel` and
/// `customModel` predate this type and keep their original meaning.
enum Preferences {
    private static var defaults: UserDefaults { .standard }

    /// The chosen model ID, or nil for automatic selection.
    static var selectedModel: String? {
        get { nonEmpty(defaults.string(forKey: "selectedModel")) }
        set { defaults.set(nonEmpty(newValue), forKey: "selectedModel") }
    }

    /// A model ID entered by the user that is not one of the presets.
    static var customModel: String? {
        get { nonEmpty(defaults.string(forKey: "customModel")) }
        set { defaults.set(nonEmpty(newValue), forKey: "customModel") }
    }

    static var format: CorrectionFormat {
        get { CorrectionFormat(rawValue: defaults.integer(forKey: "format")) ?? .detect }
        set { defaults.set(newValue.rawValue, forKey: "format") }
    }

    static var checksAfterPaste: Bool {
        get { defaults.object(forKey: "checksAfterPaste") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "checksAfterPaste") }
    }

    static var checksWhileTyping: Bool {
        get { defaults.bool(forKey: "checksWhileTyping") }
        set { defaults.set(newValue, forKey: "checksWhileTyping") }
    }

    static var hidesAfterCopy: Bool {
        get { defaults.bool(forKey: "hidesAfterCopy") }
        set { defaults.set(newValue, forKey: "hidesAfterCopy") }
    }

    static let textZoomRange: ClosedRange<CGFloat> = 0.75...2.5

    static var textZoom: CGFloat {
        get {
            let value = defaults.double(forKey: "textZoom")
            return value == 0 ? 1 : min(max(CGFloat(value), textZoomRange.lowerBound), textZoomRange.upperBound)
        }
        set { defaults.set(Double(min(max(newValue, textZoomRange.lowerBound), textZoomRange.upperBound)), forKey: "textZoom") }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}
