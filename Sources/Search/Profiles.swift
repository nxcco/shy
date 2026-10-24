import AppKit
import SwiftUI
import WebKit

// Profiles, as in Arc: a profile holds the sign-ins and site data, the
// history, the bookmarks and the passwords, and each space belongs to one.
// Going to a space is going to its profile, in the same window: the tabs
// there are signed in as the profile is, the address field offers its
// history, the bookmarks are its own, and a password saved or filled in is
// its own. Several spaces can share a profile — Work and Work Research,
// both signed in to the same mail.
//
// There is always one, "Personal": everything there was before profiles,
// left where it was — the same store, history.json, bookmarks.json and
// keychain items — so nobody's data moves, and every space is in it until
// it is given another. A space with sign-ins of its own from before keeps
// them, inside whichever profile it is in.
//
// Shared by every profile, for now: the settings, the extensions (one
// WKWebExtensionController for the app), downloads and the icons of sites.
// Never synced anywhere.

struct Profile: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String

    static let personalID = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1") ?? UUID()
    var isPersonal: Bool { id == Profile.personalID }
    static let personal = Profile(id: personalID, name: "Personal")
}

@MainActor
final class Profiles: ObservableObject {
    static let shared = Profiles()

    /// Every profile, Personal first.
    @Published private(set) var list: [Profile]

    private init() { list = Profiles.read() }

    /// More than one: only then does anything about profiles show beyond
    /// Settings.
    var several: Bool { list.count > 1 }

    func profile(_ id: UUID) -> Profile { list.first { $0.id == id } ?? .personal }

    // MARK: - the file

    private nonisolated static var file: URL { Store.file("profiles.json") }

    nonisolated static func read() -> [Profile] {
        let saved = (try? Data(contentsOf: file)).flatMap { try? JSONDecoder().decode([Profile].self, from: $0) } ?? []
        let personal = saved.first(where: \.isPersonal) ?? .personal
        return [personal] + saved.filter { !$0.isPersonal }
    }

    private func write() {
        let snapshot = list
        // Only Personal, named as it always was, is no file at all.
        if snapshot == [.personal] {
            try? FileManager.default.removeItem(at: Profiles.file)
            return
        }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? FileManager.default.createDirectory(at: Profiles.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: Profiles.file, options: .atomic)
    }

    // MARK: - what each holds

    /// Each profile's store, made once: WebKit shares processes between
    /// views that ask for the same store object.
    private static var stores: [UUID: WKWebsiteDataStore] = [:]

    /// The cookies and sign-ins its spaces share. Personal's is the store
    /// there always was; another's is WebKit's store under the profile's
    /// own identifier.
    static func store(_ id: UUID) -> WKWebsiteDataStore {
        if id == Profile.personalID { return Store.websites }
        if let made = stores[id] { return made }
        let made = WKWebsiteDataStore(forIdentifier: id)
        if Store.keepsSignIns { Store.followSignIns(made) } else { Store.followCookies(made) }
        stores[id] = made
        return made
    }

    /// The profile stores made so far, Personal's aside.
    static var madeStores: [WKWebsiteDataStore] { Array(stores.values) }

    private static var histories: [UUID: History] = [:]
    private static var bookmarkLists: [UUID: Bookmarks] = [:]

    /// Its history: Personal's in history.json, as always; another's in a
    /// file of its own.
    static func history(_ id: UUID) -> History {
        if let made = histories[id] { return made }
        let made = History(file: id == Profile.personalID ? "history.json" : "history-\(id.uuidString).json")
        histories[id] = made
        return made
    }

    static func bookmarks(_ id: UUID) -> Bookmarks {
        if let made = bookmarkLists[id] { return made }
        let made = Bookmarks(file: id == Profile.personalID ? "bookmarks.json" : "bookmarks-\(id.uuidString).json")
        bookmarkLists[id] = made
        return made
    }

    // MARK: - making, renaming, deleting

    @discardableResult
    func add(named name: String) -> Profile {
        let made = Profile(id: UUID(), name: String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60)))
        list.append(made)
        write()
        return made
    }

    /// The one named so, made if there is none: for an import bringing a
    /// browser's profiles in.
    func named(_ name: String) -> Profile {
        if name == Profile.personal.name || name.isEmpty { return list[0] }
        return list.first { $0.name == name } ?? add(named: name)
    }

    func rename(_ id: UUID, to name: String) {
        let name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        guard !name.isEmpty, let at = list.firstIndex(where: { $0.id == id }) else { return }
        list[at].name = name
        write()
    }

    /// A profile and what it holds, gone: its cookies, sign-ins, site data,
    /// history, bookmarks and passwords are erased from this Mac. Its spaces
    /// stay, with their tabs, in Personal. Personal itself stays.
    func delete(_ id: UUID) {
        guard id != Profile.personalID, list.contains(where: { $0.id == id }) else { return }
        // Its spaces to Personal first, so that their tabs leave its store
        // before it is emptied (see Browser's Spaces.changed).
        let all = Spaces.read()
        Spaces.write(all.map { space in
            var space = space
            if space.profile == id { space.profile = nil }
            return space
        })
        list.removeAll { $0.id == id }
        write()
        if let store = Profiles.stores.removeValue(forKey: id) {
            Browsers.acting.forgetDownloads(of: store)
            store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {}
        }
        // The store itself, by the same sweep as a deleted space's.
        let pending = Set(Store.settings.stringArray(forKey: "spaces.erasing") ?? []).union([id.uuidString])
        Store.settings.set(pending.sorted(), forKey: "spaces.erasing")
        Spaces.sweep()
        Profiles.histories.removeValue(forKey: id)?.retire()
        Profiles.bookmarkLists.removeValue(forKey: id)?.retire()
        // Never opened this run: their files go all the same.
        for name in ["history-\(id.uuidString).json", "bookmarks-\(id.uuidString).json"] {
            Disk.remove(Store.file(name))
        }
        Vault.forgetAll(in: id)
    }
}

/// Settings › Tabs › Profiles: each profile, what it holds, and its spaces.
struct ProfilesCard: View {
    @ObservedObject var browser: Browser
    @ObservedObject private var profiles = Profiles.shared

    var body: some View {
        Card {
            Line("Profiles", "Each holds its own sign-ins, history, bookmarks and passwords. A space belongs to one: right-click the space's icon › Profile. Extensions and settings are shared") {
                Pill("New Profile…") {
                    Ask.name("New Profile", detail: "Signed out of everything, with no history, bookmarks or passwords. Give a space to it from the space's menu.",
                             placeholder: "Work", confirm: "Create") { profiles.add(named: $0) }
                }
            }
            ForEach(profiles.list) { profile in
                Rule()
                Line(profile.name, spacesDetail(profile)) {
                    HStack(spacing: 6) {
                        Pill("Rename…") {
                            Ask.name("Rename Profile", placeholder: profile.name, initial: profile.name, confirm: "Rename") {
                                profiles.rename(profile.id, to: $0)
                            }
                        }
                        if !profile.isPersonal {
                            Pill("Delete…") {
                                Ask.sure("Delete “\(profile.name)”?",
                                         detail: "Its cookies, sign-ins, history, bookmarks and passwords are erased from this Mac. Its spaces stay, with their tabs, in \(profiles.list[0].name).",
                                         confirm: "Delete", returnCancels: true) { profiles.delete(profile.id) }
                            }
                        }
                    }
                }
            }
        }
    }

    private func spacesDetail(_ profile: Profile) -> String {
        let names = browser.spaces.filter { $0.profileID == profile.id }.map(\.name)
        return names.isEmpty ? "No spaces yet" : names.joined(separator: ", ")
    }
}
