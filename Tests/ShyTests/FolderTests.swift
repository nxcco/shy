import AppKit
import XCTest
@testable import Shy

/// Folders among the pinned rows (Folders.swift): what going into one makes
/// of a tab, the lines the column draws, deleting one, tab groups made
/// folders, where a carried tab would land, and folders.json.
@MainActor
final class FolderTests: XCTestCase {
    override class func setUp() {
        setenv("SHY_PROBE", "folders-\(getpid())", 1)
        super.setUp()
    }

    private func browser(tabs count: Int) -> Browser {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let browser = Browser(record: WindowRecord())
        for number in 0..<count {
            if number > 0 { browser.newTab() }
            browser.tabs.last?.restore(url: URL(string: "https://\(number).example/")!, title: "\(number)")
        }
        return browser
    }

    /// The space's pins and folders are kept on disk for every window:
    /// a test leaves none behind.
    private func clean(_ browser: Browser) {
        for folder in Folders.tops(browser.folders) { browser.deleteFolder(folder.id) }
        for tab in browser.tabs where tab.pin != nil { browser.unpin(tab) }
        browser.closeAll()
    }

    func testATabMovedIntoAFolderIsAPinnedRowThere() throws {
        let browser = browser(tabs: 5)
        defer { clean(browser) }
        let tabs = browser.tabs
        let folder = try XCTUnwrap(browser.newFolder(named: "Work", editing: false))
        for tab in tabs[0...2] { XCTAssertTrue(browser.move(tab, toFolder: folder)) }
        XCTAssertTrue(tabs[0...2].allSatisfy { $0.pin != nil && $0.listed && $0.folder == folder })
        XCTAssertNotNil(tabs[0].home, "a folder's tab goes home as a pin does")
        XCTAssertTrue(browser.move(tabs[3], toFolder: folder, at: 0))
        XCTAssertEqual(browser.tabs(inFolder: folder).map(\.id), [3, 0, 1, 2].map { tabs[$0].id })
        XCTAssertEqual(browser.tabs.map(\.id), [3, 0, 1, 2, 4].map { tabs[$0].id },
                       "the row is in the column's order")
        XCTAssertTrue(browser.squarePins.isEmpty)
        XCTAssertTrue(browser.listedPins.isEmpty)
        XCTAssertEqual(Pins.defs(browser.spaceID).compactMap(\.folder), [folder, folder, folder, folder])

        browser.clearTabs()
        for tab in tabs[0...3] { XCTAssertTrue(browser.tabs.contains { $0 === tab }, "Clear keeps a folder's tabs") }
        XCTAssertFalse(browser.tabs.contains { $0 === tabs[4] })

        XCTAssertTrue(browser.move(tabs[0], toFolder: nil))
        XCTAssertNotNil(tabs[0].pin, "out of its folder, a tab is still kept")
        XCTAssertTrue(tabs[0].listed)
        XCTAssertNil(tabs[0].folder)
        XCTAssertFalse(browser.move(tabs[1], toFolder: UUID()), "no folder, no move")
        XCTAssertEqual(tabs[1].folder, folder)
    }

    func testOneLevelDownAndTheLinesTheColumnDraws() throws {
        let browser = browser(tabs: 4)
        defer { clean(browser) }
        let tabs = browser.tabs
        let top = try XCTUnwrap(browser.newFolder(named: "Top", editing: false))
        let inner = try XCTUnwrap(browser.newFolder(in: top, named: "Inner", editing: false))
        XCTAssertNil(browser.newFolder(in: inner, editing: false), "a folder in a folder holds tabs only")
        browser.move(tabs[0], toFolder: top)
        browser.move(tabs[1], toFolder: inner)
        func shape() -> [String] {
            browser.folderLines.map { line in
                switch line {
                case .folder(let folder, let depth): "\(depth) \(folder.name)"
                case .tab(let tab, let depth, _): "\(depth) \(tabs.firstIndex { $0 === tab } ?? -1)"
                }
            }
        }
        XCTAssertEqual(shape(), ["0 Top", "1 0", "1 Inner", "2 1"])
        browser.select(tabs[3])
        browser.toggleFolder(inner)
        XCTAssertEqual(shape(), ["0 Top", "1 0", "1 Inner"])
        browser.select(tabs[1])
        XCTAssertEqual(shape(), ["0 Top", "1 0", "1 Inner", "2 1"], "the tab in front stays in sight")
        browser.toggleFolder(top)
        XCTAssertEqual(shape(), ["0 Top", "1 1"], "under a folded folder, a step in")
        XCTAssertEqual(browser.shownTabs.filter { $0.pin != nil }.map(\.id), [tabs[1].id])

        // Another space passing by draws the same lines from the same row.
        let parked = Parked(tabs: browser.tabs, active: browser.activeID)
        XCTAssertEqual(Folders.lines(browser.folders, pins: parked.tabs.filter { $0.pin != nil }, front: parked.front).map(\.id),
                       browser.folderLines.map(\.id))

        browser.deleteFolder(top)
        XCTAssertTrue(browser.folders.isEmpty, "the folder in it goes with it")
        for tab in tabs {
            XCTAssertNil(tab.pin, "its tabs come out as ordinary tabs")
            XCTAssertTrue(browser.tabs.contains { $0 === tab }, "and stay open")
        }
    }

