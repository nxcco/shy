import AppKit
import WebKit
import XCTest
@testable import Shy

/// Each profile's extensions keep their storage apart (Extensions.of, H2 in
/// the audit): the same extension, in two profiles' controllers at once,
/// under the same id and origin as the app gives it, never reads what the
/// other profile's wrote, and deleting one profile's leaves the other's.
@available(macOS 15.4, *)
@MainActor
final class ExtensionProfileStorageTests: XCTestCase {
    override class func setUp() {
        setenv("SHY_PROBE", "profile-storage-\(getpid())", 1)
        super.setUp()
    }

    private func fixture() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("profile-storage-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let manifest: [String: Any] = [
            "manifest_version": 3, "name": "Profile storage", "version": "1",
            "permissions": ["storage"],
            "host_permissions": ["https://example.com/*"],
            "content_scripts": [["matches": ["https://example.com/*"], "js": ["content.js"]]],
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(to: folder.appendingPathComponent("manifest.json"))
        let script = """
            (async () => {
              try {
                const q = new URLSearchParams(location.search);
                if (q.has('set')) await browser.storage.local.set({ v: q.get('set') });
                const r = await browser.storage.local.get('v');
                document.documentElement.dataset.got = r.v ?? 'none';
              } catch (e) { document.documentElement.dataset.got = 'error: ' + e; }
            })();
            """
        try Data(script.utf8).write(to: folder.appendingPathComponent("content.js"))
        return folder
    }

    private func controller(_ id: UUID) -> WKWebExtensionController {
        let configuration = WKWebExtensionController.Configuration(identifier: id)
        configuration.defaultWebsiteDataStore = .nonPersistent()
        return WKWebExtensionController(configuration: configuration)
    }

    private func got(_ controller: WKWebExtensionController, _ query: String) async throws -> String {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.webExtensionController = controller
        let web = WKWebView(frame: .zero, configuration: config)
        web.loadHTMLString("<html><body>page</body></html>", baseURL: URL(string: "https://example.com/\(query)"))
        for _ in 0..<100 {
            if let value = try? await web.evaluateJavaScript("document.documentElement.dataset.got || ''") as? String, !value.isEmpty {
                return value
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        return "timed out"
    }

    private func load(_ ext: WKWebExtension, into controller: WKWebExtensionController) throws -> WKWebExtensionContext {
        let context = WKWebExtensionContext(for: ext)
        // As the app does (Extensions.swift): the same id and origin every launch, in every profile.
        context.uniqueIdentifier = "profilestorage"
        context.baseURL = URL(string: "webkit-extension://profilestorage/")!
        context.setPermissionStatus(.grantedExplicitly, for: try WKWebExtension.MatchPattern(string: "https://example.com/*"))
        context.setPermissionStatus(.grantedExplicitly, for: .storage)
        // Its pages here use a store that keeps nothing, which WebKit counts as private.
        context.hasAccessToPrivateData = true
        try controller.load(context)
        return context
    }

    private let kinds = Set<WKWebExtension.DataType>([.local, .session, .synchronized])

    /// What deleting a profile does to its extensions' storage: listed and
    /// removed once they are unloaded, as WebKit lists none while loaded.
    private func wipe(_ controller: WKWebExtensionController) async {
        await controller.removeData(ofTypes: kinds, from: await controller.dataRecords(ofTypes: kinds))
    }

    func testTwoProfilesKeepTheSameExtensionsStorageApart() async throws {
        _ = NSApplication.shared
        let folder = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let work = controller(UUID()), personal = controller(UUID())
        // One WKWebExtension, a context of its own in each controller.
        let ext = try await WKWebExtension(resourceBaseURL: folder)
        let inWork = try load(ext, into: work)
        let inPersonal = try load(ext, into: personal)

        do { let value = try await got(work, "?set=WORK"); XCTAssertEqual(value, "WORK") }
        do { let value = try await got(personal, ""); XCTAssertEqual(value, "none", "personal must not see work's storage") }
        do { let value = try await got(personal, "?set=PERSONAL"); XCTAssertEqual(value, "PERSONAL") }
        do { let value = try await got(work, ""); XCTAssertEqual(value, "WORK", "work keeps its own") }

        // Deleting a profile: its controller's extension data goes, the other's stays.
        try work.unload(inWork)
        _ = try load(ext, into: work)
        do { let value = try await got(work, ""); XCTAssertEqual(value, "WORK", "kept across an unload and load, by its id") }
        try work.unload(work.extensionContexts.first!)
        let records = await work.dataRecords(ofTypes: kinds)
        XCTAssertFalse(records.isEmpty, "there was something to wipe")
        await wipe(work)
        _ = try load(ext, into: work)
        do { let value = try await got(work, ""); XCTAssertEqual(value, "none", "a wiped profile's storage is gone") }
        do { let value = try await got(personal, ""); XCTAssertEqual(value, "PERSONAL", "the other profile's stays") }

        try personal.unload(inPersonal)
        await wipe(personal)
    }
}
