import Foundation
import WebKit
import XCTest
@testable import Shy

/// What the shim answers from what the browser keeps, where an extension's
/// odd arguments used to stop the app or reach further than it asked.
@available(macOS 15.4, *)
@MainActor
final class ExtensionDataTests: XCTestCase {
    override class func setUp() {
        setenv("SHY_PROBE", "extension-data-\(getpid())", 1)
        super.setUp()
    }

    private func fixture() async throws -> (URL, WKWebExtensionContext) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("data-ext-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let manifest: [String: Any] = [
            "manifest_version": 3, "name": "Data", "version": "1",
            "permissions": ["bookmarks", "history", "sessions", "browsingData"],
        ]
        try JSONSerialization.data(withJSONObject: manifest).write(to: folder.appendingPathComponent("manifest.json"))
        return (folder, WKWebExtensionContext(for: try await WKWebExtension(resourceBaseURL: folder)))
    }

    private func ask(_ api: String, _ args: [Any], _ context: WKWebExtensionContext) async throws -> [String: Any]? {
        try await ExtensionShims.answer(["api": api, "args": args], from: context, owner: Extensions.shared) as? [String: Any]
    }

    func testNegativeCountsAnswerNothingRatherThanStopping() async throws {
        let (folder, context) = try await fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let browser = Browser(record: WindowRecord())
        Browsers.register(browser)
        defer { browser.closeAll() }

        let recent = try await ask("bookmarks.getRecent", [-1], context)
        XCTAssertEqual((recent?["value"] as? [Any])?.count, 0, "\(String(describing: recent))")
        let history = try await ask("history.search", [["text": "", "maxResults": -5]], context)
        XCTAssertEqual((history?["value"] as? [Any])?.count, 0, "\(String(describing: history))")
        let closed = try await ask("sessions.getRecentlyClosed", [["maxResults": -1]], context)
        XCTAssertEqual((closed?["value"] as? [Any])?.count, 0, "\(String(describing: closed))")
    }

    func testSitesAndADateTogetherAreRefused() async throws {
        let (folder, context) = try await fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let browser = Browser(record: WindowRecord())
        Browsers.register(browser)
        defer { browser.closeAll() }

        let some = try await ask("browsingData.remove", [["origins": ["https://example.com"], "since": 1000], ["cookies": true]], context)
        XCTAssertNotNil(some?["error"], "\(String(describing: some))")
        let allBut = try await ask("browsingData.remove", [["excludeOrigins": ["https://example.com"], "since": 1000], ["cookies": true]], context)
        XCTAssertNotNil(allBut?["error"], "\(String(describing: allBut))")
    }

    func testReusedScriptFileIsMadeFreshAgain() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("script-ext-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let path = try ExtensionShims.scriptingFile("() => 1", arguments: [], in: folder)
        let file = folder.appendingPathComponent(path)
        let old = Date().addingTimeInterval(-600)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: file.path)
        XCTAssertEqual(try ExtensionShims.scriptingFile("() => 1", arguments: [], in: folder), path)
        let date = try XCTUnwrap(file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        XCTAssertGreaterThan(date.timeIntervalSince(old), 500)
        // Another call's cleanup leaves it, being new again.
        _ = try ExtensionShims.scriptingFile("() => 2", arguments: [], in: folder)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testUserScriptsMessageOnlyWhereTheirWorldAllows() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("us-ext-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("_shy"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let script: [String: Any] = ["id": "a", "js": [["code": "1"]]]
        let text = { (path: String) in try String(contentsOf: folder.appendingPathComponent(path), encoding: .utf8) }

        XCTAssertFalse(try text(ExtensionShims.userScriptFile(script, in: folder)).contains("sendMessage"))
        let worlds: [[String: Any]] = [["messaging": true]]
        try JSONSerialization.data(withJSONObject: worlds).write(to: folder.appendingPathComponent("_shy/worlds.json"))
        XCTAssertTrue(try text(ExtensionShims.userScriptFile(script, in: folder)).contains("sendMessage"))
    }

    func testOlderDownloadListsReadWithoutNumbersOrProfiles() throws {
        let json = #"[{"name":"a.pdf","from":"example.com","path":"/tmp/a.pdf","date":0}]"#
        let keep = try XCTUnwrap(JSONDecoder().decode([Keep].self, from: Data(json.utf8)).first)
        XCTAssertEqual(keep.number, 0)
        XCTAssertNil(keep.profile)
        // One from before profiles were kept is Personal's alone.
        XCTAssertTrue(keep.seen(by: Profile.personalID))
        XCTAssertFalse(keep.seen(by: UUID()))
        var mine = keep
        let other = UUID()
        mine.profile = other
        XCTAssertTrue(mine.seen(by: other))
        XCTAssertFalse(mine.seen(by: Profile.personalID))
    }
}