    func testTabGroupsBecomeFoldersOnce() throws {
        let browser = browser(tabs: 1)
        let space = UUID()
        defer {
            Pins.forget(space)
            Session.erase(space: space)
            browser.closeAll()
        }
        let group = TabGroup(id: UUID(), name: "Reading", collapsed: true)
        let shape = Session.Shape(tabs: [
            Session.Entry(url: "https://a.example/", title: "A"),
            Session.Entry(url: "https://b.example/", title: "B", groupID: group.id),
            Session.Entry(url: "https://c.example/", title: "C", groupID: group.id),
        ], active: 0, groups: [group])
        let folded = browser.foldGroups(shape, space: space)
        XCTAssertNil(folded.groups)
        XCTAssertEqual(folded.tabs.map { $0.pin != nil }, [false, true, true])
        XCTAssertEqual(folded.tabs.map(\.url), shape.tabs.map(\.url), "nothing lost, nothing moved")
        XCTAssertTrue(folded.tabs.allSatisfy { $0.groupID == nil })
        let folder = try XCTUnwrap(Pins.folders(space).first)
        XCTAssertEqual(folder.id, group.id, "an extension knows it by the same number")
        XCTAssertEqual(folder.name, "Reading")
        XCTAssertTrue(folder.folded)
        XCTAssertEqual(Pins.defs(space).map(\.home), ["https://b.example/", "https://c.example/"])
        XCTAssertEqual(Pins.defs(space).map(\.folder), [group.id, group.id])
        XCTAssertEqual(Pins.defs(space).map(\.listed), [true, true])
        XCTAssertEqual(folded.tabs.compactMap(\.pinID), Pins.defs(space).map(\.id))

        // Read again before the row was written: the same pins, no more.
        let again = browser.foldGroups(shape, space: space)
        XCTAssertEqual(Pins.defs(space).count, 2)
        XCTAssertEqual(Pins.folders(space).count, 1)
        XCTAssertEqual(again.tabs.compactMap(\.pinID), folded.tabs.compactMap(\.pinID))
    }

    func testWhereACarriedTabGoesAmongTheFolders() {
        let folder = Folder(id: UUID(), name: "F")
        let a = Tab(configuration: Web.configuration()), b = Tab(configuration: Web.configuration())
        let carried = Tab(configuration: Web.configuration())
        defer { [a, b, carried].forEach { $0.close() } }
        let lines: [(line: FolderLine, frame: CGRect)] = [
            (.folder(folder, depth: 0), CGRect(x: 0, y: 0, width: 200, height: 28)),
            (.tab(a, depth: 1, folder: folder.id), CGRect(x: 14, y: 30, width: 186, height: 28)),
            (.tab(b, depth: 1, folder: folder.id), CGRect(x: 14, y: 60, width: 186, height: 28)),
        ]
        func slot(_ y: CGFloat, _ moving: Tab = carried) -> PinDrop.Target? {
            PinDrop.folderSlot(y: y, lines: lines, carried: moving.id) { _ in [a.id, b.id] }
        }
        XCTAssertEqual(slot(10), .folder(folder.id, at: nil), "over the folder: in, at the end")
        XCTAssertEqual(slot(35), .folder(folder.id, at: 0))
        XCTAssertEqual(slot(50), .folder(folder.id, at: 1))
        XCTAssertEqual(slot(300), .folder(folder.id, at: 2), "past the last line: after it")
        XCTAssertEqual(slot(40, a), .folder(folder.id, at: 0), "over itself it stays")
        XCTAssertEqual(slot(65, a), .folder(folder.id, at: 0), "counted without the carried tab")
        XCTAssertEqual(PinDrop.zone(CGPoint(x: 20, y: 50), width: 200, gridBottom: nil, listed: nil,
                                    folders: CGRect(x: 0, y: 0, width: 200, height: 90)), .folders)
        XCTAssertEqual(PinDrop.zone(CGPoint(x: 20, y: 120), width: 200, gridBottom: nil, listed: nil,
                                    folders: CGRect(x: 0, y: 0, width: 200, height: 90)), .loose)
    }

