import XCTest
@testable import Shy

/// A declarativeNetRequest redirect to an extension's own page (Norma's
/// block page): the target WebKit hands over, and who may go there.
final class ExtensionRuleRedirectTests: XCTestCase {
    private let base = "chrome-extension://offmcbeojiklcpoccgcjapoofafkhjje"
    private let manifest: [String: Any] = [
        "manifest_version": 3,
        "web_accessible_resources": [["resources": ["blocked.html"], "matches": ["<all_urls>"]]],
    ]

    func testEscapedFragmentAndQueryComeBackAsChromeReadsThem() {
        func target(_ path: String) -> String { ExtensionRedirectPolicy.ruleTarget(URL(string: base + path)!).absoluteString }
        XCTAssertEqual(target("/blocked.html%23instagram.com"), base + "/blocked.html#instagram.com")
        XCTAssertEqual(target("/blocked.html%3Fsite=x%23top"), base + "/blocked.html?site=x#top")
        XCTAssertEqual(target("/blocked.html%23a%3Fb"), base + "/blocked.html#a%3Fb")
        XCTAssertEqual(target("/blocked.html"), base + "/blocked.html")
        // Already a query or fragment: left alone.
        XCTAssertEqual(target("/blocked.html?x=%23"), base + "/blocked.html?x=%23")
    }

    func testRuleRedirectReachesOnlyExposedFiles() {
        let blocked = ExtensionRedirectPolicy.ruleTarget(URL(string: base + "/blocked.html%23instagram.com")!)
        let https = URL(string: "https://www.instagram.com/")!
        let http = URL(string: "http://example.com/")!
        XCTAssertTrue(ExtensionRedirectPolicy.allows(target: blocked, sourceOrigin: https, manifest: manifest, fromRule: true))
        XCTAssertTrue(ExtensionRedirectPolicy.allows(target: blocked, sourceOrigin: http, manifest: manifest, fromRule: true))
        // A site's own return to an extension page stays HTTPS only.
        XCTAssertFalse(ExtensionRedirectPolicy.allows(target: blocked, sourceOrigin: http, manifest: manifest))
        // A file the extension doesn't expose, or a way out of its folder.
        for path in ["/options.html", "/blocked.html%2F..%2Fsecret.html", "/../blocked.html"] {
            let other = ExtensionRedirectPolicy.ruleTarget(URL(string: base + path)!)
            XCTAssertFalse(ExtensionRedirectPolicy.allows(target: other, sourceOrigin: https, manifest: manifest, fromRule: true), path)
        }
        // Exposed to https sites only: not to an http one, even by a rule.
        let httpsOnly: [String: Any] = [
            "manifest_version": 3,
            "web_accessible_resources": [["resources": ["blocked.html"], "matches": ["https://*/*"]]],
        ]
        XCTAssertTrue(ExtensionRedirectPolicy.allows(target: blocked, sourceOrigin: https, manifest: httpsOnly, fromRule: true))
        XCTAssertFalse(ExtensionRedirectPolicy.allows(target: blocked, sourceOrigin: http, manifest: httpsOnly, fromRule: true))
    }

    /// The scheme of a web_accessible_resources origin is matched as
    /// written: an http pattern never lets an https site's own return in,
    /// and "*" covers both for a rule's redirect.
    func testOriginSchemesMatchAsWritten() {
        let blocked = URL(string: base + "/blocked.html")!
        let https = URL(string: "https://example.com/")!
        let http = URL(string: "http://example.com/")!
        func exposed(_ match: String) -> [String: Any] {
            ["manifest_version": 3, "web_accessible_resources": [["resources": ["blocked.html"], "matches": [match]]]]
        }
        XCTAssertFalse(ExtensionRedirectPolicy.allows(target: blocked, sourceOrigin: https, manifest: exposed("http://example.com/*")))
        XCTAssertFalse(ExtensionRedirectPolicy.allows(target: blocked, sourceOrigin: https, manifest: exposed("http://example.com/*"), fromRule: true))
        XCTAssertTrue(ExtensionRedirectPolicy.allows(target: blocked, sourceOrigin: http, manifest: exposed("http://example.com/*"), fromRule: true))
        XCTAssertTrue(ExtensionRedirectPolicy.allows(target: blocked, sourceOrigin: http, manifest: exposed("*://example.com/*"), fromRule: true))
        XCTAssertFalse(ExtensionRedirectPolicy.allows(target: blocked, sourceOrigin: http, manifest: exposed("*://example.com/*")))
        // Never a file: or other scheme as the site.
        for odd in ["file:///etc/", "data:text/html,x", "javascript:x"] {
            XCTAssertFalse(ExtensionRedirectPolicy.allows(target: blocked, sourceOrigin: URL(string: odd)!, manifest: exposed("<all_urls>"), fromRule: true), odd)
        }
        // Only an extension page is a target.
        for odd in ["javascript:alert(1)", "data:text/html,x", "file:///etc/hosts", "https://example.com/blocked.html"] {
            XCTAssertFalse(ExtensionRedirectPolicy.allows(target: URL(string: odd)!, sourceOrigin: https, manifest: exposed("<all_urls>"), fromRule: true), odd)
        }
    }

    /// A resource pattern is the whole path, `*` crossing folders, and a
    /// long path a page made up is answered at once rather than in seconds.
    func testResourcePatternsMatchWholePathsQuickly() {
        let https = URL(string: "https://example.com/")!
        func exposed(_ resource: String) -> [String: Any] {
            ["manifest_version": 3, "web_accessible_resources": [["resources": [resource], "matches": ["<all_urls>"]]]]
        }
        func allows(_ path: String, _ resource: String) -> Bool {
            ExtensionRedirectPolicy.allows(target: URL(string: base + path)!, sourceOrigin: https, manifest: exposed(resource))
        }
        XCTAssertTrue(allows("/a/icons/b/icons/c.png", "*/icons/*/icons/*.png"))
        XCTAssertTrue(allows("/icons/x/y/z.png", "icons/*.png"))
        XCTAssertTrue(allows("/blocked.html", "/blocked.html"))
        XCTAssertFalse(allows("/icons/z.png.html", "icons/*.png"))
        XCTAssertFalse(allows("/x/icons/z.png", "icons/*.png"))
        XCTAssertFalse(allows("/a.b", "a?b"))

        let long = "/" + String(repeating: "icons/", count: 1400) + "x.pn"
        let started = Date()
        XCTAssertFalse(allows(long, "*/icons/*/icons/*.png"))
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
    }
}
