import AppKit
import WebKit
import Combine
import NaturalLanguage
import UserNotifications
import IOKit.pwr_mgt
import CryptoKit

// The Chrome APIs WebKit doesn't have, filled in by the browser itself.
//
// Safari's extension engine covers tabs, storage, scripting, request rules,
// cookies, menus, alarms and messaging. Chrome extensions also reach for
// bookmarks, history, downloads, the side panel, offscreen documents, tab
// groups and OAuth — and fall over when those are undefined.
//
// So when an extension is installed, a small script is put at the front of
// its background and of every page it ships: `chrome.bookmarks` and the rest
// are defined there, and every call becomes a native message to this app,
// which answers from its own bookmarks, history and downloads. To the
// extension it looks like Chrome. The files are changed after the store's
// signature has been checked, and only by adding.

@available(macOS 15.4, *)
@MainActor
enum ExtensionShims {
    /// The name native messages to the browser itself go to.
    static let application = "shy"
    nonisolated static let file = "shy-shim.js"
    /// Shy's passkey patch, put first in every script an extension runs in
    /// a page's own world (see Passkeys.swift, and `first` in the script).
    nonisolated static let passkeys = "shy-passkeys.js"
    /// The first line of a worker that already carries the shim.
    nonisolated static let marker = "/* Shy: Chrome APIs WebKit lacks, filled in (ExtensionShims.swift) */"
    nonisolated static let ender = "/* Shy: end of shim */"

    // MARK: - at install

    /// Written beside a prepared extension: which shim it carries. The same
    /// one needs nothing redone, which matters at launch — preparing reads
    /// every script and page an extension ships.
    nonisolated static let stamp = ".shy-shim"
    /// Raised when `prepare` changes what it does to a package, so that
    /// extensions prepared before are prepared again.
    nonisolated private static let preparation = "4"
    nonisolated static let version: String = {
        SHA256.hash(data: Data((script + PasskeyRelay.page + preparation).utf8)).prefix(8).map { String(format: "%02x", $0) }.joined() + (Store.testing ? "-test" : "")
    }()

