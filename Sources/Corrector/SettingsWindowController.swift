import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private let settings: SettingsModel
    private var hasBeenShown = false

    convenience init() { self.init(settings: SettingsModel(), defaults: .standard) }

    init(settings: SettingsModel, defaults: UserDefaults) {
        self.settings = settings
        let hosting = NSHostingController(rootView: SettingsView(settings: settings).defaultAppStorage(defaults))
        hosting.sizingOptions = [.preferredContentSize]
        let window = NSWindow(contentViewController: hosting)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.title = "Corrector Settings"
        // The main panel floats; a normal-level window would open behind it.
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func show(focusingAPIKey: Bool = false) {
        guard let window else { return }
        if !window.isVisible { settings.reload() }
        if !hasBeenShown {
            window.center()
            hasBeenShown = true
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if focusingAPIKey { settings.requestKeyFocus() }
    }
}
