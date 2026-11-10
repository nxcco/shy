import Foundation
import AppKit

// What you have kept. Downloads work already; this is only the memory of them,
// so a file you fetched an hour ago is one click from the Finder rather than a
// hunt through a folder.

struct Keep: Codable, Identifiable, Equatable {
    var name: String
    var from: String
    var path: String
    var date: Date
    /// What extensions call it (chrome.downloads ids), its own for good:
    /// a place in the list moves as files come and go. 0 until Loot gives
    /// it one.
    var number = 0
    /// The address it was fetched from, when there was one worth keeping.
    var source: URL?
    /// The profile whose window saved it. Nil in a list from before they
    /// were kept, which only Personal's extensions are shown (see seen).
    var profile: UUID?

    var id: String { path }

    var url: URL { URL(fileURLWithPath: path) }
    var stillThere: Bool { FileManager.default.fileExists(atPath: path) }

    /// Whether an extension of this profile may see it: another profile's
    /// downloads are that profile's business, as its history is.
    func seen(by profile: UUID) -> Bool {
        self.profile.map { $0 == profile } ?? (profile == Profile.personalID)
    }
}

extension Keep {
    private enum Keys: String, CodingKey { case name, from, path, date, number, source, profile }

    /// A list saved before numbers were kept is read without them; Loot
    /// numbers them as it loads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        name = try c.decode(String.self, forKey: .name)
        from = try c.decode(String.self, forKey: .from)
        path = try c.decode(String.self, forKey: .path)
        date = try c.decode(Date.self, forKey: .date)
        number = (try? c.decodeIfPresent(Int.self, forKey: .number)) ?? 0
        source = try? c.decodeIfPresent(URL.self, forKey: .source)
        profile = try? c.decodeIfPresent(UUID.self, forKey: .profile)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(name, forKey: .name)
        try c.encode(from, forKey: .from)
        try c.encode(path, forKey: .path)
        try c.encode(date, forKey: .date)
        try c.encode(number, forKey: .number)
        try c.encodeIfPresent(source, forKey: .source)
        try c.encodeIfPresent(profile, forKey: .profile)
    }
}

@MainActor
final class Loot: ObservableObject {
    @Published private(set) var kept: [Keep] = []
    /// The last number given. The next is above it and never below the
    /// time now, in milliseconds, so a file taken off the list can't hand
    /// its number to another after a relaunch.
    private var lastNumber = 0
    /// Numbers promised to downloads still under way, by address: what an
    /// extension's downloads.download answered, kept by the file it becomes.
    private var promised: [URL: Int] = [:]

    init() { load() }

    func add(_ keep: Keep) {
        var keep = keep
        if keep.number == 0 { keep.number = keep.source.flatMap { promised.removeValue(forKey: $0) } ?? nextNumber() }
        // A data: address is the whole file over again, not where it came from.
        if keep.source?.scheme?.lowercased() == "data" { keep.source = nil }
        kept.removeAll { $0.path == keep.path }
        kept.insert(keep, at: 0)
        // Fifty is more than anybody scrolls back through.
        if kept.count > 50 { kept.removeLast(kept.count - 50) }
        save()
    }

    /// The number a download from this address will have once it lands.
    func promise(_ source: URL) -> Int {
        let number = nextNumber()
        promised[source] = number
        return number
    }

    private func nextNumber() -> Int {
        lastNumber = max(lastNumber + 1, Int(Date().timeIntervalSince1970 * 1000))
        return lastNumber
    }

    /// Off the list, and the file to the Trash, where it can still be put
    /// back from. A file already gone is only taken off the list.
    func forget(_ keep: Keep) {
        if keep.stillThere { try? FileManager.default.trashItem(at: keep.url, resultingItemURL: nil) }
        kept.removeAll { $0.id == keep.id }
        save()
    }

    /// Only the list is emptied. Files you asked for are yours, and deleting
    /// them is the Finder's business, not a browser's.
    func forgetAll() {
        kept = []
        save()
    }

    func reveal(_ keep: Keep) {
        NSWorkspace.shared.activateFileViewerSelecting([keep.url])
    }

    func open(_ keep: Keep) {
        NSWorkspace.shared.open(keep.url)
    }

    private static var file: URL { Store.file("downloads.json") }

    private func load() {
        guard let data = try? Data(contentsOf: Loot.file),
              var list = try? JSONDecoder().decode([Keep].self, from: data)
        else { return }
        lastNumber = list.map(\.number).max() ?? 0
        // Older lists had none: numbered oldest first, then written back,
        // so each keeps the one it was given.
        let unnumbered = list.indices.reversed().filter { list[$0].number == 0 }
        for index in unnumbered { list[index].number = nextNumber() }
        kept = list
        if !unnumbered.isEmpty { save() }
    }

    private func save() {
        let snapshot = kept
        // One after another, the newest last (see Disk).
        Disk.write(Loot.file) { try? JSONEncoder().encode(snapshot) }
    }
}
