import SwiftUI
import WebKit

// Spaces: separate sets of tabs in the one window, each with its own
// cookies and sign-ins, and a downloads folder of its own if you like.
//
// Off unless turned on in Settings › Tabs. Until then there is one space,
// the first, and nothing about it shows: its tabs are the session there
// has always been and its sites use the store there has always been, so
// turning spaces on signs nobody out.
//
// A space's sites live in a WebKit store of their own, made by identifier;
// history, bookmarks, settings and
// extensions are shared by every space. Switching swaps the row of tabs:
// the ones left behind are parked, their sound paused, and they sleep
// after half an hour as any tab does, pins included unless their site may
// send notifications (Sleep.swift). ⌃1–⌃9 switch, as in Arc.

struct Space: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    /// Which of `Spaces.colours` — from before spaces had icons; kept so an
    /// older list still reads.
    var colour: Int
    /// Its icon, one of `Spaces.icons`.
    var icon: String?
    /// Signed in wherever the first space is — the same cookies and
    /// sign-ins, only the tabs its own — rather than a store of its own.
    /// Chosen when it is made; nil, for a space from before the choice, is
    /// a store of its own.
    var sharesSignIns: Bool?
    /// Where this space's downloads go; nil for the folder in Settings.
    var downloads: String?
    /// The profile it is in (see Profiles.swift); nil for Personal.
    var profile: UUID?

    var profileID: UUID { profile ?? Profile.personalID }

    /// The first space: the session and the store there were before spaces.
    static let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID()
    var isFirst: Bool { id == Space.firstID }

    /// The icon it shows: its own, or a house for the first and a
    /// briefcase for any other that has none yet.
    var symbol: String { icon.flatMap { Spaces.icons.contains($0) ? $0 : nil } ?? (isFirst ? "house" : "briefcase") }
}

enum Spaces {
    static let colours: [Color] = [
        Color(red: 0.45, green: 0.47, blue: 0.52), // slate
        Color(red: 0.26, green: 0.52, blue: 0.96), // blue
        Color(red: 0.20, green: 0.66, blue: 0.45), // green
        Color(red: 0.96, green: 0.62, blue: 0.20), // orange
        Color(red: 0.90, green: 0.33, blue: 0.40), // red
        Color(red: 0.62, green: 0.40, blue: 0.90), // violet
    ]

    /// The icons a space can wear: Apple's own symbols, drawn in one weight
    /// and one grey, grouped as work, thinking, leisure and life.
    static let icons = [
        "briefcase", "building.2", "desktopcomputer", "laptopcomputer", "chevron.left.forwardslash.chevron.right", "terminal",
        "sparkles", "brain.head.profile", "lightbulb", "gamecontroller", "beach.umbrella", "cup.and.saucer",
        "music.note", "film", "paintpalette", "camera", "house", "book",
        "graduationcap", "cart", "airplane", "dumbbell", "leaf", "heart",
    ]
    static let iconNames = [
        "Work", "Office", "Desktop", "Laptop", "Code", "Terminal",
        "AI", "Thinking", "Ideas", "Games", "Leisure", "Café",
        "Music", "Film", "Art", "Photos", "Home", "Reading",
        "Studies", "Shopping", "Travel", "Sport", "Nature", "Personal",
    ]

    private static var file: URL { Store.file("spaces.json") }

    /// Every space, the first one first — made on the spot if there is no
    /// list yet.
    static func read() -> [Space] {
        let data = try? Data(contentsOf: file)
        let decoded = data.flatMap { try? JSONDecoder().decode([Space].self, from: $0) }
        // A list that doesn't read is set aside, not written over at the
        // next change: the spaces' stores would be left with no line to
        // delete them from.
        if data != nil, decoded == nil { Store.quarantine(file) }
        let saved = decoded ?? []
        let first = saved.first(where: \.isFirst) ?? Space(id: Space.firstID, name: "Personal", colour: 0)
        return [first] + saved.filter { !$0.isFirst }
    }

    static func write(_ spaces: [Space]) {
        MainActor.assumeIsolated { know(spaces) }
        guard let data = try? JSONEncoder().encode(spaces) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
        // Every window's list follows (see Browser.init).
        NotificationCenter.default.post(name: changed, object: spaces)
    }

    /// The list of spaces changed, in one window or another.
    static let changed = Notification.Name("ShySpacesChanged")

