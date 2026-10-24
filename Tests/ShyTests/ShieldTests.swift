import WebKit
import XCTest
@testable import Shy

@MainActor
final class ShieldTests: XCTestCase {
    /// A private page is reached by no profile's pause; a profile's pause
    /// and its autoplay stay its own.
    func testPausesAndAutoplayAreThePagesProfilesOnly() {
        let host = "pause-\(UUID().uuidString.prefix(8)).example"
        let other = UUID()
        defer {
            Shield.shared.pause(host, false, in: Profile.personalID)
            Autoplay.set(false, for: host, in: Profile.personalID)
            SiteMemory.forget(other)
        }
        Shield.shared.pause(host, true, in: Profile.personalID)
        XCTAssertTrue(Shield.shared.isPaused(on: host, in: Profile.personalID))
        XCTAssertFalse(Shield.shared.isPaused(on: host, in: nil))
        XCTAssertFalse(Shield.shared.isPaused(on: host, in: other))
        Autoplay.set(true, for: host, in: other)
        XCTAssertTrue(Autoplay.allowed(host, in: other))
        XCTAssertFalse(Autoplay.allowed(host, in: Profile.personalID))
        SiteMemory.forget(other)
        XCTAssertFalse(Autoplay.allowed(host, in: other))
    }

    func testNetworkFilterMatchesOnlyTheListedHostAndItsSubdomains() throws {
        let pattern = try NSRegularExpression(pattern: Shield.networkFilter(for: "segment.com"))
        for url in ["https://segment.com/track", "http://segment.com/track",
                    "https://cdn.segment.com/track", "https://a.b.segment.com/track",
                    "https://segment.com:8443/track", "https://segment.com/",
                    "https://segment.com/?event=test", "https://segment.com/#event"] {
            XCTAssertNotNil(pattern.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)), url)
        }
        for url in ["https://segment.company/app.js", "https://cdn.segment.company/app.js",
                    "https://segment.com.example/app.js", "https://segment.com-example/app.js",
                    "https://notsegment.com/app.js", "https://example.com/segment.com/track",
                    "https://segmentXcom/app.js", "ftp://segment.com/track"] {
            XCTAssertNil(pattern.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)), url)
        }
    }

    func testNetworkFilterCompilesInWebKit() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("shield-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = try XCTUnwrap(WKContentRuleListStore(url: folder))
        let rules: [[String: Any]] = [[
            "trigger": ["url-filter": Shield.networkFilter(for: "segment.com"), "load-type": ["third-party"]],
            "action": ["type": "block"],
        ]]
        let data = try JSONSerialization.data(withJSONObject: rules)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        let list = try await store.compileContentRuleList(forIdentifier: "fixture", encodedContentRuleList: json)
        XCTAssertNotNil(list)
    }
}
