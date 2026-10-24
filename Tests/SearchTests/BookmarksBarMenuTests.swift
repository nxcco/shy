import AppKit
import XCTest
@testable import Search

/// What the bookmarks bar's right-click menu does, without the menu: a
/// real one is an NSMenu that a hidden run can't open (#439).
@MainActor
final class BookmarksBarMenuTests: XCTestCase {
    override class func setUp() {
        setenv("SEARCH_PROBE", "bookmarks-bar-menu-\(getpid())", 1)
        super.setUp()
    }

    func testOpenInPrivateTabIsPrivateAndInFront() {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        defer { browser.closeAll() }
        let before = browser.tabs.count
        browser.openShy(URL(string: "https://example.com/a")!)
        XCTAssertEqual(browser.tabs.count, before + 1)
        let tab = try? XCTUnwrap(browser.active)
        XCTAssertEqual(tab?.shy, true, "Open in Private Tab keeps nothing")
        XCTAssertEqual(browser.editing, false)
    }

    func testOpenAllInTabGroupNamesTheGroupAfterTheFolder() {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        defer { browser.closeAll() }

        let urls = (1...3).map { URL(string: "https://example.com/\($0)")! }
        browser.openInTabGroup(urls, named: "Reading")
        let group = try? XCTUnwrap(browser.tabGroups.first { $0.name == "Reading" })
        XCTAssertNotNil(group)
        XCTAssertNil(browser.editingGroupID, "A group named already doesn't wait for a name")
        if let group {
            XCTAssertEqual(browser.tabs(in: group.id).count, 3)
        }
    }

    func testOpenInSplitPairsWithThePageOnScreen() {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        defer { browser.closeAll() }
        browser.active?.restore(url: URL(string: "about:blank#left")!, title: "Left")

        browser.openInSplit(URL(string: "https://example.com/right")!)
        XCTAssertNotNil(browser.activeSplit, "The page opens paired with the one on screen")
    }
}