    /// The space new tabs are made in: the one on screen.
    @MainActor static var current = Space.firstID

    /// Each space's store, made once: WebKit shares processes between views
    /// that ask for the same store object.
    @MainActor private static var stores: [UUID: WKWebsiteDataStore] = [:]
    /// The spaces signed in as their profile is (see Space.sharesSignIns).
    @MainActor static var sharing: Set<UUID> = []
    /// The profile of each space not in Personal.
    @MainActor static var owners: [UUID: UUID] = [:]

    /// What the stores are made from: which spaces share their profile's,
    /// and whose profile each is.
    @MainActor static func know(_ spaces: [Space]) {
        sharing = Set(spaces.filter { $0.sharesSignIns == true }.map(\.id))
        owners = Dictionary(spaces.compactMap { space in space.profile.map { (space.id, $0) } }, uniquingKeysWith: { a, _ in a })
    }

    @MainActor static func profile(of id: UUID) -> UUID { owners[id] ?? Profile.personalID }

    /// The space whose own store this is, for one with sign-ins of its own.
    @MainActor static func space(owning store: WKWebsiteDataStore) -> UUID? {
        stores.first { $0.value === store }?.key
    }

    /// A space's store: its profile's, unless it has sign-ins of its own.
    @MainActor static func store(for id: UUID) -> WKWebsiteDataStore {
        if id == Space.firstID || sharing.contains(id) { return Profiles.store(profile(of: id)) }
        if let made = stores[id] { return made }
        let made = WKWebsiteDataStore(forIdentifier: Store.webKitID(id))
        if Store.keepsSignIns { Store.followSignIns(made) } else { Store.followCookies(made) }
        stores[id] = made
        return made
    }

    /// The shared store and every space's own made so far. Not a private
    /// tab's: each has a store of its own, out of this list on purpose, so
    /// tracking prevention stays on there whatever the switch says.
    @MainActor static var everyStore: [WKWebsiteDataStore] {
        [Store.websites] + Profiles.madeStores + stores.values
    }

    /// A space's store and everything in it, gone. What it holds — cookies,
    /// sign-ins, storage, caches — is emptied at once. The store itself
    /// WebKit won't remove while this run still holds on to it, however
    /// closed its tabs, so it is written down and removed at the next
    /// launch if the tries in between don't manage.
    @MainActor static func erase(_ id: UUID) {
        guard id != Space.firstID else { return }
        // And once more a moment later, for what its closing tabs were
        // still writing — the cache of the page on screen, for one.
        let store = store(for: id)
        // The space's downloads would have kept its store, and asked with
        // its cookies again: they go with it.
        Browsers.acting.forgetDownloads(of: store)
        let everything = WKWebsiteDataStore.allWebsiteDataTypes()
        store.removeData(ofTypes: everything, modifiedSince: .distantPast) {}
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            store.removeData(ofTypes: everything, modifiedSince: .distantPast) {}
        }
        stores[id] = nil
        let pending = Set(Store.settings.stringArray(forKey: "spaces.erasing") ?? []).union([Store.webKitID(id).uuidString])
        Store.settings.set(pending.sorted(), forKey: "spaces.erasing")
        sweep()
        for delay in [3.0, 15.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { sweep() }
        }
    }

    /// Every store of a deleted space that is still there, tried again.
    @MainActor static func sweep() {
        for text in Store.settings.stringArray(forKey: "spaces.erasing") ?? [] {
            guard let id = UUID(uuidString: text) else { continue }
            Task { @MainActor in
                do { try await WKWebsiteDataStore.remove(forIdentifier: id) } catch {
                    // Gone already is as good as removed; anything else is
                    // tried again later.
                    let left = await WKWebsiteDataStore.allDataStoreIdentifiers
                    guard !left.contains(id) else { return }
                }
                let now = (Store.settings.stringArray(forKey: "spaces.erasing") ?? []).filter { $0 != text }
                Store.settings.set(now, forKey: "spaces.erasing")
            }
        }
    }
}

/// A space's row of tabs while another space is on screen.
struct Parked {
    var tabs: [Tab]
    var active: Tab.ID?
    var splits: [TabSplit] = []
    /// The row's tabs that aren't pins, as the column draws them while the
    /// row passes during a swipe between spaces: a pair's other half isn't
    /// a row of its own. Its pins and folders are drawn as on screen (see
    /// Folders.lines).
    @MainActor var loose: [Tab] {
        tabs.filter { tab in
            tab.pin == nil && !splits.contains { $0.tabs.contains(tab.id) && $0.left != tab.id }
        }
    }

