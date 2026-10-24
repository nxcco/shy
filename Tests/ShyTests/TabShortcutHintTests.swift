import AppKit
import SwiftUI
import XCTest
@testable import Shy

@MainActor
final class TabShortcutHintTests: XCTestCase {
    override class func setUp() {
        setenv("SHY_PROBE", "tab-shortcut-hints-\(getpid())", 1)
        super.setUp()
    }

    func testNumbersFollowVisibleTabsIncludingPinsFoldersAndSplits() throws {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        defer { browser.closeAll() }
        browser.commandHeld = true
        for count in 1...11 {
            if count > 1 { browser.newTab() }
            browser.tabs.last?.restore(url: URL(string: "about:blank#\(count)")!, title: "Tab \(count)")
            assertNumbers(browser)
        }
        let pinned = browser.tabs[3]
        browser.pin(pinned)
        defer { browser.unpin(pinned) }
        let left = browser.tabs[5], right = browser.tabs[6]
        browser.pair(right, with: left, onLeft: false)
        XCTAssertNil(browser.tabShortcutNumbers[right.id])
        assertNumbers(browser)
        let filed = browser.tabs.filter { $0.pin == nil && $0.id != left.id && $0.id != right.id }.prefix(2)
        let folder = try XCTUnwrap(browser.newFolder(named: "Kept", editing: false))
        defer { browser.deleteFolder(folder) }
        for tab in filed { browser.move(tab, toFolder: folder) }
        browser.select(browser.tabs.last!)
        browser.toggleFolder(folder)
        for tab in filed { XCTAssertNil(browser.tabShortcutNumbers[tab.id]) }
        assertNumbers(browser)
        browser.move(browser.tabs.last!, to: 1)
        assertNumbers(browser)
        browser.commandHeld = false
        XCTAssertTrue(browser.tabShortcutNumbers.isEmpty)
    }

    func testCommandEventsAndFocusLoss() async throws {
        _ = NSApplication.shared
        let browser = Browser(record: WindowRecord())
        for number in 1...11 {
            if number > 1 { browser.newTab() }
            browser.tabs.last?.restore(url: URL(string: "about:blank#\(number)")!, title: "Tab \(number)")
        }
        let window = NSWindow(contentRect: NSRect(x: -20_000, y: -20_000, width: 900, height: 600),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ContentView(browser: browser))
        window.orderFrontRegardless()
        let previousFront = Front.shared.browser
        Front.shared.set(browser)
        defer {
            Front.shared.set(previousFront)
            ContentView.forget(browser)
            window.contentView = nil
            window.close()
            browser.closeAll()
        }
        try await settle()
        try await flags(.command, in: window)
        XCTAssertTrue(browser.commandHeld)
        XCTAssertEqual(browser.tabShortcutNumbers.count, 9)
        for number in [2, 9] {
            let hinted = try XCTUnwrap(browser.tabShortcutNumbers.first { $0.value == number }?.key)
            try press(number, browser: browser, window: window)
            XCTAssertEqual(browser.activeID, hinted, "The physical shortcut must select its hinted tab")
        }
        let tabs = browser.tabs
        browser.pin(tabs[4])
        defer { browser.unpin(tabs[4]) }
        browser.pair(tabs[1], with: tabs[0], onLeft: false)
        let folder = try XCTUnwrap(browser.newFolder(named: "Kept", editing: false))
        defer { browser.deleteFolder(folder) }
        browser.move(tabs[2], toFolder: folder)
        browser.move(tabs[3], toFolder: folder)
        XCTAssertNil(browser.tabShortcutNumbers[folder], "An open folder has no number")
        XCTAssertNotNil(browser.tabShortcutNumbers[tabs[2].id])
        XCTAssertNotNil(browser.tabShortcutNumbers[tabs[3].id])
        XCTAssertNil(browser.tabShortcutNumbers[tabs[1].id], "A split counts once")
        try press(try XCTUnwrap(browser.tabShortcutNumbers[tabs[3].id]), browser: browser, window: window)
        XCTAssertEqual(browser.activeID, tabs[3].id)
        browser.select(tabs.last!)
        browser.toggleFolder(folder)
        tabs[2].touch(at: Date(timeIntervalSinceNow: -100))
        tabs[3].touch(at: Date(timeIntervalSinceNow: -10))
        XCTAssertNotNil(browser.tabShortcutNumbers[folder])
        for tab in tabs[2...3] { XCTAssertNil(browser.tabShortcutNumbers[tab.id]) }
        try press(1, browser: browser, window: window)
        XCTAssertEqual(browser.activeID, tabs[4].id, "Pins in no folder keep their place before the folders")
        XCTAssertEqual(browser.tabShortcutNumbers[folder], 2)
        try press(2, browser: browser, window: window)
        XCTAssertEqual(browser.activeID, tabs[3].id, "A folded folder selects its most recently used page")
        XCTAssertTrue(browser.folders.first { $0.id == folder }?.folded == true)
        XCTAssertNil(browser.tabShortcutNumbers[tabs[3].id], "The active member has no duplicate number")
        tabs[2].touch(at: Date(timeIntervalSinceNow: 10))
        try press(try XCTUnwrap(browser.tabShortcutNumbers[folder]), browser: browser, window: window)
        XCTAssertEqual(browser.activeID, tabs[3].id, "An active folded folder keeps its current page")
        try press(9, browser: browser, window: window)
        XCTAssertEqual(browser.activeID, tabs.last?.id, "Command 9 counts a folded folder as one target")
        browser.toggleFolder(folder)
        XCTAssertNil(browser.tabShortcutNumbers[folder])
        XCTAssertNotNil(browser.tabShortcutNumbers[tabs[2].id])
        try press(try XCTUnwrap(browser.tabShortcutNumbers[tabs[2].id]), browser: browser, window: window)
        XCTAssertEqual(browser.activeID, tabs[2].id)
        assertNumbers(browser)
        try await flags([], in: window)
        XCTAssertFalse(browser.commandHeld)
        try await flags(.command, in: window)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        XCTAssertFalse(browser.commandHeld)
        try await flags(.command, in: window)
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        XCTAssertFalse(browser.commandHeld)
    }

    private func assertNumbers(_ browser: Browser, file: StaticString = #filePath, line: UInt = #line) {
        let shown = browser.tabShortcutTargets
        for (index, tab) in shown.enumerated() {
            let expected = index < 8 ? index + 1 : (index == shown.count - 1 ? 9 : nil)
            XCTAssertEqual(browser.tabShortcutNumbers[tab.id], expected, file: file, line: line)
        }
    }

    private func press(_ number: Int, browser: Browser, window: NSWindow) throws {
        let codes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        let characters = number == 2 ? "é" : String(number)
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
            modifierFlags: .command, timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: codes[number - 1]))
        XCTAssertNil(ContentView.keyHooks[ObjectIdentifier(browser)]?(event))
    }

    private func flags(_ flags: NSEvent.ModifierFlags, in window: NSWindow) async throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .flagsChanged, location: .zero,
            modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: 55))
        NSApp.postEvent(event, atStart: false)
        if let queued = NSApp.nextEvent(matching: .flagsChanged, until: Date(timeIntervalSinceNow: 1), inMode: .default, dequeue: true) {
            NSApp.sendEvent(queued)
        }
        try await settle()
    }

    private func settle() async throws { try await Task.sleep(for: .milliseconds(250)) }
}