    /// `fresh`: a package just unpacked or copied in. What only Shy writes
    /// beside an extension — which permissions it added, which shim it
    /// carries — is Shy's to say, never the package's: anything by those
    /// names that came inside it goes before a word of it is read.
    nonisolated static func prepare(_ folder: URL, fresh: Bool = false, workerGeneration: Int = 0) throws {
        let files = FileManager.default
        if fresh {
            for name in [stamp, ".shy-added"] { try? files.removeItem(at: folder.appendingPathComponent(name)) }
        }
        let stampURL = folder.appendingPathComponent(stamp)
        let revision = version + "-worker-\(workerGeneration)"
        if (try? String(contentsOf: stampURL, encoding: .utf8)) == revision { return }
        defer { try? revision.write(to: stampURL, atomically: true, encoding: .utf8) }
        let manifestURL = folder.appendingPathComponent("manifest.json")
        guard var manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
        else { throw Crx.Refused.unpack }

        let script = shim(for: folder).replacingOccurrences(of: "__SHY_WORKER_GENERATION__", with: String(workerGeneration))
        try script.write(to: folder.appendingPathComponent(file), atomically: true, encoding: .utf8)
        try PasskeyRelay.page.write(to: folder.appendingPathComponent(passkeys), atomically: true, encoding: .utf8)

        // Native messaging is how the shim reaches the browser; user scripts
        // are carried out through WebKit's registered content scripts, which
        // need scripting. What is added is written down, so the extension is
        // described by what it asked for, not by what Shy gave it.
        var permissions = manifest["permissions"] as? [Any] ?? []
        let asked = Set(permissions.compactMap { $0 as? String })
        var added = (try? JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent(".shy-added")))) as? [String] ?? []
        for needed in ["nativeMessaging"] + (asked.contains("userScripts") ? ["scripting"] : []) where !asked.contains(needed) {
            permissions.append(needed)
            added.append(needed)
        }
        manifest["permissions"] = permissions
        if let data = try? JSONSerialization.data(withJSONObject: Array(Set(added)).sorted()) {
            try? data.write(to: folder.appendingPathComponent(".shy-added"))
        }

        // The background, whichever kind it is, gets the shim first. A
        // classic service worker gets it written at the top of its own file;
        // a module one imports it first, as its imports run before anything
        // written above them.
        if var background = manifest["background"] as? [String: Any] {
            // A manifest is not a way out of its own package: a worker path
            // that resolves outside the folder, or is a link, is left alone.
            if let worker = background["service_worker"] as? String { unlink(worker, in: folder) }
            if let worker = background["service_worker"] as? String,
               let path = inside(worker, of: folder) {
                if var source = try? String(contentsOf: path, encoding: .utf8) {
                    // Already carrying one: take the old one off, so a newer
                    // Shy puts its newer shim in its place.
                    if source.hasPrefix(marker), let end = source.range(of: ender) {
                        source = String(source[end.upperBound...]).trimmingPrefix("\n").description
                    }
                    // A copy from before there was an end marker: it ends
                    // where its function does, the first `})();` that
                    // starts a line.
                    while source.hasPrefix(marker), let end = source.range(of: "\n})();\n") {
                        source = String(source[end.upperBound...])
                    }
                    let first = "import \"/\(file)\";\n"
                    while source.hasPrefix(first) { source.removeFirst(first.count) }
                    let module = (background["type"] as? String) == "module"
                    try (module ? first + source : marker + "\n" + script + "\n" + ender + "\n" + source).write(to: path, atomically: true, encoding: .utf8)
                }
            }
            // Scripts, alone or beside a worker — WebKit runs them as a page
            // when a manifest names both.
            if var scripts = background["scripts"] as? [String] {
                if scripts.first != file { scripts.insert(file, at: 0) }
                background["scripts"] = scripts
            }
            manifest["background"] = background
        }

        // Content scripts too — there only Chrome's behaviour is mended. One
        // that runs in the page's own world has Shy's passkey patch before
        // it: a password manager's there keeps a reference to
        // navigator.credentials as it finds it, and that has to be Shy's,
        // not WebKit's (see Passkeys.swift).
        if let entries = manifest["content_scripts"] as? [[String: Any]] {
            manifest["content_scripts"] = entries.map { entry -> [String: Any] in
                var entry = entry
                if var js = entry["js"] as? [String] {
                    if !js.contains(file) { js.insert(file, at: 0) }
                    if (entry["world"] as? String)?.uppercased() == "MAIN", !js.contains(passkeys) { js.insert(passkeys, at: 0) }
                    entry["js"] = js
                }
                return entry
            }
        }

        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .withoutEscapingSlashes])
        try data.write(to: manifestURL, options: .atomic)

        // Every page it ships — popup, options, background page, side panel —
        // and scripts a content script may insert into a website. WebKit
        // decodes those in the site's encoding unless the resource says
        // otherwise: Backpack's Unicode regexes break on a windows-1252
        // page. A UTF-8 signature keeps the script's text independent of
        // the page without changing the page's own encoding or scripts.
        let signature = Data([0xEF, 0xBB, 0xBF])
        let walker = files.enumerator(at: folder, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey])
        while let url = walker?.nextObject() as? URL {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  inside(String(url.path.dropFirst(folder.path.count)), of: folder) != nil
            else { continue }
            if ["js", "mjs"].contains(url.pathExtension.lowercased()) {
                guard let bytes = try? Data(contentsOf: url),
                      !bytes.starts(with: signature), bytes.contains(where: { $0 >= 0x80 }),
                      String(data: bytes, encoding: .utf8) != nil,
                      // A hashbang must stay at the very first character.
                      !bytes.starts(with: [0x23, 0x21])
                else { continue }
                // As every other rewrite here: one that fails leaves the
                // file as it was, and the stamp is still written (see the
                // defer above), so it isn't tried again at every launch.
                try? (signature + bytes).write(to: url, options: .atomic)
                continue
            }
            guard ["html", "htm"].contains(url.pathExtension.lowercased()),
                  var html = try? String(contentsOf: url, encoding: .utf8)
            else { continue }
            if let chained = chainModules(html, page: url, folder: folder) {
                html = chained
                try? html.write(to: url, atomically: true, encoding: .utf8)
            }
            guard !html.contains(file) else { continue }
            let tag = "<script src=\"/\(file)\"></script>"
            if let head = html.range(of: "<head[^>]*>", options: [.regularExpression, .caseInsensitive]) {
                html.insert(contentsOf: tag, at: head.upperBound)
            } else {
                html = tag + html
            }
            try? html.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// A page's module scripts, two or more of them with one that awaits,
    /// made one module that imports them in their order: nil when there is
    /// nothing to do. Chrome waits for a module still at a top-level await
    /// before running a later tag's module that imports it; WebKit runs the
    /// later one at once, which then reads the first one's exports before
    /// they exist ("Cannot access 'd' before initialization"). Vimium C's
    /// options page lists five, the second awaiting its translations, and
    /// stayed blank. Inside one module's imports WebKit does wait, so the
    /// tags become one, in a file of Shy's beside the page (named with
    /// `search-` like the shim). The modules themselves are not touched. Only
    /// plain tags: one marked async, or a src that isn't the package's own
    /// file, leaves the page as it is.
    nonisolated static func chainModules(_ html: String, page: URL, folder: URL) -> String? {
        let tags = try! NSRegularExpression(pattern: #"<script\b([^>]*)>\s*</script>"#, options: [.caseInsensitive])
        let module = try! NSRegularExpression(pattern: #"\btype\s*=\s*["']?module\b"#, options: [.caseInsensitive])
        let source = try! NSRegularExpression(pattern: #"\bsrc\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#, options: [.caseInsensitive])
        let async = try! NSRegularExpression(pattern: #"(^|\s)async(\s|=|$)"#, options: [.caseInsensitive])
        let whole = NSRange(html.startIndex..., in: html)
        var found: [(range: Range<String.Index>, attributes: String, src: String)] = []
        for match in tags.matches(in: html, range: whole) {
            guard let range = Range(match.range, in: html), let inner = Range(match.range(at: 1), in: html) else { continue }
            let attributes = String(html[inner])
            let span = NSRange(attributes.startIndex..., in: attributes)
            guard module.firstMatch(in: attributes, range: span) != nil else { continue }
            guard async.firstMatch(in: attributes, range: span) == nil,
                  let named = source.firstMatch(in: attributes, range: span),
                  let src = (1...3).lazy.compactMap({ Range(named.range(at: $0), in: attributes) }).first.map({ String(attributes[$0]) }),
                  !src.isEmpty, !src.contains(":"), !src.hasPrefix("//"), !src.contains(where: \.isNewline)
            else { return nil }
            found.append((range, attributes, src))
        }
        guard found.count >= 2 else { return nil }
        // The package's own files, and one of them awaiting at all: without
        // an await, every module has run by the time the next tag's does.
        let directory = page.deletingLastPathComponent()
        let root = folder.standardizedFileURL.path + "/"
        var awaits = false
        for entry in found {
            let path = entry.src.split(separator: "?").first.map(String.init) ?? entry.src
            let file = (path.hasPrefix("/") ? folder.appendingPathComponent(String(path.dropFirst())) : directory.appendingPathComponent(path)).standardizedFileURL
            guard file.path.hasPrefix(root), let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
            if text.range(of: #"\bawait\b"#, options: .regularExpression) != nil { awaits = true }
        }
        guard awaits else { return nil }
        let name = "shy-modules-" + page.deletingPathExtension().lastPathComponent + ".js"
        let imports = found.map { entry -> String in
            let spec = entry.src.hasPrefix("/") || entry.src.hasPrefix("./") || entry.src.hasPrefix("../") ? entry.src : "./" + entry.src
            return "import \"\(spec.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\";"
        }
        do {
            try ("// Shy: this page's module scripts, in their order (ExtensionShims.chainModules).\n" + imports.joined(separator: "\n") + "\n")
                .write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
        } catch { return nil }
        // The first tag, its other attributes kept (blocking="render"), now
        // naming the one module; the others gone.
        var html = html
        for (index, entry) in found.enumerated().reversed() {
            if index == 0 {
                let span = NSRange(entry.attributes.startIndex..., in: entry.attributes)
                let attributes = source.stringByReplacingMatches(in: entry.attributes, range: span, withTemplate: NSRegularExpression.escapedTemplate(for: "src=\"\(name)\""))
                html.replaceSubrange(entry.range, with: "<script\(attributes)></script>")
            } else {
                html.removeSubrange(entry.range)
            }
        }
        return html
    }

    /// A worker that is a link to another file of its own package
    /// (StopTheMadness ships `background-143.js` → `background.js`) is made
    /// a copy of that file, so it can carry the shim. A link that leads out
    /// of the package is left as it is, and so left alone.
    nonisolated private static func unlink(_ name: String, in folder: URL) {
        let path = folder.appendingPathComponent(name.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).standardizedFileURL
        guard path.path.hasPrefix(folder.standardizedFileURL.path + "/"),
              (try? path.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
        else { return }
        let root = folder.resolvingSymlinksInPath().path
        let parent = path.deletingLastPathComponent().resolvingSymlinksInPath().path
        let target = path.resolvingSymlinksInPath()
        guard parent == root || parent.hasPrefix(root + "/"),
              target.path.hasPrefix(root + "/"),
              (try? target.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
              let data = try? Data(contentsOf: target)
        else { return }
        try? FileManager.default.removeItem(at: path)
        try? data.write(to: path)
    }

    /// A path a package names, resolved and kept inside the folder it came
    /// in: `..` in a manifest is not a way out of the package. Nor is a
    /// symbolic link, which a folder install keeps as it is: the worker is
    /// read through it and written back over it as a regular file, so a
    /// link to a file elsewhere would put that file's bytes in the package.
    /// A folder on the way that is a link is caught by where it resolves.
    nonisolated private static func inside(_ name: String, of folder: URL) -> URL? {
        let path = folder.appendingPathComponent(name.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).standardizedFileURL
        guard path.path.hasPrefix(folder.standardizedFileURL.path + "/"),
              (try? path.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
              path.resolvingSymlinksInPath().path.hasPrefix(folder.resolvingSymlinksInPath().path + "/")
        else { return nil }
        return path
    }

    /// The shim as this extension gets it: with the events its code mentions
    /// — `chrome.tabs.onUpdated`, `e.runtime.onInstalled` — so its worker
    /// can take their listeners late (see the end of the script).
    nonisolated static func shim(for folder: URL) -> String {
        var found = Set<String>()
        let pattern = try! NSRegularExpression(pattern: #"\.([a-zA-Z]+)\.(on[A-Z][A-Za-z]+)\b"#)
        let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
        while let url = walker?.nextObject() as? URL {
            guard url.pathExtension == "js", url.lastPathComponent != file,
                  var text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            // Not the shim's own words, in a worker that already carries it.
            if text.hasPrefix(marker), let end = text.range(of: ender) { text = String(text[end.upperBound...]) }
            let range = NSRange(text.startIndex..., in: text)
            for match in pattern.matches(in: text, range: range) {
                guard let a = Range(match.range(at: 1), in: text), let b = Range(match.range(at: 2), in: text) else { continue }
                found.insert("\(text[a]).\(text[b])")
            }
        }
        let list = (try? JSONSerialization.data(withJSONObject: found.sorted())).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        // And the scripts it ships, so its worker can be told at once that
        // one isn't there (see importScripts in the script).
        var scripts: [String] = []
        let all = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
        while let url = all?.nextObject() as? URL {
            guard url.pathExtension == "js" else { continue }
            let path = String(url.standardizedFileURL.path.dropFirst(folder.standardizedFileURL.path.count))
            // An empty one is marked: there is nothing to run in it.
            let empty = ((try? String(contentsOf: url, encoding: .utf8)) ?? "x").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            scripts.append((empty ? "-" : "") + path)
        }
        let shipped = (try? JSONSerialization.data(withJSONObject: scripts.sorted())).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        return script.replacingOccurrences(of: "__SHY_EVENTS__", with: list)
            .replacingOccurrences(of: "__SHY_SCRIPTS__", with: shipped)
            .replacingOccurrences(of: "__SHY_CHROME__", with: Crx.chromeVersion)
            .replacingOccurrences(of: "__SHY_VERBOSE__", with: Store.testing ? "true" : "false")
    }

    /// Defines only what is missing, so the day WebKit implements an API,
    /// WebKit's is the one used.
    nonisolated static let script = Scripts.load("shim")

    // MARK: - answering

    /// Remembered per extension: the side panel it set, and whether its
    /// button should open it.
    static var panelPath: [String: String] = [:]
    static var panelOnClick: Set<String> = []
    /// Turned off for the whole window (setOptions enabled: false).
    static var panelOff: Set<String> = []
    /// What setOptions said for one tab, by the extension's tab id.
    static var panelTabs: [String: [Int: (path: String?, enabled: Bool?)]] = [:]
    /// One voice for every extension that reads aloud.
    static let speaker = NSSpeechSynthesizer()

    static func answer(_ message: Any, from context: WKWebExtensionContext, owner: Extensions) async throws -> Any? {
        guard let body = message as? [String: Any], let api = body["api"] as? String else {
            return ["error": "Not a Shy message"]
        }
        let args = body["args"] as? [Any] ?? []
        do {
            return ["value": try await run(api, args, context: context, owner: owner) ?? NSNull()]
        } catch {
            return ["error": error.localizedDescription]
        }
    }

    /// The tab groups an extension is shown: the folders with a tab of their
    /// own in them, never an empty one, as Chrome has no group without a
    /// tab (see the tab groups cases in `run`).
    private static func listedGroups(_ browser: Browser) -> [Folder] {
        let filed = Set(browser.tabs.compactMap { $0.pin == nil ? nil : $0.folder })
        return browser.folders.filter { filed.contains($0.id) }
    }

    private static func listedGroup(_ number: Any?, in browser: Browser) throws -> Folder {
        guard let number = number as? Int,
              let folder = listedGroups(browser).first(where: { Folder.number($0.id) == number })
        else { throw Unsupported(what: "No group with id: \(number.map { "\($0)" } ?? "none").") }
        return folder
    }

    /// A folder as Chrome describes a group. Folders have no colour; grey
    /// is Chrome's first.
    private static func chromeGroup(_ folder: Folder) -> [String: Any] {
        ["id": Folder.number(folder.id), "title": folder.name, "collapsed": folder.folded,
         "color": "grey", "windowId": 1, "shared": false]
    }

    struct Unsupported: LocalizedError {
        let what: String
        var errorDescription: String? { what }
    }

    /// The families whose answers leave the extension's own origin: what the
    /// browser knows about the person using it. WebKit keeps no permission
    /// object for them, they are the APIs this shim exists to supply, so the
    /// gate reads the names the extension's own manifest asked for.
    private static let gates: [String: String] = [
        "bookmarks": "bookmarks",
        "history": "history",
        "downloads": "downloads",
        "sessions": "sessions",
        "topSites": "topSites",
        "browsingData": "browsingData",
        "readingList": "readingList",
        "userScripts": "userScripts",
        "identity": "identity",
        "search": "search",
        "notifications": "notifications",
        "idle": "idle",
        "power": "power",
        "tts": "tts",
        "tabGroups": "tabGroups",
    ]

    /// What this extension asked for: the names in its manifest and any
    /// optional ones granted since. The checks inside the shim are a
    /// courtesy to honest code, the shim runs beside the extension's own,
    /// so the one that counts is here. The manifest is the one WebKit
    /// already holds, not the file read again on every call.
    /// A tab's icon for favIconUrl: the picture the tab wears, as a small
    /// PNG. Shy keeps icons as pictures, not addresses, and Chrome's
    /// favIconUrl may be a data: URL. Made once per site and kept.
    /// A tab as the shim names it: `i`, its place in its window's row as
    /// extensions see it, and `w`, that window's frame from windows.getAll()
    /// (see Extensions.tab(windowFrame:index:)). A bare number, or no frame,
    /// is only understood while there is one window.
    private static func located(_ place: Any?, context: WKWebExtensionContext, owner: Extensions) -> Tab? {
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
    private static var favIcons: [ObjectIdentifier: (icon: NSImage, url: String)] = [:]
    static func forgetIcons() { favIcons.removeAll() }

    private static func favIconURL(_ tab: Tab) -> String? {
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

    static func allowed(_ id: String, context: WKWebExtensionContext) -> Set<String> {
        let asked = (context.webExtension.manifest["permissions"] as? [Any] ?? []).compactMap { $0 as? String }
        return Set(asked + (Store.settings.stringArray(forKey: "extensions.granted.\(id)") ?? []))
    }

    private static func run(_ api: String, _ args: [Any], context: WKWebExtensionContext, owner: Extensions) async throws -> Any? {
        guard let browser = owner.browser else { throw Unsupported(what: "No browser window") }
        let first = args.first
        let id = context.uniqueIdentifier

        if api.hasPrefix("setting.") {
            // A browser setting (chrome.privacy…) belongs to the family its
            // name starts with, and only an extension that asked for that
            // family may read or change it, as in Chrome.
            let name = api.split(separator: ":", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
            let family = String(name.prefix(while: { $0 != "." }))
            guard !family.isEmpty, allowed(id, context: context).contains(family) else {
                throw Unsupported(what: "The extension never asked for \u{201C}\(family)\u{201D}")
            }
            return setting(api, first as? [String: Any] ?? [:], extension: id, owner: owner)
        }

        // What leaves this app is answered here, not in the injected script:
        // the shim runs beside the extension's own code, so its checks stop
        // only the honest. A family this extension never asked for is an
        // error, the way Chrome answers a call to an API it lacks.
        // `tabs.describe` is the one call inside a family WebKit does own
        // where the permission guards reading a tab rather than moving or
        // selecting it. WebKit keeps that permission, optional grants
        // included, so it is asked.
        if api == "tabs.describe", !context.hasPermission(.tabs) {
            throw Unsupported(what: "The extension never asked for \u{201C}tabs\u{201D}")
        }
        if let needed = gates[String(api.prefix(while: { $0 != "." }))], !allowed(id, context: context).contains(needed) {
            throw Unsupported(what: "The extension never asked for \u{201C}\(needed)\u{201D}")
        }

        switch api {
        // MARK: bookmarks
        case "bookmarks.getTree":
            return [root(browser.bookmarks.roots)]
        case "bookmarks.getSubTree":
            guard let key = first as? String else { return [] }
            if key == "0" { return [root(browser.bookmarks.roots)] }
            if key == "1" { return [bar(browser.bookmarks.roots)] }
            return find(key, in: browser.bookmarks.roots).map { [node($0.node, parent: $0.parent, index: $0.index, deep: true)] } ?? []
        case "bookmarks.getChildren":
            let key = first as? String ?? "1"
            if key == "0" { return [bar(browser.bookmarks.roots, deep: false)] }
            let kids = key == "1" ? browser.bookmarks.roots : (find(key, in: browser.bookmarks.roots)?.node.children ?? [])
            return kids.enumerated().map { node($1, parent: key, index: $0, deep: false) }
        case "bookmarks.get":
            let keys = (first as? [String]) ?? (first as? String).map { [$0] } ?? []
            return keys.compactMap { key in
                find(key, in: browser.bookmarks.roots).map { node($0.node, parent: $0.parent, index: $0.index, deep: false) }
            }
        case "bookmarks.getRecent":
            let count = (first as? Int) ?? 10
            return flat(browser.bookmarks.roots).filter { !$0.node.isFolder }.suffix(count).reversed()
                .map { node($0.node, parent: $0.parent, index: $0.index, deep: false) }
        case "bookmarks.search":
            let query = (first as? String) ?? ((first as? [String: Any])?["query"] as? String) ?? ""
            let wantURL = (first as? [String: Any])?["url"] as? String
            let wantTitle = (first as? [String: Any])?["title"] as? String
            let words = query.lowercased().split(separator: " ").map(String.init)
            return flat(browser.bookmarks.roots).filter { hit in
                let n = hit.node
                if let wantURL, n.url != wantURL { return false }
                if let wantTitle, n.title != wantTitle { return false }
                let hay = (n.title + " " + (n.url ?? "")).lowercased()
                return words.allSatisfy { hay.contains($0) }
            }.map { node($0.node, parent: $0.parent, index: $0.index, deep: false) }
        case "bookmarks.create":
            let spec = first as? [String: Any] ?? [:]
            let title = spec["title"] as? String ?? ""
            let parent = (spec["parentId"] as? String).flatMap(UUID.init(uuidString:))
            let index = spec["index"] as? Int
            let made: Bookmark
            if let url = (spec["url"] as? String).flatMap(URL.init(string:)) {
                made = browser.bookmarks.insert(.site(title, url), into: parent, at: index)
            } else {
                made = browser.bookmarks.insert(.folder(title, []), into: parent, at: index)
            }
            return find(made.id.uuidString, in: browser.bookmarks.roots).map { node($0.node, parent: $0.parent, index: $0.index, deep: false) }
        case "bookmarks.update":
            guard let key = first as? String, let uuid = UUID(uuidString: key) else { throw Unsupported(what: "No such bookmark") }
            let changes = args.count > 1 ? args[1] as? [String: Any] ?? [:] : [:]
            browser.bookmarks.update(uuid, title: changes["title"] as? String, url: changes["url"] as? String)
            return find(key, in: browser.bookmarks.roots).map { node($0.node, parent: $0.parent, index: $0.index, deep: false) }
        case "bookmarks.move":
            guard let key = first as? String, let uuid = UUID(uuidString: key) else { throw Unsupported(what: "No such bookmark") }
            let spec = (args.count > 1 ? args[1] as? [String: Any] : nil) ?? [:]
            // No parent named keeps it in the folder it is in, as in Chrome;
            // "1", the bar, is the top level.
            let target = (spec["parentId"] as? String).map(UUID.init(uuidString:)) ?? browser.bookmarks.parent(of: uuid)
            browser.bookmarks.move(uuid, into: target, at: spec["index"] as? Int)
            return find(key, in: browser.bookmarks.roots).map { node($0.node, parent: $0.parent, index: $0.index, deep: false) }
        case "bookmarks.remove", "bookmarks.removeTree":
            guard let key = first as? String, let uuid = UUID(uuidString: key) else { throw Unsupported(what: "No such bookmark") }
            browser.bookmarks.remove(uuid)
            return nil

        // MARK: history
        case "history.search":
            let spec = first as? [String: Any] ?? [:]
            let text = spec["text"] as? String ?? ""
            let start = (spec["startTime"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
                ?? Date().addingTimeInterval(-24 * 3600)
            let end = (spec["endTime"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) } ?? .distantFuture
            let limit = spec["maxResults"] as? Int ?? 100
            return browser.history.everything(matching: text)
                .filter { $0.last >= start && $0.last <= end }
                .sorted { $0.last > $1.last }
                .prefix(limit)
                .map(visit)
        case "history.getVisits":
            let url = (first as? [String: Any])?["url"] as? String ?? ""
            return browser.history.everything().filter { $0.url.absoluteString == url }.map { trace in
                ["id": trace.key, "visitId": "1", "visitTime": trace.last.timeIntervalSince1970 * 1000,
                 "referringVisitId": "0", "transition": "link"]
            }
        case "history.addUrl":
            if let url = ((first as? [String: Any])?["url"] as? String).flatMap(URL.init(string:)) {
                browser.history.record(url, title: "")
            }
            return nil
        case "history.deleteUrl":
            let url = (first as? [String: Any])?["url"] as? String ?? ""
            for trace in browser.history.everything() where trace.url.absoluteString == url {
                browser.history.forget(trace.key)
            }
            return nil
        case "history.deleteRange":
            let spec = first as? [String: Any] ?? [:]
            let start = Date(timeIntervalSince1970: (spec["startTime"] as? Double ?? 0) / 1000)
            let end = Date(timeIntervalSince1970: (spec["endTime"] as? Double ?? 0) / 1000)
            for trace in browser.history.everything() where trace.last >= start && trace.last <= end {
                browser.history.forget(trace.key)
            }
            return nil
        case "history.deleteAll":
            browser.history.forget()
            // As Clear History does: the pages icons were kept for go too.
            Favicons.forgetEverything()
            return nil

        // MARK: downloads
        case "downloads.download":
            let spec = first as? [String: Any] ?? [:]
            guard let url = (spec["url"] as? String).flatMap(URL.init(string:)) else { throw Unsupported(what: "No url to download") }
            guard let web = ExtensionShims.downloadPage(active: browser.active, tabs: browser.tabs) else {
                throw Unsupported(what: "No page to download through")
            }
            if let name = spec["filename"] as? String, !name.isEmpty {
                // A name it asks for, which may carry folders: only the last part is kept.
                browser.namedDownloads[url] = (name as NSString).lastPathComponent
            }
            ExtensionShims.askedDownloads[url] = id
            let download = await web.startDownload(using: URLRequest(url: url))
            browser.keep(download)
            return browser.loot.kept.count + 1
        case "downloads.search":
            return browser.loot.kept.enumerated().map { index, keep in
                ["id": index + 1, "url": keep.url.absoluteString, "finalUrl": keep.url.absoluteString,
                 "filename": keep.path, "state": "complete", "exists": keep.stillThere,
                 "startTime": ISO8601DateFormatter().string(from: keep.date), "mime": ""] as [String: Any]
            }
        case "downloads.open", "downloads.show":
            guard let index = first as? Int, browser.loot.kept.indices.contains(index - 1) else { return nil }
            let keep = browser.loot.kept[index - 1]
            if api == "downloads.open" {
                // As in Chrome, opening asks for its own permission; and only
                // a file this extension downloaded itself, not any of yours.
                guard allowed(id, context: context).contains("downloads.open") else {
                    throw Unsupported(what: "The extension never asked for \u{201C}downloads.open\u{201D}")
                }
                // Only when you have just done something in it, as Chrome
                // asks: never on its own, from its worker.
                guard Extensions.justUsed(id) else {
                    throw Unsupported(what: "downloads.open() may only be called in response to a user gesture.")
                }
                guard ExtensionShims.ownDownloads[id]?.contains(keep.path) == true else {
                    throw Unsupported(what: "Only a download this extension started can be opened by it")
                }
                browser.loot.open(keep)
            } else {
                browser.loot.reveal(keep)
            }
            return nil
        case "downloads.showDefaultFolder":
            NSWorkspace.shared.open(browser.prefs.downloads)
            return nil
        case "downloads.erase":
            return []
        case "downloads.pause", "downloads.resume", "downloads.cancel", "downloads.removeFile", "downloads.getFileIcon":
            throw Unsupported(what: "\(api) isn't available in Shy yet")

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

        // MARK: offscreen — a page with a DOM for a worker that has none
        // MARK: capture — a stream id for the worker's chooseDesktopMedia
        case "capture.grant":
            return await ExtensionCapture.shared.grant(for: context)

        case "offscreen.createDocument":
            guard let path = (first as? [String: Any])?["url"] as? String
            else { throw Unsupported(what: "No page for the offscreen document") }
            let reasons = (first as? [String: Any])?["reasons"] as? [String] ?? []
            try await ExtensionOffscreen.create(path, reasons: reasons, for: context)
            return nil
        case "offscreen.closeDocument":
            ExtensionOffscreen.close(for: id)
            return nil
        case "offscreen.hasDocument":
            return ExtensionOffscreen.hasDocument(for: id)
        case "offscreen.sendMessage":
            guard args.count == 3, let token = first as? String,
                  let sender = args[2] as? [String: Any] else { return ["handled": false] }
            return try await ExtensionOffscreen.send(args[1], sender: sender, token: token, for: id)

        // MARK: fonts — what the Mac has; the page's own fonts stay the page's
        case "fontSettings.getFontList":
            return NSFontManager.shared.availableFontFamilies.map { ["fontId": $0, "displayName": $0] }
        case "fontSettings.getFont":
            return ["fontId": "", "levelOfControl": "not_controllable"]
        case "fontSettings.getDefaultFontSize":
            return ["pixelSize": 16, "levelOfControl": "not_controllable"]
        case "fontSettings.getDefaultFixedFontSize":
            return ["pixelSize": 13, "levelOfControl": "not_controllable"]
        case "fontSettings.getMinimumFontSize":
            return ["pixelSize": 0, "levelOfControl": "not_controllable"]
        case _ where api.hasPrefix("fontSettings.set") || api.hasPrefix("fontSettings.clear"):
            return nil

        // MARK: management — only itself
        case "management.getSelf", "management.get":
            let found = context.webExtension
            return ["id": id, "name": found.displayName ?? "", "shortName": found.displayShortName ?? "",
                    "version": found.version ?? "", "description": found.displayDescription ?? "",
                    "enabled": true, "type": "extension", "installType": owner.installed.first { $0.id == id }?.fromStore == false ? "development" : "normal",
                    "mayDisable": true, "offlineEnabled": true, "isApp": false, "hostPermissions": [], "permissions": []]
        case "management.getAll":
            return []
        case "management.setEnabled", "management.uninstallSelf":
            throw Unsupported(what: "Extensions are turned on and off in Settings › Extensions")

        // MARK: language
        case "i18n.detectLanguage":
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(first as? String ?? "")
            let guesses = recognizer.languageHypotheses(withMaximum: 3)
            return ["isReliable": (guesses.values.max() ?? 0) > 0.6,
                    "languages": guesses.sorted { $0.value > $1.value }.map { ["language": $0.key.rawValue, "percentage": Int($0.value * 100)] }]
        case "runtime.getContexts":
            // The extension's own pages that Chrome would list: its worker,
            // its popup while it is up, its offscreen document. Bitwarden
            // asks for these to know where to send its messages.
            let filter = first as? [String: Any] ?? [:]
            let types = filter["contextTypes"] as? [String]
            let urls = filter["documentUrls"] as? [String]
            var found: [[String: Any]] = []
            func add(_ type: String, _ url: URL?) {
                guard types == nil || types!.contains(type) else { return }
                let address = url?.absoluteString ?? ""
                guard urls == nil || urls!.contains(address) else { return }
                found.append([
                    "contextType": type, "contextId": "\(id)-\(type)", "tabId": -1, "windowId": -1,
                    "frameId": type == "BACKGROUND" ? -1 : 0, "documentUrl": address,
                    "documentOrigin": url.map { "\($0.scheme ?? "")://\($0.host ?? "")" } ?? "",
                    "incognito": false,
                ])
            }
            if context.webExtension.hasBackgroundContent {
                let manifest = context.webExtension.manifest["background"] as? [String: Any] ?? [:]
                let script = manifest["service_worker"] as? String ?? manifest["page"] as? String
                add("BACKGROUND", script.map { context.baseURL.appendingPathComponent($0) })
            }
            if ExtensionPopup.shared.extensionID == id { add("POPUP", ExtensionPopup.shared.view?.url) }
            found += ExtensionOffscreen.contexts(for: id, matching: filter)
            return found

        // MARK: notifications — the Mac's own
        case "notifications.create":
            let named = first as? String
            let options = (named == nil ? first : (args.count > 1 ? args[1] : nil)) as? [String: Any] ?? [:]
            let key = named ?? UUID().uuidString
            let center = UNUserNotificationCenter.current()
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            let content = UNMutableNotificationContent()
            content.title = options["title"] as? String ?? (context.webExtension.displayName ?? "")
            content.body = options["message"] as? String ?? ""
            content.subtitle = context.webExtension.displayName ?? ""
            try? await center.add(UNNotificationRequest(identifier: "\(id).\(key)", content: content, trigger: nil))
            return key
        case "notifications.clear":
            if let key = first as? String {
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["\(id).\(key)"])
            }
            return true
        case "notifications.getAll":
            return [String: Any]()
        case "notifications.getPermissionLevel":
            return "granted"
        case "notifications.update":
            return false

        // MARK: speech
        case "tts.speak":
            let options = (args.count > 1 ? args[1] : nil) as? [String: Any] ?? [:]
            if !(options["enqueue"] as? Bool ?? false) { speaker.stopSpeaking() }
            if let voice = options["voiceName"] as? String,
               let match = NSSpeechSynthesizer.availableVoices.first(where: { NSSpeechSynthesizer.attributes(forVoice: $0)[.name] as? String == voice }) {
                speaker.setVoice(match)
            }
            if let rate = options["rate"] as? Double { speaker.rate = Swift.Float(180 * rate) }
            speaker.startSpeaking(first as? String ?? "")
            return nil
        case "tts.stop":
            speaker.stopSpeaking()
            return nil
        case "tts.pause":
            speaker.pauseSpeaking(at: .immediateBoundary)
            return nil
        case "tts.resume":
            speaker.continueSpeaking()
            return nil
        case "tts.isSpeaking":
            return speaker.isSpeaking
        case "tts.getVoices":
            return NSSpeechSynthesizer.availableVoices.map { voice -> [String: Any] in
                let attributes = NSSpeechSynthesizer.attributes(forVoice: voice)
                return ["voiceName": attributes[.name] as? String ?? voice.rawValue,
                        "lang": (attributes[.localeIdentifier] as? String ?? "").replacingOccurrences(of: "_", with: "-"),
                        "remote": false, "eventTypes": ["start", "end"]]
            }

        // MARK: the worker, up before a page talks to it
        case "background.observe":
            guard owner.contexts[id] === context, context.isLoaded else { return nil }
            return await ExtensionWorkerRecovery.shared.observe(id, generation: first as? Int ?? 0, token: args.dropFirst().first as? String ?? "")
        case "background.unobserve":
            guard owner.contexts[id] === context else { return nil }
            ExtensionWorkerRecovery.shared.cancel(id, token: first as? String ?? "")
            return nil
        case "background.wake":
            guard context.webExtension.hasBackgroundContent else { return nil }
            // WebKit sometimes fails to start a worker again after unloading
            // it, and then never tries again: every message waits for ever.
            // Tried twice more, then the extension is taken up afresh.
            for attempt in 0..<3 {
                // WebKit never calls back after some failed starts; eight
                // seconds without an answer counts as a failure.
                let error: Error? = await withCheckedContinuation { done in
                    var finished = false
                    let finish: (Error?) -> Void = { result in
                        guard !finished else { return }
                        finished = true
                        done.resume(returning: result)
                    }
                    context.loadBackgroundContent { error in MainActor.assumeIsolated { finish(error) } }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 8) { finish(Unsupported(what: "no answer from WebKit")) }
                }
                guard error != nil else { return nil }
                if attempt < 2 { try? await Task.sleep(for: .milliseconds(400)) }
            }
            owner.revive(id, because: "its worker wouldn't start")
            return nil
        // Whether this extension was loaded before in this run of the
        // browser — an "install" then is really a restart (see the shim).
        case "background.loadedBefore":
            return owner.loadedBefore.contains(id)
        // A page found the worker gone though WebKit believes it runs (see
        // the shim's ping).
        case "background.revive":
            return owner.revive(id, because: "its worker stopped answering")

        // MARK: what went wrong inside
        case "debug.error":
            owner.noteError(first as? String ?? "?", for: id)
            return nil
        case "memory.rulesBuilt":
            Trim.rulesBuilt()
            return nil

        // MARK: its own pages, for clients.matchAll() (see the shim)
        case "clients.pages":
            var pages: [[String: Any]] = []
            if let popup = ExtensionPopup.shared.client(of: id) { pages.append(popup) }
            for tab in browser.tabs where owner.seen(tab, for: context) {
                guard let web = tab.built, let url = web.url, Browser.extensionHost(of: url) == id else { continue }
                let shown = tab.id == browser.activeID && web.window?.occlusionState.contains(.visible) == true
                pages.append(["id": tab.id.uuidString, "url": url.absoluteString, "visible": shown, "focused": shown && web.window?.isKeyWindow == true])
            }
            // Its offscreen document too, as Chrome lists it.
            if let url = ExtensionOffscreen.url(for: id) { pages.append(["id": "offscreen", "url": url.absoluteString, "visible": false, "focused": false]) }
            return pages

        // MARK: the button's popup
        case "action.popup":
            let path = first as? String ?? ""
            let index = args.dropFirst().first as? Int ?? -1
            let visible = owner.visibleTabs(for: context)
            if index >= 0, visible.indices.contains(index) {
                popups[id, default: [:]][visible[index].id.uuidString] = path
            } else {
                popups[id, default: [:]]["*"] = path
                popups[id] = popups[id]?.filter { $0.key == "*" }
            }
            return nil

        // MARK: script injection and user scripts
        case "scripting.file":
            return try scriptingFile(first as? String ?? "", arguments: args.dropFirst().first as? [Any] ?? [], in: owner.folder(for: id))
        case "userScripts.file":
            return try userScriptFile(first as? [String: Any] ?? [:], in: owner.folder(for: id))
        case "userScripts.list":
            return (try? JSONSerialization.jsonObject(with: Data(contentsOf: owner.folder(for: id).appendingPathComponent("_shy/userscripts.json")))) ?? []
        case "userScripts.save":
            let folder = owner.folder(for: id).appendingPathComponent("_shy", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let scripts = first as? [[String: Any]] ?? []
            try JSONSerialization.data(withJSONObject: scripts).write(to: folder.appendingPathComponent("userscripts.json"), options: .atomic)
            // Files no saved script is written in any more, once a moment
            // has passed — one being injected right now is left alone.
            let keep = Set(scripts.compactMap { try? userScriptFile($0, in: owner.folder(for: id)) }.map { URL(fileURLWithPath: $0).lastPathComponent })
            for file in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            where file.lastPathComponent.hasPrefix("us-") && !keep.contains(file.lastPathComponent) {
                let age = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate).map { -$0.timeIntervalSinceNow } ?? 999
                if age > 60 { try? FileManager.default.removeItem(at: file) }
            }
            return nil
        case "userScripts.world", "userScripts.worlds":
            let url = owner.folder(for: id).appendingPathComponent("_shy/worlds.json")
            var worlds = (try? JSONSerialization.jsonObject(with: Data(contentsOf: url))) as? [[String: Any]] ?? []
            if api == "userScripts.worlds" { return worlds }
            let props = first as? [String: Any] ?? [:]
            let world = props["worldId"] as? String ?? ""
            worlds.removeAll { ($0["worldId"] as? String ?? "") == world }
            if props["reset"] as? Bool != true { worlds.append(props) }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: worlds).write(to: url, options: .atomic)
            return nil

        // MARK: permissions Shy grants itself
        case "permissions.granted":
            return Store.settings.stringArray(forKey: "extensions.granted.\(id)") ?? []
        case "permissions.request":
            let wanted = (first as? [String]) ?? []
            // As in Chrome: only what the manifest named, as a permission or
            // an optional one. What was agreed to at install still describes
            // the extension; it can't ask later for something it never named.
            let manifest = context.webExtension.manifest
            let named = Set(((manifest["permissions"] as? [Any] ?? []) + (manifest["optional_permissions"] as? [Any] ?? [])).compactMap { $0 as? String })
            guard wanted.allSatisfy(named.contains) else {
                throw Unsupported(what: "Only permissions specified in the manifest may be requested.")
            }
            // Those Chrome grants without a word, having nothing to warn of.
            let silent: Set<String> = ["tabGroups", "sidePanel", "offscreen", "idle", "power", "fontSettings", "search",
                                       "system.cpu", "system.memory", "system.display", "favicon"]
            let names = wanted.map { $0.replacingOccurrences(of: ".", with: " ") }.joined(separator: ", ")
            let yes = wanted.allSatisfy(silent.contains) ? true : await owner.ask(more: names, context: context)
            guard yes else { return false }
            let had = Store.settings.stringArray(forKey: "extensions.granted.\(id)") ?? []
            Store.settings.set(Array(Set(had + wanted)).sorted(), forKey: "extensions.granted.\(id)")
            return true
        case "permissions.afterClick":
            // permissions.request for WebKit's own permissions and sites,
            // made from a click on the extension's button whose moment
            // WebKit lost while the shim filled in the tab it was given
            // (see `mend`). Only within seconds of that click, once, and
            // only what the manifest names, asked as WebKit would ask it.
            // A click or key in one of the extension's own pages counts too
            // (its options page in a tab, its popup): Chrome treats that as
            // the user gesture, and WebKit loses it as soon as the page
            // awaits anything before calling permissions.request.
            let when = [Extensions.clicked[id], Extensions.touched[id]].compactMap { $0 }.max()
            guard let when, Date().timeIntervalSince(when) < 10 else {
                throw Unsupported(what: "Invalid call to permissions.request(). Must be called during a user gesture.")
            }
            Extensions.clicked[id] = nil
            Extensions.touched[id] = nil
            let found = context.webExtension
            let wanted = ((first as? [String]) ?? []).map { WKWebExtension.Permission(rawValue: $0) }
            let origins = ((args.dropFirst().first as? [String]) ?? []).compactMap { try? WKWebExtension.MatchPattern(string: $0) }
                .filter { !Extensions.withheld($0) }
            let named = found.requestedPermissions.union(found.optionalPermissions)
            // Sites as the manifest names them, optional ones included —
            // which allRequestedMatchPatterns leaves out.
            let places = Set(found.allRequestedMatchPatterns.union(found.optionalPermissionMatchPatterns).map(\.string))
            guard wanted.allSatisfy(named.contains), origins.allSatisfy({ places.contains($0.string) }) else {
                throw Unsupported(what: "Only permissions specified in the manifest may be requested.")
            }
            let missing = wanted.filter { context.permissionStatus(for: $0) != .grantedExplicitly }
            let unreached = origins.filter { pattern in
                let status = context.permissionStatus(for: pattern)
                if status == .grantedExplicitly || status == .grantedImplicitly { return false }
                if status == .deniedExplicitly || status == .deniedImplicitly { return true }
                if context.deniedPermissionMatchPatterns.keys.contains(where: { !$0.matchesAllHosts && $0.matches(pattern) }) { return true }
                // WebKit can report a named pattern as requested even when a wildcard grants it.
                return !context.currentPermissionMatchPatterns.contains { granted in
                    granted.scheme == pattern.scheme && granted.path == pattern.path && granted.matches(pattern)
                }
            }
            guard !missing.isEmpty || !unreached.isEmpty else { return true }
            let every = unreached.contains { $0.matchesAllHosts || $0.matchesAllURLs }
            let sites = every ? "every website" : unreached.map(\.string).sorted().joined(separator: ", ")
            let question = unreached.isEmpty ? "asks for more access" : "wants to read and change \(sites)"
            let detail = missing.isEmpty ? "Until you remove the extension." : missing.map(\.rawValue).sorted().joined(separator: ", ")
            guard await owner.ask(question, detail: detail, context: context) else { return false }
            for permission in missing { context.setPermissionStatus(.grantedExplicitly, for: permission) }
            for pattern in unreached { context.setPermissionStatus(.grantedExplicitly, for: pattern) }
            Extensions.fence(context)
            return true
        case "permissions.removeWebsites":
            // What fence() keeps of <all_urls> once it is given back, and
            // <all_urls> itself: both, and exactly those, so a host the
            // manifest names stays. Taken out of the granted list as it is:
            // WebKit's own "unknown" leaves *://*/* granted beside a named
            // host (AllURLsRemovalTests).
            let everything: Set<String> = ["<all_urls>", "*://*/*"]
            context.grantedPermissionMatchPatterns = context.grantedPermissionMatchPatterns
                .filter { !everything.contains($0.key.string) }
            return true
        case "permissions.remove":
            let gone = Set((first as? [String]) ?? [])
            let had = Store.settings.stringArray(forKey: "extensions.granted.\(id)") ?? []
            Store.settings.set(had.filter { !gone.contains($0) }, forKey: "extensions.granted.\(id)")
            return true

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

        // MARK: search
        case "search.query":
            let spec = first as? [String: Any] ?? [:]
            // Words to search for, as in Chrome — never an address, file:
            // and data: included, which the address field would take.
            guard let url = browser.searchURL(for: spec["text"] as? String ?? "") else { return nil }
            switch spec["disposition"] as? String {
            case "NEW_TAB", "NEW_WINDOW": browser.open(url, foreground: true)
            default:
                guard browser.active.map({ owner.seen($0, for: context) }) ?? true else { throw Unsupported(what: "No tab there") }
                browser.visit(url)
            }
            return nil

        // MARK: idle
        case "idle.queryState":
            let threshold = (first as? Double) ?? 60
            if let session = CGSessionCopyCurrentDictionary() as? [String: Any],
               session["CGSSessionScreenIsLocked"] as? Bool == true { return "locked" }
            let quiet = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
            return quiet >= threshold ? "idle" : "active"
        case "idle.getAutoLockDelay":
            return 0

        // MARK: power
        case "power.requestKeepAwake":
            let display = (first as? String) == "display"
            if let old = awake[id] { IOPMAssertionRelease(old) }
            var assertion: IOPMAssertionID = 0
            let kind = (display ? kIOPMAssertionTypePreventUserIdleDisplaySleep : kIOPMAssertionTypePreventUserIdleSystemSleep) as CFString
            if IOPMAssertionCreateWithName(kind, IOPMAssertionLevel(kIOPMAssertionLevelOn), "An extension in Shy" as CFString, &assertion) == kIOReturnSuccess {
                awake[id] = assertion
            }
            return nil
        case "power.releaseKeepAwake":
            if let old = awake.removeValue(forKey: id) { IOPMAssertionRelease(old) }
            return nil
        case "power.reportActivity":
            var assertion: IOPMAssertionID = 0
            IOPMAssertionDeclareUserActivity("An extension in Shy" as CFString, kIOPMUserActiveLocal, &assertion)
            return nil

        // MARK: browsing data
        case "browsingData.settings":
            return ["options": ["since": 0], "dataToRemove": [:], "dataRemovalPermitted": [
                "cache": true, "cookies": true, "history": true, "downloads": true, "localStorage": true,
                "indexedDB": true, "serviceWorkers": true, "cacheStorage": true, "fileSystems": true, "webSQL": true,
            ]]
        case let api where api.hasPrefix("browsingData."):
            let options = first as? [String: Any] ?? [:]
            let what: [String: Bool]
            if api == "browsingData.remove" {
                what = (args.dropFirst().first as? [String: Any] ?? [:]).compactMapValues { $0 as? Bool }
            } else {
                let key = String(api.dropFirst("browsingData.remove".count))
                what = [key.prefix(1).lowercased() + key.dropFirst(): true]
            }
            try await clear(what, options: options, browser: browser)
            return nil

        // MARK: sessions — the tabs you closed
        case "sessions.getRecentlyClosed":
            let limit = (first as? [String: Any])?["maxResults"] as? Int ?? 25
            return browser.closedHere.reversed().prefix(limit).map { ghost in
                ["lastModified": Int(Date().timeIntervalSince1970),
                 "tab": ["sessionId": ghost.id.uuidString, "url": ghost.url.absoluteString, "title": ghost.title,
                         "index": ghost.index, "windowId": 1, "active": false, "pinned": false, "highlighted": false,
                         "incognito": false, "selected": false, "discarded": false, "autoDiscardable": true, "groupId": -1]] as [String: Any]
            }
        case "sessions.getDevices":
            return []
        case "sessions.restore":
            let ghost = (first as? String).flatMap { key in browser.closedHere.first { $0.id.uuidString == key } } ?? browser.closedHere.last
            guard let ghost else { throw Unsupported(what: "Nothing to restore") }
            browser.reopen(ghost)
            return ["lastModified": Int(Date().timeIntervalSince1970),
                    "tab": ["url": ghost.url.absoluteString, "title": ghost.title, "index": ghost.index, "windowId": 1]]

        // MARK: top sites — the most visited in history
        case "topSites.get":
            var visits: [String: (url: URL, title: String, count: Int)] = [:]
            for trace in browser.history.everything() {
                guard let host = trace.url.host() else { continue }
                visits[host, default: (trace.url, trace.title, 0)].count += 1
            }
            return visits.values.sorted { $0.count > $1.count }.prefix(10).map {
                ["url": $0.url.absoluteString, "title": $0.title]
            }

        // MARK: reading list — none kept
        case "readingList.query":
            return []
        case "readingList.addEntry", "readingList.removeEntry", "readingList.updateEntry":
            throw Unsupported(what: "Shy has no reading list")

        // MARK: system
        case "system.cpu.getInfo":
            #if arch(x86_64)
            let (arch, model) = ("x86_64", "Intel")
            #else
            let (arch, model) = ("arm64", "Apple silicon")
            #endif
            return ["numOfProcessors": ProcessInfo.processInfo.processorCount, "archName": arch,
                    "modelName": model, "features": [], "processors": [], "temperatures": []]
        case "system.memory.getInfo":
            return ["capacity": Double(ProcessInfo.processInfo.physicalMemory), "availableCapacity": Double(ProcessInfo.processInfo.physicalMemory) / 2]
        case "system.storage.getInfo":
            return []
        case "system.display.getInfo":
            return NSScreen.screens.enumerated().map { index, screen in
                let f = screen.frame, v = screen.visibleFrame
                return ["id": String(index), "name": screen.localizedName, "isPrimary": index == 0, "isInternal": index == 0,
                        "isEnabled": true, "dpiX": 96 * screen.backingScaleFactor, "dpiY": 96 * screen.backingScaleFactor,
                        "rotation": 0, "bounds": ["left": f.minX, "top": f.minY, "width": f.width, "height": f.height],
                        "workArea": ["left": v.minX, "top": v.minY, "width": v.width, "height": v.height]] as [String: Any]
            }

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

        // MARK: identity
        case "identity.launchWebAuthFlow":
            let spec = first as? [String: Any] ?? [:]
            guard let url = (spec["url"] as? String).flatMap(URL.init(string:)) else { throw Unsupported(what: "No authorization url") }
            // As in Chrome, a flow is non-interactive unless it says otherwise:
            // run out of sight, it either comes straight back or fails.
            if spec["interactive"] as? Bool != true {
                let wait = (spec["timeoutMsForNonInteractive"] as? NSNumber).map { $0.doubleValue / 1000 }
                return try await ExtensionAuth.quietly(url, extension: id,
                                                       abortOnLoad: spec["abortOnLoadForNonInteractive"] as? Bool ?? true,
                                                       timeout: wait).absoluteString
            }
            return try await ExtensionAuth.run(url, extension: id, browser: browser).absoluteString
        case "identity.getProfileUserInfo":
            return ["email": "", "id": ""]
        case "identity.removeCachedAuthToken", "identity.clearAllCachedAuthTokens":
            return nil
        case "identity.getAuthToken":
            throw Unsupported(what: "getAuthToken needs a Google account signed into Chrome; this extension would need launchWebAuthFlow instead")

        default:
            throw Unsupported(what: "\(api) isn't available in Shy")
        }
    }

    // MARK: - the side panel

    /// A function sent by an extension page inside a website's frame cannot
    /// survive the JSON message to its worker. Write it as a file for WebKit's
    /// scripting API, with its JSON arguments and final result intact.
    static func scriptingFile(_ function: String, arguments: [Any], in folder: URL) throws -> String {
        // A megabyte of source at most: a page gone wrong can't fill the
        // extension's folder with big files (Security).
        guard !function.isEmpty, function.utf8.count <= 1_000_000, JSONSerialization.isValidJSONObject(arguments),
              let data = try? JSONSerialization.data(withJSONObject: arguments),
              let args = String(data: data, encoding: .utf8)
        else { throw Unsupported(what: "Invalid script function or arguments") }
        let source = "(\(function))(...\(args))\n"
        let name = "script-" + SHA256.hash(data: Data(source.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined() + ".js"
        let dir = folder.appendingPathComponent("_shy", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: url.path) { try source.write(to: url, atomically: true, encoding: .utf8) }
        for old in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        where old.lastPathComponent.hasPrefix("script-") && old != url {
            let age = (try? old.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate).map { -$0.timeIntervalSinceNow } ?? 0
            if age > 60 { try? FileManager.default.removeItem(at: old) }
        }
        return "_shy/" + name
    }

    /// A user script as a file WebKit can inject: its code — inline, or read
    /// from the extension's own files — inside a block that leaves at once
    /// on a page its globs rule out and, for Chrome's USER_SCRIPT world,
    /// gives the code a `chrome` whose messages are marked as a user
    /// script's. Named by what is in it, so a changed script is a new file
    /// and never a stale one WebKit has already read.
    static func userScriptFile(_ script: [String: Any], in folder: URL) throws -> String {
        let json = { (value: Any) in
            (try? JSONSerialization.data(withJSONObject: value)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        }
        var code = ""
        for source in script["js"] as? [[String: Any]] ?? [] {
            if let inline = source["code"] as? String {
                code += inline + "\n;\n"
            } else if let file = source["file"] as? String,
                      // One of the extension's own files, and nothing outside
                      // its folder: a name is resolved before it is read.
                      let path = inside(file, of: folder),
                      let text = try? String(contentsOf: path, encoding: .utf8) {
                code += text + "\n;\n"
            }
        }
        let userWorld = (script["world"] as? String) != "MAIN"
        let prelude = #"""
          const chrome = (() => {
            const runtime = globalThis.chrome.runtime;
            return { runtime: {
              id: runtime.id, getURL: (path) => runtime.getURL(path), get lastError() { return runtime.lastError; },
              sendMessage: (message, ...rest) => runtime.sendMessage({ __shyUserScript: true, message }, ...rest.filter((r) => typeof r === "function" || (r && typeof r === "object"))),
              connect: (info) => runtime.connect({ ...(info || {}), name: "shy-us:" + ((info && info.name) || "") }),
            } };
          })();
          const browser = chrome;
        """#
        let text = #"""
        /* Shy: a user script (chrome.userScripts) */
        shy_user_script: {
          const __shyHref = location.href;
          const __shyGlob = (g) => new RegExp("^" + g.replace(/[.+^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*").replace(/\?/g, ".") + "$");
          const __shyIn = \#(json(script["includeGlobs"] ?? [])), __shyOut = \#(json(script["excludeGlobs"] ?? []));
          if ((__shyIn.length && !__shyIn.some((g) => __shyGlob(g).test(__shyHref))) || __shyOut.some((g) => __shyGlob(g).test(__shyHref))) break shy_user_script;
        \#(userWorld ? prelude : "")
        \#(code)
        }
        """#
        let name = "us-" + SHA256.hash(data: Data(text.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined() + ".js"
        let dir = folder.appendingPathComponent("_shy", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: url.path) { try text.write(to: url, atomically: true, encoding: .utf8) }
        return "_shy/" + name
    }

    /// Popups extensions set for their buttons: per tab, or "*" for all.
    static var popups: [String: [String: String]] = [:]
    /// The page an extension's downloads.download goes through: the tab in
    /// front, or another of yours, never a private tab — a download goes
    /// with the sign-ins of the page it's made through, and a private tab's
    /// are its own, whatever the extension may see.
    static func downloadPage(active: Tab?, tabs: [Tab]) -> WKWebView? {
        ([active].compactMap { $0 } + tabs).filter { !$0.shy }.lazy.compactMap(\.built).first
    }

    /// Downloads an extension asked for, by address, until they land; then
    /// the files they became, which are the only ones it may open.
    static var askedDownloads: [URL: String] = [:]
    static var ownDownloads: [String: Set<String>] = [:]

    /// Keep-awake assertions, one per extension that asked.
    static var awake: [String: IOPMAssertionID] = [:]

    /// chrome.privacy and chrome.proxy: what each extension set, kept across
    /// launches as Chrome keeps it. Shy acts on one of them — an
    /// extension turning the browser's own offer to save passwords off,
    /// which is how every password manager asks Chrome to step aside.
    private static func setting(_ api: String, _ details: [String: Any], extension id: String, owner: Extensions) -> Any? {
        let parts = api.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        let name = parts[1]
        var mine = Extensions.settings(for: id)
        switch parts[0] {
        case "setting.set":
            mine[name] = details["value"]
        case "setting.clear":
            mine[name] = nil
        default:
            let value = mine[name] ?? defaultSetting(name, owner: owner)
            return ["value": value ?? NSNull(), "levelOfControl": mine[name] != nil ? "controlled_by_this_extension" : "controllable_by_this_extension"]
        }
        Extensions.setSettings(mine, for: id)
        owner.objectWillChange.send()
        return nil
    }

    private static func defaultSetting(_ name: String, owner: Extensions) -> Any? {
        switch name {
        case "privacy.services.passwordSavingEnabled": return owner.browser?.prefs.savesPasswords ?? true
        case "privacy.network.webRTCIPHandlingPolicy": return "default"
        case "privacy.websites.doNotTrackEnabled", "privacy.websites.adMeasurementEnabled",
             "privacy.websites.fledgeEnabled", "privacy.websites.topicsEnabled",
             "privacy.services.safeBrowsingExtendedReportingEnabled": return false
        case "proxy.settings": return ["mode": "system"]
        default: return true
        }
    }

    /// chrome.browsingData, from what WebKit and Shy keep.
    private static func clear(_ what: [String: Bool], options: [String: Any], browser: Browser) async throws {
        let since = Date(timeIntervalSince1970: (options["since"] as? Double ?? 0) / 1000)
        let origins = (options["origins"] as? [String])?.compactMap { URL(string: $0)?.host() }
        var types = Set<String>()
        let map: [String: [String]] = [
            "cache": [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeFetchCache],
            "cacheStorage": [WKWebsiteDataTypeFetchCache], "appcache": [WKWebsiteDataTypeOfflineWebApplicationCache],
            "cookies": [WKWebsiteDataTypeCookies], "localStorage": [WKWebsiteDataTypeLocalStorage, WKWebsiteDataTypeSessionStorage],
            "indexedDB": [WKWebsiteDataTypeIndexedDBDatabases], "serviceWorkers": [WKWebsiteDataTypeServiceWorkerRegistrations],
            "webSQL": [WKWebsiteDataTypeWebSQLDatabases], "fileSystems": [WKWebsiteDataTypeFileSystem],
        ]
        for (key, on) in what where on { types.formUnion(map[key] ?? []) }
        // The front window's space's store, as its history below is the
        // front window's: Personal's every time cleared Personal's sign-ins
        // from another profile and left that profile's own untouched.
        let store = await MainActor.run { Spaces.store(for: browser.spaceID) }
        if !types.isEmpty {
            if let origins {
                let records = await store.dataRecords(ofTypes: types)
                let hit = records.filter { record in origins.contains { $0 == record.displayName || $0.hasSuffix("." + record.displayName) } }
                await store.removeData(ofTypes: types, for: hit)
            } else {
                await store.removeData(ofTypes: types, modifiedSince: since)
            }
        }
        if what["history"] == true, origins == nil {
            for trace in browser.history.everything() where trace.last >= since { browser.history.forget(trace.key) }
        }
    }

    static func defaultPanel(_ context: WKWebExtensionContext) -> String? {
        (context.webExtension.manifest["side_panel"] as? [String: Any])?["default_path"] as? String
    }

    /// One of the extension's own pages, from the path it gave: resolved
    /// rather than appended, since a path can carry a query (Claude's side
    /// panel names its tab, sidepanel.html?tabId=…), which appended would be
    /// escaped into the file's name. Never anywhere but inside the
    /// extension: a full address given as a "path" is refused.
    static func page(_ path: String, in context: WKWebExtensionContext) -> URL? {
        let base = context.baseURL
        guard let url = URL(string: path.trimmingCharacters(in: CharacterSet(charactersIn: "/")), relativeTo: base)?.absoluteURL,
              url.scheme == base.scheme, url.host == base.host
        else { return nil }
        return url
    }

    /// The extension's button, for one that asked for its panel on a
    /// press (openPanelOnActionClick): its panel up, or down again.
    static func openPanel(_ context: WKWebExtensionContext, owner: Extensions) {
        let id = context.uniqueIdentifier
        guard !panelOff.contains(id), let path = panelPath[id] ?? defaultPanel(context) else { return }
        // Resolved, not appended: a path can carry a query — Claude's names
        // the tab its panel is for, sidepanel.html?tabId=… — which appended
        // would be escaped into the file's name.
        guard let url = ExtensionShims.page(path, in: context) else { return }
        // In the side panel; a tab of its own if the panel can't be made,
        // as before there was a panel to put it in. Beside a private tab
        // this extension may not see, the button does nothing.
        guard let browser = owner.browser else { return }
        if browser.toggleSidePanel(context, url: url) == .noPanel {
            browser.open(url, foreground: true)
        }
    }

    // MARK: - bookmarks, as Chrome shapes them

    private typealias Hit = (node: Bookmark, parent: String, index: Int)

    private static func flat(_ nodes: [Bookmark], parent: String = "1") -> [Hit] {
        nodes.enumerated().flatMap { index, n -> [Hit] in
            [(n, parent, index)] + flat(n.children ?? [], parent: n.id.uuidString)
        }
    }

    private static func find(_ key: String, in nodes: [Bookmark]) -> Hit? {
        flat(nodes).first { $0.node.id.uuidString == key }
    }

    private static func node(_ n: Bookmark, parent: String, index: Int, deep: Bool) -> [String: Any] {
        var out: [String: Any] = ["id": n.id.uuidString, "parentId": parent, "index": index, "title": n.title,
                                  "dateAdded": 0, "syncing": false]
        if let url = n.url { out["url"] = url }
        if n.isFolder {
            out["dateGroupModified"] = 0
            if deep {
                out["children"] = (n.children ?? []).enumerated().map { node($1, parent: n.id.uuidString, index: $0, deep: true) }
            }
        }
        return out
    }

    private static func bar(_ roots: [Bookmark], deep: Bool = true) -> [String: Any] {
        var out: [String: Any] = ["id": "1", "parentId": "0", "index": 0, "title": "Bookmarks", "dateAdded": 0,
                                  "folderType": "bookmarks-bar", "syncing": false]
        if deep { out["children"] = roots.enumerated().map { node($1, parent: "1", index: $0, deep: true) } }
        return out
    }

    private static func root(_ roots: [Bookmark]) -> [String: Any] {
        ["id": "0", "title": "", "dateAdded": 0, "syncing": false, "children": [bar(roots)]]
    }

    private static func visit(_ trace: History.Trace) -> [String: Any] {
        ["id": trace.key, "url": trace.url.absoluteString, "title": trace.title,
         "lastVisitTime": trace.last.timeIntervalSince1970 * 1000, "visitCount": trace.count, "typedCount": 0]
    }
}

/// chrome.identity.launchWebAuthFlow: a tab for the provider's sign-in, and
/// the moment it tries to go to https://<id>.chromiumapp.org/, that address
/// is the answer and the tab goes. Browser asks `intercept` about every
/// navigation; nothing is ever loaded from chromiumapp.org.
@MainActor
enum ExtensionAuth {
    private static var waiting: [String: (tab: Tab.ID, finish: (Result<URL, Error>) -> Void)] = [:]
    /// One per flow: whether its tab is still somewhere.
    private static var watches: [String: Timer] = [:]

    struct Declined: LocalizedError {
        var errorDescription: String? { "The user did not approve access." }
    }

    static func run(_ url: URL, extension id: String, browser: Browser) async throws -> URL {
        if #available(macOS 15.4, *) { try Extensions.mayOpen(url) }
        return try await withCheckedThrowingContinuation { continuation in
            waiting[id]?.finish(.failure(Declined()))
            let tab = browser.open(url, foreground: true)
            waiting[id] = (tab.id, { result in continuation.resume(with: result) })
            // Closing the tab is saying no. Moved to another window, or to
            // a space not on screen, it is still there.
            watches[id]?.invalidate()
            let started = Date()
            watches[id] = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                MainActor.assumeIsolated {
                    guard let entry = waiting[id], entry.tab == tab.id else {
                        watches.removeValue(forKey: id)?.invalidate()
                        return
                    }
                    // So is ten minutes with nobody finishing: its address is
                    // no longer watched for.
                    guard !exists(entry.tab) || Date().timeIntervalSince(started) > 600 else { return }
                    waiting[id] = nil
                    watches.removeValue(forKey: id)?.invalidate()
                    entry.finish(.failure(Declined()))
                }
            }
        }
    }

    /// A non-interactive flow, as Chrome runs one: the provider's page loads
    /// in a view that is never on screen, signed in as the tabs are, and the
    /// flow ends the moment it heads for this extension's own
    /// https://<id>.chromiumapp.org/ — or fails, without a word to anyone,
    /// once the page has loaded (unless the extension asked to wait) or the
    /// time is up. Claude in Chrome restores its sign-in this way each time
    /// the browser starts; until now it got a tab in front instead.
    ///
    /// What it allows, no more than a tab opened behind would (which any
    /// extension may do, with no permission): an extension with "identity"
    /// has an http(s) page load out of sight, with the cookies of the space
    /// in front, for at most a minute. It learns only the address it is sent
    /// to on its own chromiumapp.org, never the page. The page gets no other
    /// extension, no popup, dialog, download or app launch, and no other
    /// scheme. One flow per extension at a time; a new one ends the last.
    static func quietly(_ url: URL, extension id: String, abortOnLoad: Bool, timeout: TimeInterval?) async throws -> URL {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
            throw Quiet.failure("Authorization page could not be loaded.")
        }
        let limit = min(max(timeout ?? Quiet.longest, 0.5), Quiet.longest)
        return try await withCheckedThrowingContinuation { continuation in
            quiet[id]?.end(.failure(Quiet.failure("User interaction required.")))
            let flow = Quiet(extensionID: id, abortOnLoad: abortOnLoad) { result in
                quiet[id] = nil
                continuation.resume(with: result)
            }
            quiet[id] = flow
            flow.start(url, limit: limit)
        }
    }

    private static var quiet: [String: Quiet] = [:]

    /// The view and its watcher for one non-interactive flow.
    @MainActor
    final class Quiet: NSObject, WKNavigationDelegate, WKUIDelegate {
        /// The longest a flow may run out of sight, whatever it asks.
        static let longest: TimeInterval = 60

        static func failure(_ why: String) -> Error {
            NSError(domain: "Shy", code: 1, userInfo: [NSLocalizedDescriptionKey: why])
        }

        let extensionID: String
        let abortOnLoad: Bool
        private var finish: ((Result<URL, Error>) -> Void)?
        private var view: WKWebView?
        private var timer: Timer?

        init(extensionID: String, abortOnLoad: Bool, finish: @escaping (Result<URL, Error>) -> Void) {
            self.extensionID = extensionID.lowercased()
            self.abortOnLoad = abortOnLoad
            self.finish = finish
        }

        func start(_ url: URL, limit: TimeInterval) {
            let config = WKWebViewConfiguration()
            // The front space's sign-ins, as the tab an interactive flow
            // opens would have; no extension's scripts, and the same user
            // agent as every other view (see Web.userAgentName).
            config.websiteDataStore = Spaces.store(for: Spaces.current)
            config.processPool = Web.pool
            config.applicationNameForUserAgent = Web.userAgentName
            config.preferences.javaScriptCanOpenWindowsAutomatically = false
            // No sound or video from nowhere: nobody can click here.
            config.mediaTypesRequiringUserActionForPlayback = .all
            // WebKit's own passkey operation is never opened (see Passkeys.swift):
            // the page is told there are none, as with passkeys off.
            config.userContentController.addUserScript(
                WKUserScript(source: FormRelay.withoutPasskeys, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page)
            )
            // In no window, ever: there is nothing to show.
            let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
            view.navigationDelegate = self
            // Without a UI delegate WebKit puts up its own question for the
            // camera, the microphone or the screen; here every one is no.
            view.uiDelegate = self
            Muter.set(true, on: view)
            self.view = view
            timer = Timer.scheduledTimer(withTimeInterval: limit, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.end(.failure(Quiet.failure("User interaction required."))) }
            }
            view.load(URLRequest(url: url))
        }

        /// The extension's own redirect address, and nobody else's.
        private func answer(_ url: URL?) -> Bool {
            guard let url, url.scheme?.lowercased() == "https",
                  url.host()?.lowercased() == extensionID + ".chromiumapp.org" else { return false }
            end(.success(url))
            return true
        }

        /// Any other chromiumapp.org address — another extension's, or this
        /// one's over http — never loads: what it carries (a code, a token)
        /// would go out over the network instead of to nobody.
        private static func chromiumapp(_ url: URL?) -> Bool {
            guard let host = url?.host()?.lowercased() else { return false }
            let bare = host.hasSuffix(".") ? String(host.dropLast()) : host
            return bare == "chromiumapp.org" || bare.hasSuffix(".chromiumapp.org")
        }

        func end(_ result: Result<URL, Error>) {
            guard let finish else { return }
            self.finish = nil
            timer?.invalidate(); timer = nil
            if let view {
                view.navigationDelegate = nil
                view.uiDelegate = nil
                view.stopLoading()
            }
            view = nil
            finish(result)
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            let main = action.targetFrame?.isMainFrame ?? true
            if main, answer(action.request.url) { return decisionHandler(.cancel) }
            if Self.chromiumapp(action.request.url) {
                decisionHandler(.cancel)
                if main { end(.failure(Quiet.failure("Authorization page could not be loaded."))) }
                return
            }
            let scheme = action.request.url?.scheme?.lowercased() ?? ""
            let fine = main ? ["http", "https"] : ["http", "https", "about", "data", "blob"]
            guard !action.shouldPerformDownload, action.targetFrame != nil, fine.contains(scheme) else {
                return decisionHandler(.cancel)
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                     decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
            decisionHandler(response.canShowMIMEType ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
            if answer(webView.url) { webView.stopLoading(); return }
            if Self.chromiumapp(webView.url) {
                webView.stopLoading()
                end(.failure(Quiet.failure("Authorization page could not be loaded.")))
            }
        }

        // A site asking who you are, or holding out a client certificate,
        // gets no answer here: that is interaction. Only the certificate
        // check goes on as usual (and fails the load if it fails).
        func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
                     completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
                completionHandler(.performDefaultHandling, nil)
            } else {
                completionHandler(.rejectProtectionSpace, nil)
            }
        }

        // MARK: nothing to show, nothing to ask

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            completionHandler()
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            completionHandler(false)
        }

        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
            completionHandler(nil)
        }

        func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                     initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
            completionHandler(nil)
        }

        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(.deny)
        }

        @objc(_webView:requestDisplayCapturePermissionForOrigin:initiatedByFrame:withSystemAudio:decisionHandler:)
        func displayCapture(_ web: WKWebView, origin: WKSecurityOrigin, frame: WKFrameInfo, systemAudio: Bool,
                            decisionHandler: @escaping (Int) -> Void) {
            decisionHandler(0)
        }

        @objc(_webView:requestGeolocationPermissionForOrigin:initiatedByFrame:decisionHandler:)
        func location(_ webView: WKWebView, origin: WKSecurityOrigin, frame: WKFrameInfo,
                      decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(.deny)
        }

        @objc(_webView:requestNotificationPermissionForSecurityOrigin:decisionHandler:)
        func notifications(_ webView: WKWebView, origin: WKSecurityOrigin, decisionHandler: @escaping (Bool) -> Void) {
            decisionHandler(false)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // A page meant to be seen: Chrome's non-interactive flow ends
            // here unless the extension asked to wait for a script to move on.
            if abortOnLoad { end(.failure(Quiet.failure("User interaction required."))) }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            failed(error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            failed(error)
        }

        private func failed(_ error: Error) {
            // A navigation cancelled here, or replaced by the page's next one,
            // isn't the page failing.
            let error = error as NSError
            if error.domain == NSURLErrorDomain, error.code == NSURLErrorCancelled { return }
            if error.domain == "WebKitErrorDomain", error.code == 102 { return }
            end(.failure(Quiet.failure("Authorization page could not be loaded.")))
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            end(.failure(Quiet.failure("Authorization page could not be loaded.")))
        }
    }

    private static func exists(_ id: Tab.ID) -> Bool {
        Browsers.all.contains { browser in
            browser.tabs.contains { $0.id == id } || browser.parked.values.contains { $0.tabs.contains { $0.id == id } }
        }
    }

    /// True when the address is an extension's OAuth redirect arriving in
    /// the tab that began the sign-in, which is then handed over and never
    /// loaded. Any page can go to an address shaped like one of these, and
    /// what it carries would be delivered as the flow's answer: only the
    /// tab the flow was started in may finish it, or a window that tab's
    /// page opened, since some providers finish the sign-in in a popup.
    static func intercept(_ url: URL, browser: Browser, from webView: WKWebView) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host()?.lowercased(), host.hasSuffix(".chromiumapp.org") else { return false }
        let id = String(host.dropLast(".chromiumapp.org".count))
        guard let entry = waiting[id], let from = browser.tab(for: webView),
              from.id == entry.tab || from.opener == entry.tab
        else { return false }
        waiting.removeValue(forKey: id)
        entry.finish(.success(url))
        // The popup, when the answer came in one, goes with the flow's tab:
        // left behind, it would hold a redirect that never loads.
        watches.removeValue(forKey: id)?.invalidate()
        if from.id != entry.tab { browser.close(from) }
        // The flow's tab, in whichever window it is now.
        for home in Browsers.all {
            if let tab = home.tabs.first(where: { $0.id == entry.tab }) { home.close(tab) }
        }
        return true
    }

    /// The same redirect with no launchWebAuthFlow waiting for it. Some
    /// extensions open the provider's page with tabs.create and watch that
    /// tab's address until it reaches their chromiumapp.org one, then close
    /// the tab (Figma's does). In Chrome the navigation fails onto an error
    /// page that still carries the address, and tabs.onUpdated reports it;
    /// in WebKit a failed load never commits, so nothing would. The tab takes
    /// the address without loading anything, for an installed extension
    /// that asked for identity. What each extension sees of it is WebKit's
    /// call, as for any address: tabs or host access, as in Chrome. Left
    /// open, the tab says what Chrome's would.
    static func handOver(_ url: URL, mainFrame: Bool, browser: Browser, from webView: WKWebView) -> Bool {
        guard mainFrame, url.scheme?.lowercased() == "https", let host = url.host()?.lowercased(),
              host.hasSuffix(".chromiumapp.org") else { return false }
        let id = String(host.dropLast(".chromiumapp.org".count))
        guard #available(macOS 15.4, *), let context = Extensions.owner(of: webView.configuration.webExtensionController)?.contexts[id],
              ExtensionShims.allowed(id, context: context).contains("identity"),
              let tab = browser.tab(for: webView)
        else { return false }
        tab.hold(url)
        Task { @MainActor [weak tab] in
            try? await Task.sleep(for: .seconds(4))
            guard let tab, tab.held == url else { return }
            tab.failure = "No site at that address."
        }
        return true
    }
}