    /// The tab in front, as the column marks it: a pair's left page.
    var front: Tab.ID? {
        splits.first { pair in active.map(pair.tabs.contains) ?? false }?.left ?? active
    }
}

extension Browser {
    var space: Space { spaces.first { $0.id == spaceID } ?? spaces[0] }

    /// Every tab of the spaces not on screen, for the sleep timer.
    var parkedTabs: [Tab] { parked.values.flatMap(\.tabs) }

    /// Where a download lands: the space's folder, or the one in Settings.
    var downloadsFolder: URL {
        guard let path = space.downloads else { return prefs.downloads }
        return URL(fileURLWithPath: path)
    }

    /// Where the space on screen sits among them: one past the last while
    /// the card for a new one is up.
    var spaceAt: Int {
        makingSpace ? spaces.count : (spaces.firstIndex { $0.id == spaceID } ?? 0)
    }

    /// ⌃1–⌃9, and the menu on the space's dot.
    func switchSpace(to id: UUID) {
        enter(id)
    }

    private func enter(_ id: UUID) {
        guard id != spaceID, let to = spaces.firstIndex(where: { $0.id == id }) else { return }
        // Which way the icon at the foot turns over: the way the spaces lie.
        if !makingSpace { spaceStep = to > (spaces.firstIndex { $0.id == spaceID } ?? 0) ? 1 : -1 }
        cancelTabEdit()
        // A peek's page was made with the space left's sign-ins: kept in the
        // next one, it would be another profile's page in its row.
        if peekTab != nil { closePeek() }
        // A video playing in the tab on screen goes into picture in picture,
        // as it does when you go to another tab.
        leaving()
        writeSession(now: true)
        for tab in tabs where visibleTabIDs.contains(tab.id) { tab.touch() }

        // The row on screen is parked as it is, sound and all: music or a
        // stream keeps playing in the space you left, as it does in a tab
        // you left. ⌘⇧M, or its speaker, stops it.
        parked[spaceID] = Parked(tabs: tabs, active: activeID, splits: splits)

        spaceID = id
        // The space new pages are made in, when this is the window in front;
        // and the one to come back to, when this is the oldest window.
        if Browsers.front === self || Browsers.front == nil { Spaces.current = id }
        if usesFiles { Store.settings.set(id.uuidString, forKey: "space.current") }
        if let back = parked.removeValue(forKey: id), !back.tabs.isEmpty {
            // Nothing in front there (a fresh start, see Session.startFresh):
            // an empty tab beside its pins, as at launch, not the first pin.
            // One that has gone from the row falls to its first tab that isn't a pin.
            let front = back.active.map { active in
                back.tabs.contains { $0.id == active } ? active : (back.tabs.first { $0.pin == nil } ?? back.tabs[0]).id
            }
            showRow(back.tabs, active: front, splits: back.splits, blank: true)
            // Back in the space, on the tab whose video went out: home again.
            if let id = pictured, visibleTabIDs.contains(id) { unpicture() }
            for tab in tabs where visibleTabIDs.contains(tab.id) {
                if !tab.wake() { tab.revive() }
            }
        } else {
            showRow([], active: nil)
            restoreSession()
        }
        editing = active?.isBlank ?? true
        typed = ""
        // A row read from its file just now may hold tabs whose time ran out
        // while it wasn't in memory (see Closing.swift).
        closeLeftAlone()
        askFocus()
        // Beside the space's icon when the tabs are on screen (SpaceDot);
        // folded away, at the bottom.
        if folded && !peeking { announce(space.name) }
    }

    /// Every other space's row, made ahead of time, so the column can show
    /// the next space beside this one while two fingers bring it in.
    func preloadSpaces() {
        for space in spaces where space.id != spaceID && parked[space.id] == nil {
            parked[space.id] = loadRow(space.id)
        }
    }

    func switchSpace(index: Int) {
        guard spaces.indices.contains(index) else { return }
        switchSpace(to: spaces[index].id)
    }

    /// The icon a new space gets unless told: the first no space wears yet.
    var freeIcon: String {
        let used = Set(spaces.map(\.symbol))
        return Spaces.icons.first { !used.contains($0) } ?? "briefcase"
    }

