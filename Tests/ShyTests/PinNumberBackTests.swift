import AppKit
import XCTest
@testable import Shy

/// A pin's ⌘ number pressed again on that pin goes back to the tab before
/// it (idea 216).
@MainActor
final class PinNumberBackTests: XCTestCase {
    override class func setUp() {
        setenv("SHY_PROBE", "pin-number-back-\(getpid())", 1)
        super.setUp()
    }

    func testSecondPressGoesBack() {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        defer { browser.closeAll() }
        for number in 1...4 {
            if number > 1 { browser.newTab() }
            browser.tabs.last?.restore(url: URL(string: "about:blank#\(number)")!, title: "Tab \(number)")
        }
        let pin = browser.tabs[0]
        browser.pin(pin)
        defer { browser.unpin(pin) }
        let reading = browser.tabs.first { $0.pin == nil && $0.title == "Tab 3" }!
        XCTAssertEqual(browser.tabShortcutTargets.first?.tab.id, pin.id, "The pin is ⌘1")

        browser.select(reading)
        browser.select(index: 0)
        XCTAssertEqual(browser.activeID, pin.id, "The first press still goes to the pin")
        browser.select(index: 0)
        XCTAssertEqual(browser.activeID, reading.id, "The second goes back to where you were")
        browser.select(index: 0)
        XCTAssertEqual(browser.activeID, pin.id, "And again to the pin")

        // A tab's number, not a pin's, never goes back.
        let other = browser.tabShortcutTargets[1].tab
        browser.select(index: 1)
        XCTAssertEqual(browser.activeID, other.id)
        browser.select(index: 1)
        XCTAssertEqual(browser.activeID, other.id)
    }
}
