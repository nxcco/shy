import AppKit
import XCTest
@testable import Shy

@MainActor
final class WindowRowTests: XCTestCase {
    override class func setUp() {
        setenv("SHY_PROBE", "window-row-\(getpid())", 1)
        super.setUp()
    }

    private func pinned(_ browser: Browser) -> (old: [PinDef], pins: [PinDef]) {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let old = Pins.defs(browser.spaceID)
        let pins = [PinDef(id: UUID(), letter: "P", home: "https://pin.invalid/", title: "Pin", name: nil)]
        Pins.set(browser.spaceID, pins, from: browser)
        browser.pinsChanged(in: browser.spaceID)
        return (old, pins)
    }

    func testClosedWindowLeavesTheSpacesPinsAlone() {
        let browser = Browser(record: WindowRecord())
        let (old, pins) = pinned(browser)
        defer { Pins.set(browser.spaceID, old, from: browser) }
        browser.closeAll()
        browser.writeSession(now: true)
        browser.pinsChanged(in: browser.spaceID)
        XCTAssertEqual(Pins.defs(browser.spaceID), pins, "a closed window's empty row must not erase the pins")
        XCTAssertTrue(browser.tabs.isEmpty)
        XCTAssertFalse(browser.usesFiles)
    }

    func testReopenedTabNeverLandsAmongThePins() {
        let browser = Browser(record: WindowRecord())
        let (old, _) = pinned(browser)
        defer {
            browser.closeAll()
            Pins.set(browser.spaceID, old, from: browser)
        }
        XCTAssertEqual(browser.pinnedCount, 1)
        let ghost = Browser.Ghost(url: URL(string: "https://closed.invalid/")!, title: "Closed", index: 0,
                                  profile: browser.profileID)
        browser.reopen(ghost)
        XCTAssertNotNil(browser.tabs.first?.pin)
        XCTAssertEqual(browser.tabs.firstIndex { $0.id == browser.activeID }, 1)
    }

    func testPinSwappedForAnotherPageKeepsItsIdentity() {
        let browser = Browser(record: WindowRecord())
        let (old, pins) = pinned(browser)
        defer {
            browser.closeAll()
            Pins.set(browser.spaceID, old, from: browser)
        }
        guard let pin = browser.tabs.first(where: { $0.pin != nil }) else { return XCTFail("no pin") }
        browser.replace(pin, going: URL(string: "https://elsewhere.invalid/")!)
        let fresh = browser.tabs.first { $0.pin != nil }
        XCTAssertNotIdentical(fresh, pin)
        XCTAssertEqual(fresh?.pinID, pins[0].id)
        XCTAssertEqual(fresh?.home?.absoluteString, pins[0].home)
    }
}
