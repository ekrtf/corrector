import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private lazy var mainWindow = MainWindowController()

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Key equivalents (⌘Q, ⌘C, ⌘V…) only work once the menu exists, so install it before any window.
        MainMenu.install()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        mainWindow.showAndFocus()
        if !mainWindow.hasAPIKey { SettingsWindowController.shared.show(focusingAPIKey: true) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        mainWindow.showAndFocus()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    @objc func showSettings(_ sender: Any?) {
        SettingsWindowController.shared.show()
    }

    @objc func showAbout(_ sender: Any?) {
        NSApp.orderFrontStandardAboutPanel(sender)
        // The main panel floats, so the About panel has to float too or it opens behind it.
        for window in NSApp.windows where window.isVisible && window.level == .normal && window.sheetParent == nil {
            window.level = .floating
        }
    }
}
