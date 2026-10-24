import Foundation

// Pinned tabs are the same in every window: pinned, unpinned, moved,
// relettered or renamed in one, so they are in the others. Each window holds
// its own tab for each pin — its own page, wherever you took it — and only
// what makes the pin a pin is shared: its letter, its name, the page it was
// pinned at, its place among the pins. Per space, as the pins always were.
//
// pins.json holds them. The oldest window's session file keeps its pins as
// it always did, so 1.0.3 finds them there; the first launch of 1.0.4 takes
// them from there.
//
// There were once pins every space showed, kept under "shared": the first
// launch without them gives each space its own copy, so none goes missing.

struct PinDef: Codable, Equatable {
    var id: UUID
    var letter: String
    /// The page it was pinned at (see Browser.goHome).
    var home: String
    var title: String
    var name: String?
    /// A row, not a square (see Tab.listed). Nil rather than false, so a
    /// pins file with no rows in it is written as it always was.
    var listed: Bool? = nil
}

@MainActor
enum Pins {
    /// Pins by space, in their order.
    private(set) static var bySpace: [UUID: [PinDef]] = [:]
    private static var loaded = false

    /// A space's pins changed in one window; the others follow.
    static let changed = Notification.Name("SearchPinsChanged")

    /// Where pins.json kept the pins every space showed.
    nonisolated static let sharedKey = "shared"

    private static var file: URL { Store.file("pins.json") }

    static func defs(_ space: UUID) -> [PinDef] {
        load()
        return bySpace[space] ?? []
    }

    /// Read once. Before there is a pins.json, the pins are the oldest
    /// window's, from its session files — every space's.
    static func load() {
        guard !loaded else { return }
        loaded = true
        if let data = try? Data(contentsOf: file), let saved = decode(data) {
            bySpace = saved.bySpace
            // Pins every space showed: each space's own now, ahead of the
            // rest, under the same id so the tab each row has keeps going.
            if !saved.shared.isEmpty {
                for space in Spaces.read() {
                    let own = bySpace[space.id] ?? []
                    bySpace[space.id] = saved.shared + own.filter { pin in !saved.shared.contains { $0.id == pin.id } }
                }
                save()
            }
            return
        }
        for space in Spaces.read() {
            let defs = Session.read(space: space.id).tabs.compactMap { entry -> PinDef? in
                guard let letter = entry.pin else { return nil }
                return PinDef(id: entry.pinID ?? UUID(), letter: letter, home: entry.home ?? entry.url,
                              title: entry.title, name: entry.name)
            }
            if !defs.isEmpty { bySpace[space.id] = defs }
        }
        save()
    }

    /// A window's pins for a space, as they now are: kept, written, and
    /// passed to the other windows when they differ from what was there.
    static func set(_ space: UUID, _ defs: [PinDef], from browser: Browser) {
        load()
        guard (bySpace[space] ?? []) != defs else { return }
        bySpace[space] = defs.isEmpty ? nil : defs
        save()
        NotificationCenter.default.post(name: changed, object: browser, userInfo: ["space": space])
    }

    /// A space deleted: its pins go with it.
    static func forget(_ space: UUID) {
        guard bySpace.removeValue(forKey: space) != nil else { return }
        save()
    }

    private static func save() {
        let bySpace = bySpace
        Disk.write(file) { encode(bySpace: bySpace) }
    }

    nonisolated static func decode(_ data: Data) -> (bySpace: [UUID: [PinDef]], shared: [PinDef])? {
        guard let saved = try? JSONDecoder().decode([String: [PinDef]].self, from: data) else { return nil }
        var bySpace: [UUID: [PinDef]] = [:]
        for (key, defs) in saved {
            if let space = UUID(uuidString: key) { bySpace[space] = defs }
        }
        return (bySpace, saved[sharedKey] ?? [])
    }

    nonisolated static func encode(bySpace: [UUID: [PinDef]]) -> Data? {
        var out: [String: [PinDef]] = [:]
        for (space, defs) in bySpace { out[space.uuidString] = defs }
        return try? JSONEncoder().encode(out)
    }
}
