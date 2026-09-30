import SwiftUI

/// API key state for the Settings window. Keychain access is injected so previews never touch it.
@MainActor
final class SettingsModel: ObservableObject {
    @Published var draftKey = "" {
        didSet { if draftKey != oldValue { keyError = nil } }
    }
    @Published private(set) var hasKey = false
    @Published private(set) var keyError: String?
    @Published private(set) var keyFocusRequest = 0

    private let keyExists: () -> Bool
    private let storeKey: (String) -> Bool
    private let deleteKey: () -> Bool

    init(hasKey: @escaping () -> Bool = { KeychainStore.readKey() != nil },
         save: @escaping (String) -> Bool = { KeychainStore.saveKey($0) },
         delete: @escaping () -> Bool = { KeychainStore.deleteKey() }) {
        keyExists = hasKey
        storeKey = save
        deleteKey = delete
    }

    var canSaveKey: Bool { !trimmedDraft.isEmpty }

    /// Reloads the key state and forgets anything typed while the window was last open.
    func reload() {
        draftKey = ""
        keyError = nil
        hasKey = keyExists()
    }

    func requestKeyFocus() {
        keyFocusRequest += 1
    }

    func saveKey() {
        let key = trimmedDraft
        guard !key.isEmpty else { return }
        guard storeKey(key) else {
            keyError = "Couldn’t save the key in the Keychain."
            return
        }
        draftKey = ""
        keyError = nil
        hasKey = true
        NotificationCenter.default.post(name: .apiKeyDidChange, object: nil)
    }

    func removeKey() {
        guard deleteKey() else {
            keyError = "Couldn’t remove the key from the Keychain."
            return
        }
        keyError = nil
        hasKey = false
        NotificationCenter.default.post(name: .apiKeyDidChange, object: nil)
    }

    private var trimmedDraft: String {
        draftKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// The Settings form. Model and behavior settings use the same UserDefaults keys as `Preferences`,
/// so the main window picks up changes through `UserDefaults.didChangeNotification` and vice versa.
struct SettingsView: View {
    @ObservedObject var settings: SettingsModel

    @AppStorage("selectedModel") private var selectedModel: String?
    @AppStorage("customModel") private var customModel: String?
    @AppStorage("checksAfterPaste") private var checksAfterPaste = true
    @AppStorage("checksWhileTyping") private var checksWhileTyping = false
    @AppStorage("hidesAfterCopy") private var hidesAfterCopy = false

    @State private var customDraft = ""
    @FocusState private var keyFieldFocused: Bool

    var body: some View {
        Form {
            keySection
            modelSection
            behaviorSection
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: settings.keyFocusRequest, initial: true) {
            if settings.keyFocusRequest > 0 { keyFieldFocused = true }
        }
        .onChange(of: customModel, initial: true) {
            customDraft = customModel ?? ""
        }
    }

    private var keySection: some View {
        Section {
            LabeledContent("API key") {
                HStack {
                    SecureField("API key", text: $settings.draftKey,
                                prompt: Text(settings.hasKey ? "Paste a new key" : "sk-or-v1-…"))
                        .labelsHidden()
                        .focused($keyFieldFocused)
                        .onSubmit(settings.saveKey)
                    Button("Save", action: settings.saveKey)
                        .disabled(!settings.canSaveKey)
                }
            }
            LabeledContent {
                if settings.hasKey && settings.keyError == nil {
                    Button("Remove", action: settings.removeKey)
                }
            } label: {
                keyStatus
            }
            // Same height with or without the Remove button, so the window never resizes.
            .frame(minHeight: 22)
        } header: {
            Text("OpenRouter")
        } footer: {
            footnote {
                Text("Text you check is sent to OpenRouter. Corrector does not keep a history.")
                    .foregroundStyle(.secondary)
                Link("Get an API key", destination: URL(string: "https://openrouter.ai/keys")!)
            }
        }
    }

    @ViewBuilder
    private var keyStatus: some View {
        if let error = settings.keyError {
            Label {
                Text(error)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }
        } else if settings.hasKey {
            Label {
                Text("Saved in Keychain")
            } icon: {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
            }
        } else {
            Label("Add a key to start checking spelling.", systemImage: "key.fill")
                .foregroundStyle(.secondary)
        }
    }

    private var modelSection: some View {
        Section {
            Picker("Model", selection: modelSelection) {
                Text(ModelCatalog.automatic.title).tag(String?.none)
                Divider()
                ForEach(ModelCatalog.presets, id: \.id) { option in
                    Text(option.title).tag(option.id)
                }
                if !extraModels.isEmpty {
                    Divider()
                    ForEach(extraModels, id: \.self) { id in
                        Text(id).tag(Optional(id))
                    }
                }
            }
            .pickerStyle(.menu)

            TextField("Custom model ID", text: $customDraft, prompt: Text("provider/model-name"))
                .autocorrectionDisabled()
                .onSubmit(useCustomModel)
        } footer: {
            footnote {
                Text("Automatic picks the fastest of a curated list of models, refreshed every 30 minutes. Enter any OpenRouter model ID and press Return to use it.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var behaviorSection: some View {
        Section("Behavior") {
            Toggle("Check spelling after pasting", isOn: $checksAfterPaste)
            Toggle("Check again when I stop typing", isOn: $checksWhileTyping)
            Toggle("Hide Corrector after copying", isOn: $hidesAfterCopy)
        }
    }

    // Grouped-form footers default to trailing alignment, which reads oddly for sentences.
    // The padding lines the text up with the row labels above it.
    private func footnote(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) { content() }
            .font(.footnote)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
    }

    /// Mirrors `Preferences.selectedModel`: automatic removes the key instead of storing an empty ID.
    private var modelSelection: Binding<String?> {
        Binding(get: { nonEmpty(selectedModel) }, set: { selectedModel = nonEmpty($0) })
    }

    /// The custom model, plus a selected ID that is neither a preset nor the custom model,
    /// so the picker never shows a blank selection.
    private var extraModels: [String] {
        var ids: [String] = []
        for id in [nonEmpty(customModel), nonEmpty(selectedModel)].compactMap({ $0 })
        where !ids.contains(id) && !ModelCatalog.presets.contains(where: { $0.id == id }) {
            ids.append(id)
        }
        return ids
    }

    private func useCustomModel() {
        let previous = nonEmpty(customModel)
        guard let id = nonEmpty(customDraft) else {
            customModel = nil
            if let previous, nonEmpty(selectedModel) == previous,
               !ModelCatalog.presets.contains(where: { $0.id == previous }) {
                selectedModel = nil
            }
            return
        }
        customModel = id
        selectedModel = id
        customDraft = id
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }
}
