import AppKit
import WebKit

// The window around the page: its tabs, their groups, and the side panel.
// Part of the Chrome APIs Shy answers itself (ExtensionShims.answer); each case
// is one call, and a call this part does not know is left for the others.

@available(macOS 15.4, *)
@MainActor
extension ExtensionShims {
    static func runTabs(_ api: String, _ args: [Any], _ context: WKWebExtensionContext, _ owner: Extensions, _ browser: Browser) async throws -> Any? {
        let first = args.first
        let id = context.uniqueIdentifier
        switch api {
        // MARK: side panel — the window's, beside the page (SidePanel.swift)
        case "sidePanel.setOptions":
            let options = first as? [String: Any] ?? [:]
            if let tab = options["tabId"] as? Int {
                var kept = panelTabs[id]?[tab] ?? (nil, nil)
                if let path = options["path"] as? String { kept.path = path }
                if let enabled = options["enabled"] as? Bool { kept.enabled = enabled }
                panelTabs[id, default: [:]][tab] = kept
            } else {
                if let path = options["path"] as? String { panelPath[id] = path }
                if let enabled = options["enabled"] as? Bool {
                    if enabled { panelOff.remove(id) } else { panelOff.insert(id) }
                }
            }
            // Turned off while it is up: it goes, as in Chrome.
            if options["enabled"] as? Bool == false {
                for browser in Browsers.all {
                    if case .page(let shown, _, _) = browser.sidePanel, shown == id { browser.closeSidePanel() }
                }
            }
            return nil
        case "sidePanel.getOptions":
            let tab = (first as? [String: Any])?["tabId"] as? Int
            let own = tab.flatMap { panelTabs[id]?[$0] }
            return ["enabled": own?.enabled ?? !panelOff.contains(id),
                    "path": own?.path ?? panelPath[id] ?? defaultPanel(context) ?? ""]
        case "sidePanel.setPanelBehavior":
            if let on = (first as? [String: Any])?["openPanelOnActionClick"] as? Bool {
                if on { panelOnClick.insert(id) } else { panelOnClick.remove(id) }
            }
            return nil
        case "sidePanel.getPanelBehavior":
            return ["openPanelOnActionClick": panelOnClick.contains(id)]
        case "sidePanel.open":
            // For a tab, its own page when it was given one, and the panel
            // goes with that tab; otherwise the window's.
            let tab = (first as? [String: Any])?["tabId"] as? Int
            let own = tab.flatMap { panelTabs[id]?[$0] }
            guard own?.enabled ?? !panelOff.contains(id),
                  let path = own?.path ?? panelPath[id] ?? defaultPanel(context),
                  let url = ExtensionShims.page(path, in: context), let browser = owner.browser
            else { throw Unsupported(what: "No active side panel for this extension") }
            // The panel, or, if it can't be made, the page as a tab of its
            // own, as before there was a panel to put it in. Beside a
            // private tab it may not see, nothing opens at all.
            if browser.showSidePanel(context, url: url, for: own?.path != nil ? browser.activeID : nil) == .noPanel {
                browser.open(url, foreground: true)
            }
            return nil
        case "sidePanel.close":
            for browser in Browsers.all {
                if case .page(let shown, _, _) = browser.sidePanel, shown == id { browser.closeSidePanel() }
            }
            return nil

        // MARK: tabs, by where they are in the row
        case "tabs.describe":
            let places: [Any] = first as? [Any] ?? []
            return places.map { place -> Any in
                guard let tab = located(place, context: context, owner: owner) else { return NSNull() }
                // Another extension's page stays blank, as WebKit keeps it
                // (see the refusal in Extensions.load); its own are its own.
                if let url = tab.address, let scheme = url.scheme?.lowercased(),
                   [Extensions.scheme, Extensions.formerScheme].contains(scheme), url.host() != id {
                    return ["url": "", "title": ""]
                }
                var described: [String: Any] = ["url": tab.address?.absoluteString ?? "", "title": tab.title]
                if let icon = favIconURL(tab) { described["favIconUrl"] = icon }
                return described
            }
        // Which of these places hold a private tab, for the shim's incognito
        // (`privacy` in the script); with no places, whether this extension
        // sees any. Only tabs it sees are found, so one not let in learns
        // nothing.
        case "tabs.private":
            guard let places = first as? [Any] else {
                return Browsers.all.contains { $0.tabs.contains { $0.shy && owner.seen($0, for: context) } }
            }
            return places.map { located($0, context: context, owner: owner)?.shy == true }
        case "tabs.move", "tabs.discard", "tabs.activate":
            guard let tab = located(first, context: context, owner: owner), let browser = owner.browser(of: tab) else { throw Unsupported(what: "No tab there") }
            let visible = owner.visibleTabs(of: browser, for: context)
            switch api {
            case "tabs.move":
                let wanted = args.dropFirst().first as? Int ?? -1
                let target = visible[wanted < 0 || wanted >= visible.count ? visible.count - 1 : wanted]
                if let index = browser.tabs.firstIndex(where: { $0.id == target.id }) { browser.move(tab, to: index) }
            case "tabs.discard":
                if tab.id != browser.activeID { browser.sleep(tab) }
            default:
                browser.activateForExtension(tab)
            }
            return nil

        // MARK: tab groups
        // A tab group is a folder (see Folders.swift): one an extension
        // makes is a folder at the top of the space's, its tabs pinned rows
        // in it, kept as any folder's are; a folder you made is a group to
        // the extension, under its number. Claude in Chrome works only in a
        // group of its own: a refusal here left it unable to act on any
        // tab. A folder with no tab of its own is never shown, and one the
        // extension's calls leave empty goes, as Chrome's empty groups do.
        // A folder in a folder is a group like any other: Chrome's groups
        // don't nest, and the extension is told nothing of where it is.
        case "tabs.groups":
            let places: [Any] = first as? [Any] ?? []
            return places.map { place -> Int in
                guard let tab = located(place, context: context, owner: owner),
                      let home = owner.browser(of: tab), let folder = home.folder(of: tab) else { return -1 }
                return Folder.number(folder.id)
            }
        case "tabGroups.query":
            let spec = first as? [String: Any] ?? [:]
            return listedGroups(browser).filter { group in
                (spec["title"] as? String).map { $0 == group.name } ?? true
                    && (spec["collapsed"] as? Bool).map { $0 == group.folded } ?? true
                    && (spec["color"] as? String).map { $0 == "grey" } ?? true
            }.map(chromeGroup)
        case "tabGroups.get":
            return chromeGroup(try listedGroup(first, in: browser))
        case "tabGroups.update":
            let group = try listedGroup(first, in: browser)
            let props = args.dropFirst().first as? [String: Any] ?? [:]
            if let title = props["title"] as? String { browser.renameFolder(group.id, to: title) }
            if let collapsed = props["collapsed"] as? Bool { browser.setFolded(group.id, collapsed) }
            return chromeGroup(browser.folders.first { $0.id == group.id } ?? group)
        case "tabGroups.move":
            // A folder's place is among the folders, above the line, not at
            // a tab's index in the row: it stays where it is, and the call,
            // which in Chrome only rearranges, succeeds.
            return chromeGroup(try listedGroup(first, in: browser))
        case "tabs.group":
            let places: [Any] = first as? [Any] ?? []
            let tabs = places.compactMap { located($0, context: context, owner: owner) }
            guard !tabs.isEmpty else { throw Unsupported(what: "No tabs to group") }
            // A group is one window's, as in Chrome.
            guard let browser = owner.browser(of: tabs[0]), tabs.allSatisfy({ owner.browser(of: $0) === browser }) else {
                throw Unsupported(what: "Tabs from different windows can't share a group")
            }
            // Private tabs are never in a folder, nor a pin every space shows.
            guard tabs.allSatisfy({ browser.filable($0) }) else {
                throw Unsupported(what: "Private tabs, and pins in every space, can't be grouped")
            }
            let target: UUID
            if let number = args.dropFirst().first as? Int, number != -1 {
                target = try listedGroup(number, in: browser).id
            } else {
                // A new folder at the top, as its menu makes one, without
                // its name to type: the extension names it, if it likes.
                guard let made = browser.newFolder(editing: false) else { throw Unsupported(what: "No group made") }
                target = made
            }
            let left = Set(tabs.compactMap(\.folder)).subtracting([target])
            for tab in tabs { browser.move(tab, toFolder: target) }
            browser.dropIfEmpty(left)
            return Folder.number(target)
        case "tabs.ungroup":
            // Out of its folder and unpinned: the ordinary tab it was
            // before it was grouped, as Chrome leaves it.
            let places: [Any] = first as? [Any] ?? []
            for tab in places.compactMap({ located($0, context: context, owner: owner) }) {
                guard let browser = owner.browser(of: tab), let folder = browser.folder(of: tab) else { continue }
                browser.unpin(tab)
                browser.dropIfEmpty([folder.id])
            }
            return nil

        default:
            return Unhandled()
        }
    }
    /// The tab groups an extension is shown: the folders with a tab of their
    /// own in them, never an empty one, as Chrome has no group without a
    /// tab (see the tab groups cases in `run`).
    static func listedGroups(_ browser: Browser) -> [Folder] {
        let filed = Set(browser.tabs.compactMap { $0.pin == nil ? nil : $0.folder })
        return browser.folders.filter { filed.contains($0.id) }
    }

