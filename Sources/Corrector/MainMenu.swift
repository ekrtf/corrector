import AppKit

@MainActor
enum MainMenu {
    /// Tags the "Other Model…" item in model menus and the toolbar pop-up.
    static let otherModelTag = 1

    private static let modelMenuDelegate = ModelMenuDelegate()

    static func install() {
        let services = NSMenu(title: "Services")
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        servicesItem.submenu = services

        let app = submenu("Corrector", [
            item("About Corrector", #selector(AppDelegate.showAbout(_:))),
            .separator(),
            item("Settings…", #selector(AppDelegate.showSettings(_:)), ","),
            .separator(),
            servicesItem,
            .separator(),
            item("Hide Corrector", #selector(NSApplication.hide(_:)), "h"),
            item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("Show All", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item("Quit Corrector", #selector(NSApplication.terminate(_:)), "q")
        ])

        let file = submenu("File", [
            item("New", #selector(MainWindowController.newDocument(_:)), "n"),
            .separator(),
            item("Close", #selector(NSWindow.performClose(_:)), "w")
        ])

        let edit = submenu("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "Z"),
            .separator(),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Paste and Match Style", #selector(NSTextView.pasteAsPlainText(_:)), "V", [.command, .option]),
            item("Delete", #selector(NSText.delete(_:))),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            item("Copy Corrected Text", #selector(MainWindowController.copyCorrectedText(_:)), "C"),
            .separator(),
            submenu("Find", [
                findItem("Find…", .showFindInterface, "f"),
                findItem("Find Next", .nextMatch, "g"),
                findItem("Find Previous", .previousMatch, "G"),
                findItem("Use Selection for Find", .setSearchString, "e")
            ])
        ])

        let models = submenu("Model", [])
        models.submenu?.delegate = modelMenuDelegate
        let correction = submenu("Correction", [
            item("Check Spelling", #selector(MainWindowController.checkText(_:)), "\r"),
            item("Apply Corrections to Original", #selector(MainWindowController.applyCorrections(_:)), "\r",
                 [.command, .option]),
            .separator(),
            models,
            submenu("Format", CorrectionFormat.allCases.flatMap { format -> [NSMenuItem] in
                let formatItem = item(format.title, #selector(MainWindowController.chooseFormat(_:)))
                formatItem.tag = format.rawValue
                return format == .detect ? [formatItem, .separator()] : [formatItem]
            }),
            .separator(),
            item("Check After Paste", #selector(MainWindowController.toggleChecksAfterPaste(_:))),
            item("Check While Typing", #selector(MainWindowController.toggleChecksWhileTyping(_:)))
        ])

        // ⌘= reaches Zoom In without Shift on layouts where + needs it.
        let zoomInAlias = item("Zoom In", #selector(MainWindowController.zoomIn(_:)), "=")
        zoomInAlias.isHidden = true
        zoomInAlias.allowsKeyEquivalentWhenHidden = true
        let view = submenu("View", [
            item("Zoom In", #selector(MainWindowController.zoomIn(_:)), "+"),
            zoomInAlias,
            item("Zoom Out", #selector(MainWindowController.zoomOut(_:)), "-"),
            item("Actual Size", #selector(MainWindowController.zoomToActualSize(_:)), "0"),
            .separator(),
            item("Focus Original", #selector(MainWindowController.focusOriginal(_:)), "1"),
            item("Focus Corrected", #selector(MainWindowController.focusCorrected(_:)), "2"),
            .separator(),
            item("Show Toolbar", #selector(NSWindow.toggleToolbarShown(_:)), "t", [.command, .option])
        ])

        let window = submenu("Window", [
            item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("Zoom", #selector(NSWindow.performZoom(_:))),
            .separator(),
            item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:)))
        ])

        let mainMenu = NSMenu(title: "Main Menu")
        mainMenu.items = [app, file, edit, correction, view, window]
        NSApp.mainMenu = mainMenu
        NSApp.servicesMenu = services
        NSApp.windowsMenu = window.submenu
    }

    /// Model choices besides Automatic: the presets, then the custom and selected IDs when they are not presets.
    static func modelOptions() -> [ModelOption] {
        var options = ModelCatalog.presets
        for id in [Preferences.customModel, Preferences.selectedModel].compactMap({ $0 })
        where !options.contains(where: { $0.id == id }) {
            options.append(ModelOption(title: ModelCatalog.displayName(for: id), id: id))
        }
        return options
    }

    /// Fills a model menu. Each model item carries its ID (nil for Automatic) as its represented object.
    static func addModelItems(to menu: NSMenu, choose: Selector?, other: Selector?) {
        for (index, option) in ([ModelCatalog.automatic] + modelOptions()).enumerated() {
            let modelItem = NSMenuItem(title: option.title, action: choose, keyEquivalent: "")
            modelItem.representedObject = option.id
            menu.addItem(modelItem)
            if index == 0 { menu.addItem(.separator()) }
        }
        menu.addItem(.separator())
        let otherItem = NSMenuItem(title: "Other Model…", action: other, keyEquivalent: "")
        otherItem.tag = otherModelTag
        menu.addItem(otherItem)
    }

    private static func item(_ title: String, _ action: Selector?, _ key: String = "",
                             _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    private static func findItem(_ title: String, _ action: NSTextFinder.Action, _ key: String,
                                 _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = item(title, #selector(NSResponder.performTextFinderAction(_:)), key, modifiers)
        item.tag = action.rawValue
        return item
    }

    private static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let menu = NSMenu(title: title)
        menu.items = items
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}

/// Rebuilds Correction ▸ Model each time it opens, so custom models added elsewhere appear.
@MainActor
private final class ModelMenuDelegate: NSObject, NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        MainMenu.addModelItems(to: menu,
                               choose: #selector(MainWindowController.chooseModel(_:)),
                               other: #selector(MainWindowController.chooseOtherModel(_:)))
    }
}
