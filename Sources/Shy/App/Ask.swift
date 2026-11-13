import SwiftUI

/// The few questions a space's menu asks, as sheets on the window. The
/// bookmarks list borrows `name` for Rename….
@MainActor
enum Ask {
    /// A test run's answer to `sure`, in place of a sheet that a probe
    /// started hidden can't show (`ui confirm on|off`). Never set otherwise.
    @MainActor static var testing: Bool?

    /// `empty`: an empty name is an answer too (a bookmark's, see
    /// Bookmarks.askRename); otherwise it is taken as no answer.
    static func name(_ title: String, detail: String? = nil, placeholder: String, initial: String = "", confirm: String, empty: Bool = false, then: @escaping (String) -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        if let detail { alert.informativeText = detail }
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = placeholder
        field.stringValue = initial
        alert.accessoryView = field
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        show(alert) { ok in
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if ok, empty || !name.isEmpty { then(name) }
        }
    }

    /// A new space's name, and the profile it is in — for when the column
    /// isn't there to hold the card.
    @MainActor static func newSpace(in profile: UUID, then: @escaping (String, UUID) -> Void, cancelled: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = "New Space"
        alert.informativeText = "Its own tabs, signed in as its profile is."
        let field = NSTextField(frame: NSRect(x: 0, y: 30, width: 260, height: 24))
        field.placeholderString = "Work"
        let profiles = Profiles.shared.list
        let pick = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 260, height: 24), pullsDown: false)
        pick.addItems(withTitles: profiles.map(\.name))
        pick.selectItem(at: profiles.firstIndex { $0.id == profile } ?? 0)
        let box = NSView(frame: NSRect(x: 0, y: 0, width: 260, height: 58))
        box.addSubview(field)
        box.addSubview(pick)
        alert.accessoryView = box
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        show(alert) { ok in
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard ok, !name.isEmpty else { cancelled(); return }
            then(name, profiles[max(0, pick.indexOfSelectedItem)].id)
        }
    }

    /// `returnCancels`: Return is Cancel's, for a yes that can't be undone.
    static func sure(_ title: String, detail: String, confirm: String, returnCancels: Bool = false, then: @escaping () -> Void) {
        if Store.testing, let yes = testing {
            if yes { then() }
            return
        }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        let yes = alert.addButton(withTitle: confirm)
        yes.hasDestructiveAction = true
        let no = alert.addButton(withTitle: "Cancel")
        guard returnCancels else {
            show(alert) { ok in if ok { then() } }
            return
        }
        yes.keyEquivalent = ""
        no.keyEquivalent = "\r"
        // A button holds one key, and Cancel gave up Esc for Return: Esc is
        // caught here for it while the question is up.
        let escape = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.window === alert.window, event.keyCode == 53 else { return event }
            no.performClick(nil)
            return nil
        }
        show(alert) { ok in
            if let escape { NSEvent.removeMonitor(escape) }
            if ok { then() }
        }
    }

    static func folder(then: @escaping (URL?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use for This Space"
        panel.message = "Downloads in this space go here. Cancel keeps the folder it has."
        guard let window = Links.window else { return }
        panel.beginSheetModal(for: window) { answer in
            if answer == .OK, let url = panel.url { then(url) }
        }
    }

    private static func show(_ alert: NSAlert, _ done: @escaping (Bool) -> Void) {
        guard let window = Links.window else {
            done(alert.runModal() == .alertFirstButtonReturn)
            return
        }
        alert.beginSheetModal(for: window) { done($0 == .alertFirstButtonReturn) }
    }
}