    /// A new space — signed in where the others are, or starting afresh with
    /// its own cookies and sign-ins. By default it starts empty and on screen.
    /// A new space in a profile: signed in as that profile is. Sign-ins of
    /// its own (`sharesSignIns` false) are for the bench's tests of spaces
    /// from before profiles, and nothing else.
    func addSpace(named name: String, icon: String? = nil, profile: UUID? = nil, sharesSignIns: Bool = true) {
        makingSpace = false
        var made = Space(id: UUID(), name: name, colour: 0, icon: icon ?? freeIcon, sharesSignIns: sharesSignIns)
        let profile = profile ?? newSpaceProfile ?? profileID
        made.profile = profile == Profile.personalID ? nil : profile
        newSpaceProfile = nil
        spaces.append(made)
        Spaces.write(spaces)
        if let afterSpaceCreated {
            self.afterSpaceCreated = nil
            afterSpaceCreated(made)
        } else {
            switchSpace(to: made.id)
        }
    }

    /// Dragged to another place among the dots. ⌃1–⌃9 follow the order.
    func moveSpace(_ id: UUID, to index: Int) {
        guard let from = spaces.firstIndex(where: { $0.id == id }), spaces.indices.contains(index), from != index else { return }
        spaces.move(fromOffsets: IndexSet(integer: from), toOffset: index > from ? index + 1 : index)
        Spaces.write(spaces)
    }

    /// "New Space…": the card for a new space, in the column or the bar.
    /// `profile`: the one it starts in, the card's choice at first; the
    /// profile on screen when none is said.
    func askForSpace(in profile: UUID? = nil, then onCreated: ((Space) -> Void)? = nil) {
        afterSpaceCreated = onCreated
        newSpaceProfile = profile
        // In place, where the next space would come in, in the column or the
        // bar alike; a question only while the tabs are folded out of sight.
        if !folded || peeking {
            let here = spaces.firstIndex { $0.id == spaceID } ?? 0
            SpaceSwipe.shared.start(for: self)
            SpaceSwipe.shared.slide(self, to: spaces.count, from: here)
        } else {
            Ask.newSpace(in: profile ?? profileID,
                then: { name, profile in self.addSpace(named: name, profile: profile) },
                cancelled: { self.cancelSpaceCreation() }
            )
        }
    }

    func cancelSpaceCreation() {
        afterSpaceCreated = nil
    }

    func renameSpace(_ id: UUID, to name: String) {
        guard let at = spaces.firstIndex(where: { $0.id == id }), !name.isEmpty else { return }
        spaces[at].name = name
        Spaces.write(spaces)
    }

    func setSpaceIcon(_ id: UUID, to icon: String) {
        guard let at = spaces.firstIndex(where: { $0.id == id }) else { return }
        spaces[at].icon = icon
        Spaces.write(spaces)
    }

    func setSpaceDownloads(_ id: UUID, to folder: URL?) {
        guard let at = spaces.firstIndex(where: { $0.id == id }) else { return }
        spaces[at].downloads = folder?.path
        Spaces.write(spaces)
    }

    /// A space, its tabs, and its cookies and sign-ins, gone. The first one
    /// stays: it is where everything was before there were spaces.
    func deleteSpace(_ id: UUID) {
        guard id != Space.firstID, let at = spaces.firstIndex(where: { $0.id == id }) else { return }
        if spaceID == id { switchSpace(to: Space.firstID) }
        for tab in parked.removeValue(forKey: id)?.tabs ?? [] { tab.close() }
        let shared = spaces[at].sharesSignIns == true
        spaces.remove(at: at)
        Spaces.write(spaces)
        Session.erase(space: id)
        // Gone from the other windows too: their rows there, and the space
        // itself if one was showing it (the list's change moves it).
        for other in Browsers.all where other !== self { other.forget(space: id) }
        Browsers.forgetClosed(space: id)
        Pins.forget(id)
        // A space signed in with the others has nothing of its own to erase:
        // its cookies are theirs.
        if !shared { Spaces.erase(id) }
    }
}

extension Browser {
    /// A space deleted in another window: this window's row there goes.
    func forget(space id: UUID) {
        for tab in parked.removeValue(forKey: id)?.tabs ?? [] { tab.close() }
        record.rows[id.uuidString] = nil
    }
}