    func testWhereACarriedFolderGoes() {
        let a = Folder(id: UUID(), name: "A"), b = Folder(id: UUID(), name: "B"), c = Folder(id: UUID(), name: "C")
        let d = Folder(id: UUID(), name: "D", parent: c.id)
        let folders = [a, b, c, d]
        let lines: [(line: FolderLine, frame: CGRect)] = [
            (.folder(a, depth: 0), CGRect(x: 0, y: 0, width: 200, height: 28)),
            (.folder(b, depth: 0), CGRect(x: 0, y: 30, width: 200, height: 28)),
            (.folder(c, depth: 0), CGRect(x: 0, y: 60, width: 200, height: 28)),
            (.folder(d, depth: 1), CGRect(x: 14, y: 90, width: 186, height: 28)),
        ]
        func place(_ carried: Folder, _ y: CGFloat) -> PinDrop.Place? {
            PinDrop.folderPlace(y: y, lines: lines, carried: carried, folders: folders)
        }
        XCTAssertEqual(place(a, 32), PinDrop.Place(folder: a.id, parent: nil, at: 0), "the top of a row: before it")
        XCTAssertEqual(place(a, 44), PinDrop.Place(folder: a.id, parent: b.id, at: 0), "its middle: into it")
        XCTAssertEqual(place(a, 56), PinDrop.Place(folder: a.id, parent: nil, at: 1), "its foot: after it")
        XCTAssertEqual(place(c, 40), PinDrop.Place(folder: c.id, parent: nil, at: 1),
                       "a folder holding one never goes in another: its middle half is before or after")
        XCTAssertEqual(place(c, 100), PinDrop.Place(folder: c.id, parent: nil, at: 2),
                       "its own lines don't count: the nearest other is B, above, and it goes after")
        XCTAssertEqual(place(a, 95), PinDrop.Place(folder: a.id, parent: c.id, at: 0), "before an inner folder, beside it")
        XCTAssertEqual(place(d, 14), PinDrop.Place(folder: d.id, parent: a.id, at: 0), "an inner folder into another top one")
        XCTAssertEqual(place(d, 2), PinDrop.Place(folder: d.id, parent: nil, at: 0), "or out to the top")
    }

    func testAFolderPlacedKeepsItsTabsAndItsNumber() throws {
        let browser = browser(tabs: 3)
        defer { clean(browser) }
        let tabs = browser.tabs
        let a = try XCTUnwrap(browser.newFolder(named: "A", editing: false))
        let b = try XCTUnwrap(browser.newFolder(named: "B", editing: false))
        let c = try XCTUnwrap(browser.newFolder(named: "C", editing: false))
        browser.move(tabs[0], toFolder: a)
        browser.move(tabs[1], toFolder: c)
        browser.placeFolder(c, in: nil, at: 0)
        XCTAssertEqual(Folders.tops(browser.folders).map(\.id), [c, a, b])
        XCTAssertEqual(browser.tabs.prefix(2).map(\.id), [tabs[1].id, tabs[0].id], "the row follows the folders")
        XCTAssertEqual(Pins.defs(browser.spaceID).compactMap(\.folder), [c, a], "and so does pins.json")

        browser.placeFolder(a, in: b, at: 0)
        XCTAssertEqual(browser.folders.first { $0.id == a }?.parent, b)
        XCTAssertEqual(tabs[0].folder, a, "its tabs go with it")
        browser.placeFolder(b, in: c, at: 0)
        XCTAssertNil(browser.folders.first { $0.id == b }?.parent, "one holding a folder stays at the top")
        browser.placeFolder(a, in: nil, at: 3)
        XCTAssertEqual(Folders.tops(browser.folders).map(\.id), [c, b, a])
        XCTAssertEqual(browser.folders.map(\.id).sorted { $0.uuidString < $1.uuidString },
                       [a, b, c].sorted { $0.uuidString < $1.uuidString }, "the same folders, the same ids")
    }

    func testFoldersFileKeepsEachSpaceApart() throws {
        let one = UUID(), two = UUID()
        let top = Folder(id: UUID(), name: "Top", folded: true)
        let inner = Folder(id: UUID(), name: "Inner", parent: top.id)
        let data = try XCTUnwrap(Pins.encodeFolders([one: [top, inner], two: []]))
        let back = Pins.decodeFolders(data)
        XCTAssertEqual(back[one], [top, inner])
        XCTAssertNil(back[two], "an empty list isn't written")

        // One space's list that won't read takes nothing else with it.
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        raw[two.uuidString] = [["name": "no id"]]
        let mixed = Pins.decodeFolders(try JSONSerialization.data(withJSONObject: raw))
        XCTAssertEqual(mixed[one], [top, inner])
        XCTAssertNil(mixed[two])

        // A pin in a folder is still a pin to a pins.json reader.
        let pin = PinDef(id: UUID(), letter: "A", home: "https://a.example/", title: "A", name: nil, listed: true, folder: top.id)
        let pins = try XCTUnwrap(Pins.encode(bySpace: [one: [pin]]))
        XCTAssertEqual(Pins.decode(pins)?.bySpace[one], [pin])
    }
}
