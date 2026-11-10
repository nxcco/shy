import AppKit
import SwiftUI
import WebKit
import Combine

// Updates from the Chrome Web Store, checked and asked about again when they want more.
extension Extensions {
    /// Once a day, the store is asked whether anything installed from it has
    /// a newer version; if so it is fetched, checked and swapped in. One that
    /// asks for more than it was installed with is asked about first.
    func checkForUpdates() {
        // A browser left open for days must keep checking, even if today's check is not due.
        if updateClock == nil {
            updateClock = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkForUpdates() }
            }
            updateClock?.tolerance = 60 * 5
        }
        // Each profile's own: one stamp for all of them let only the first
        // profile to check ever update. Stamped in update(_:) once the store
        // has answered, so a launch with no network tries again within the hour
        // rather than a day later.
        let last = Store.settings.object(forKey: key(Extensions.checkedKey)) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 60 * 60 * 20 else { return }
        let fromStore = installed.filter(\.fromStore)
        // Nothing to ask the store about is a check done, today.
        if fromStore.isEmpty { Store.settings.set(Date(), forKey: key(Extensions.checkedKey)) }
        for item in fromStore {
            Task { await update(item) }
        }
    }

    static let checkedKey = "extensions.checked"

    func update(_ item: Installed) async {
        // Permission approval can wait past the next check; its staging folder must stay its own.
        guard updating.insert(item.id).inserted else { return }
        defer { updating.remove(item.id) }
        var parts = URLComponents(string: "https://clients2.google.com/service/update2/crx")!
        parts.queryItems = [
            URLQueryItem(name: "response", value: "updatecheck"),
            URLQueryItem(name: "prodversion", value: Crx.chromeVersion),
            URLQueryItem(name: "acceptformat", value: "crx3"),
            URLQueryItem(name: "x", value: "id=\(item.id)&v=\(item.version)&uc"),
        ]
        guard let url = parts.url,
              let (data, _) = try? await Crx.session.data(from: url) else { return }
        Store.settings.set(Date(), forKey: key(Extensions.checkedKey))
        guard let xml = String(data: data, encoding: .utf8),
              // The answer is the <updatecheck> element alone: status="ok"
              // with a version when there is a newer one, "noupdate" when
              // not. Read across the whole reply, the first version="" is
              // the XML declaration's "1.0", and status="ok" is on <app>
              // either way — which took every reply for an update.
              let check = xml.range(of: #"<updatecheck\b[^>]*>"#, options: .regularExpression)
                .map({ String(xml[$0]) }),
              check.contains("status=\"ok\""),
              let version = check.range(of: #"\bversion="([^"]+)""#, options: .regularExpression)
                .map({ String(check[$0].dropFirst(9).dropLast()) }),
              Extensions.newer(version, than: item.version)
        else { return }
        do {
            let zip = try Crx.verifiedZip(try await Crx.fetch(item.id), id: item.id)
            let staged = stagingFolder(for: item.id)
            defer { try? FileManager.default.removeItem(at: staged) }
            try Crx.unpack(zip, into: staged)
            try ExtensionShims.prepare(staged, fresh: true)
            let found = try await WKWebExtension(resourceBaseURL: staged)
            // What is installed is the package's own version, not the one the
            // reply named: an older package served under a newer number would
            // otherwise roll the extension back.
            guard let packaged = found.version, Extensions.newer(packaged, than: item.version) else { return }
            guard let current = installed.first(where: { $0.id == item.id }), current.fromStore,
                  current.version == item.version else { return }
            // Everything it could do, sites included, against what it was
            // allowed when it was added or last asked about.
            let wants = Set(Extensions.grants(found, in: staged))
            if !wants.isSubset(of: Set(current.permissions)) {
                guard await ask(install: "An update to \(item.name)", wants: Extensions.describe(found, in: staged), icon: found.icon(for: CGSize(width: 64, height: 64)), updating: true) else {
                    return
                }
            }
            guard let index = installed.firstIndex(where: { $0.id == item.id }), installed[index].fromStore,
                  installed[index].version == item.version,
                  installed[index].permissions == current.permissions else { return }
            let target = folder(for: item.id)
            try ExtensionFiles.replace(staged, at: target)
            unload(item.id)
            errors[item.id] = nil
            workersChanged()
            installed[index].version = packaged
            installed[index].permissions = wants.sorted()
            save()
            if installed[index].enabled { await load(installed[index]) }
        } catch {
            NSLog("Extensions: update of %@ failed: %@", item.id, error.localizedDescription)
        }
    }

    /// The page the manifest names for the button, when WebKit hasn't said.
    static func popupURL(for context: WKWebExtensionContext) -> URL? {
        let manifest = context.webExtension.manifest
        let action = (manifest["action"] ?? manifest["browser_action"]) as? [String: Any]
        guard let path = action?["default_popup"] as? String, !path.isEmpty else { return nil }
        // Relative to the extension, and keeping a query it may carry.
        return URL(string: path, relativeTo: context.baseURL)?.absoluteURL
    }
}
