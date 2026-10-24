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

    /// Whose store this is: a profile's, or a space's own (in that space's
    /// profile). Nil for one of neither, a private tab's.
    static func owner(of store: WKWebsiteDataStore) -> UUID? {
        if store === Store.websites { return Profile.personalID }
        if let id = stores.first(where: { $0.value === store })?.key { return id }
        return Spaces.space(owning: store).map(Spaces.profile(of:))
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

    /// A profile and all it holds, gone: its spaces close with their tabs,
    /// and its cookies, sign-ins, site data, history, bookmarks and
    /// passwords are erased from this Mac. Personal stays, and so does the
    /// first space, which can't be deleted: it comes back to Personal,
    /// signed out. `browser`: the window whose spaces go.
    func delete(_ id: UUID, from browser: Browser) {
        guard id != Profile.personalID, list.contains(where: { $0.id == id }) else { return }
        for space in browser.spaces where space.profile == id && !space.isFirst {
            browser.deleteSpace(space.id)
        }
        // The first space, if it was in it: to Personal, and its own
        // sign-ins, if it had any, go with the rest.
        let all = Spaces.read()
        Spaces.write(all.map { space in
            var space = space
            guard space.profile == id else { return space }
            space.profile = nil
            if space.sharesSignIns != true {
                Spaces.erase(space.id)
                space.sharesSignIns = true
            }
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
        // Its sites' camera, microphone, screen and location answers.
        for key in Store.settings.dictionaryRepresentation().keys where key.hasPrefix("capture.\(id.uuidString)|") {
            Store.settings.removeObject(forKey: key)
        }
    }
}

/// Settings › Profiles & Spaces: every profile with its spaces under it.
/// A space is given to another profile by dragging it onto that profile's
/// card, or from the menu beside it, after a yes either way; a profile is
/// made, renamed or deleted here, and a new space made in it.
struct ProfilesPage: View {
    @ObservedObject var browser: Browser
    @ObservedObject private var profiles = Profiles.shared
    /// The space being dragged, and the one-time word its drag carries. A
    /// drop counts only with that word: text dragged in from another app,
    /// or a drag let go somewhere else and long gone, moves nothing.
    @State private var dragging: (space: UUID, token: String)?
    /// The profile card a space is held over.
    @State private var over: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Card {
                Line("Profiles", "Each keeps its own sign-ins, history, bookmarks and passwords. Every space belongs to one, and going to a space goes to its profile. Extensions and settings are shared") {
                    Pill("New Profile…") {
                        Ask.name("New Profile", detail: "Signed out of everything, with no history, bookmarks or passwords.",
                                 placeholder: "Work", confirm: "Create") { profiles.add(named: $0) }
                    }
                }
            }
            ForEach(profiles.list) { profile in
                card(profile)
            }
        }
    }

    private func card(_ profile: Profile) -> some View {
        let spaces = browser.spaces.filter { $0.profileID == profile.id }
        return Card {
            Line(profile.name, spaces.isEmpty ? "No spaces" : spaces.count == 1 ? "1 space" : "\(spaces.count) spaces") {
                HStack(spacing: 6) {
                    Pill("New Space") {
                        browser.askForSpace { made in browser.setProfile(profile.id, of: made.id) }
                    }
                    Pill("Rename…") {
                        Ask.name("Rename Profile", placeholder: profile.name, initial: profile.name, confirm: "Rename") {
                            profiles.rename(profile.id, to: $0)
                        }
                    }
                    if !profile.isPersonal {
                        Pill("Delete…") { askDelete(profile, spaces: spaces) }
                    }
                }
            }
            ForEach(spaces) { space in
                Rule()
                Line(space.name, nil) {
                    Picker("", selection: Binding(
                        get: { space.profileID },
                        set: { browser.askToMove(space.id, to: $0) }
                    )) {
                        ForEach(profiles.list) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                }
                .contentShape(Rectangle())
                .onDrag {
                    let token = UUID().uuidString
                    dragging = (space.id, token)
                    return NSItemProvider(object: "shy-space:\(token)" as NSString)
                }
                .help("Drag onto another profile to move it there")
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Palette.ink.opacity(over == profile.id ? 0.35 : 0), lineWidth: 1.5)
                .allowsHitTesting(false)
        )
        .onDrop(of: [.plainText], isTargeted: Binding(
            get: { over == profile.id },
            set: { over = $0 ? profile.id : (over == profile.id ? nil : over) }
        )) { providers in
            guard let held = dragging, let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: NSString.self) { text, _ in
                let said = text as? String
                DispatchQueue.main.async {
                    // Only the drag this page started, once.
                    guard said == "shy-space:\(held.token)", dragging?.token == held.token else { return }
                    dragging = nil
                    browser.askToMove(held.space, to: profile.id)
                }
            }
            return true
        }
    }

    private func askDelete(_ profile: Profile, spaces: [Space]) {
        let going = spaces.filter { !$0.isFirst }
        let named = going.map { "“\($0.name)”" }.joined(separator: ", ")
        let erased = "cookies, sign-ins, history, bookmarks and passwords are erased from this Mac. This can't be undone."
        var detail = going.isEmpty ? "Its " + erased
            : (going.count == 1 ? "Its space \(named) closes" : "Its spaces \(named) close") + " with their tabs, and its " + erased
        if spaces.contains(where: \.isFirst) {
            detail += " Your first space stays, signed out, in \(profiles.list[0].name)."
        }
        Ask.sure("Delete “\(profile.name)” and its spaces?", detail: detail, confirm: "Delete", returnCancels: true) {
            profiles.delete(profile.id, from: browser)
        }
    }
}