    static func listedGroup(_ number: Any?, in browser: Browser) throws -> Folder {
        guard let number = number as? Int,
              let folder = listedGroups(browser).first(where: { Folder.number($0.id) == number })
        else { throw Unsupported(what: "No group with id: \(number.map { "\($0)" } ?? "none").") }
        return folder
    }

    /// A folder as Chrome describes a group. Folders have no colour; grey
    /// is Chrome's first.
    static func chromeGroup(_ folder: Folder) -> [String: Any] {
        ["id": Folder.number(folder.id), "title": folder.name, "collapsed": folder.folded,
         "color": "grey", "windowId": 1, "shared": false]
    }

    /// A tab's icon for favIconUrl: the picture the tab wears, as a small
    /// PNG. Shy keeps icons as pictures, not addresses, and Chrome's
    /// favIconUrl may be a data: URL. Made once per site and kept.
    /// A tab as the shim names it: `i`, its place in its window's row as
    /// extensions see it, and `w`, that window's frame from windows.getAll()
    /// (see Extensions.tab(windowFrame:index:)). A bare number, or no frame,
    /// is only understood while there is one window.
    static func located(_ place: Any?, context: WKWebExtensionContext, owner: Extensions) -> Tab? {
        let spec = place as? [String: Any]
        guard let index = (place as? NSNumber)?.intValue ?? (spec?["i"] as? NSNumber)?.intValue else { return nil }
        let number = { (value: Any?) in (value as? NSNumber)?.doubleValue }
        if let w = spec?["w"] as? [String: Any], let left = number(w["left"]), let top = number(w["top"]),
           let width = number(w["width"]), let height = number(w["height"]) {
            return owner.tab(windowFrame: CGRect(x: left, y: top, width: width, height: height), index: index, for: context)
        }
        guard Browsers.all.count <= 1 else { return nil }
        let visible = owner.visibleTabs(for: context)
        return visible.indices.contains(index) ? visible[index] : nil
    }

    /// Each icon drawn once; the image is held so its identity stays its own.
    static var favIcons: [ObjectIdentifier: (icon: NSImage, url: String)] = [:]
    static func forgetIcons() { favIcons.removeAll() }

    static func favIconURL(_ tab: Tab) -> String? {
        guard let icon = tab.icon ?? Favicons.of(tab.profile).cached(for: tab.address, shy: tab.shy) else { return nil }
        if let known = favIcons[ObjectIdentifier(icon)] { return known.url }
        let side = 32
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                                            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        icon.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
        let url = "data:image/png;base64," + png.base64EncodedString()
        if favIcons.count > 500 { favIcons.removeAll() }
        favIcons[ObjectIdentifier(icon)] = (icon, url)
        return url
    }
}
