import SwiftUI

// The space on screen as its icon, and what hangs off it: the menu for
// that space and the drawer of all of them. The spaces themselves are in
// Spaces.swift.

/// The space on screen, as its icon: at the column's foot, or before the
/// tabs in the row. One icon however many spaces there are; a click opens
/// the drawer of spaces to go to (SpaceDrawer), a right-click the menu for
/// the one on screen (SpaceMenu). When the space changes the icon turns over the way the spaces
/// went — out on one side, the next one in from the other.
struct SpaceDot: View {
    @ObservedObject var browser: Browser
    @State private var hovering = false
    /// What is drawn, a step behind the browser: the space changes in a
    /// frame with nothing animated (see SpaceSwipe.slide), and the icon
    /// turns over just after, on a change of its own.
    @State private var shown: (key: String, symbol: String)?
    /// The space's name, for a moment after a switch (see naming()).
    @State private var named: String?
    @State private var naming = 0
    @State private var drawer = false

    static let width: CGFloat = 26

    private var symbol: String { browser.makingSpace ? "plus" : browser.space.symbol }
    private var key: String { browser.makingSpace ? "new" : "\(browser.spaceID.uuidString)-\(browser.space.symbol)" }

    var body: some View {
        Button { drawer.toggle() } label: {
            ZStack {
                Image(systemName: shown?.symbol ?? symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(hovering ? Palette.ink : Palette.muted)
                    .id(shown?.key ?? key)
                    // The way the tabs go: sideways in the column; in the bar
                    // across the top, up for the next space, down going back.
                    .transition(.push(from: (browser.spaceStep > 0 ? .trailing : .leading)
                       ))
            }
            .frame(width: SpaceDot.width, height: 26)
            .clipped()
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovering ? Palette.hover : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay { RightClick { SpaceMenu.make(for: browser) } }
        .popover(isPresented: $drawer, arrowEdge: .top) {
            SpaceDrawer(browser: browser) { drawer = false }
        }
        .onHover { hovering = $0 }
        .help("\(browser.space.name) — ⌃1–⌃9, or two fingers \("sideways") over the tabs, to switch")
        .onChange(of: key) { _, now in
            let symbol = symbol
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.22)) { shown = (now, symbol) }
            }
        }
        .onChange(of: browser.spaceID) { _, _ in name() }
        // The name, beside the icon that stands for it, the moment you get
        // there — right of it in the bar, over the first tabs (below, the
        // page would cover it), above it at the column's foot — and
        // gone again: the icon alone is what stays. Over whatever is there,
        // taking no click and moving nothing.
        .overlay(alignment: .bottomLeading) {
            if let named {
                Text(named)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Palette.ground, in: Capsule())
                    .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 1))
                    .shadow(color: .black.opacity(0.10), radius: 10, y: 3)
                    .offset(x: 0, y: -30)
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .bottomLeading)))
            }
        }
        .animation(Motion.quick, value: hovering)
        .animation(Motion.quick, value: named)
    }

    private func name() {
        guard !browser.makingSpace else { return }
        naming += 1
        let turn = naming
        named = browser.space.name
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            guard turn == naming else { return }
            named = nil
        }
    }
}

/// The dot's right-click menu: what can be done to the space on screen.
/// Going to another, adding one and the order are the drawer's.
@MainActor
enum SpaceMenu {
    /// Menu items call back into Swift through this.
    private final class Action: NSObject {
        let run: () -> Void
        init(_ run: @escaping () -> Void) { self.run = run }
        @objc func fire() { run() }
    }

    private static var actions: [Action] = []

    private static func item(_ title: String, key: String = "", checked: Bool = false, _ run: @escaping () -> Void) -> NSMenuItem {
        let action = Action(run)
        actions.append(action)
        let item = NSMenuItem(title: title, action: #selector(Action.fire), keyEquivalent: key)
        item.target = action
        item.keyEquivalentModifierMask = key.isEmpty ? [] : .control
        item.state = checked ? .on : .off
        return item
    }

    static func make(for browser: Browser) -> NSMenu {
        actions = []
        let menu = NSMenu()
        let here = browser.space
        menu.addItem(item("Rename “\(here.name)”…") {
            Ask.name("Rename Space", placeholder: here.name, initial: here.name, confirm: "Rename") { browser.renameSpace(here.id, to: $0) }
        })
        let icons = NSMenu()
        for (symbol, name) in zip(Spaces.icons, Spaces.iconNames) {
            let choice = item(name, checked: here.symbol == symbol) { browser.setSpaceIcon(here.id, to: symbol) }
            choice.image = NSImage(systemSymbolName: symbol, accessibilityDescription: name)
            icons.addItem(choice)
        }
        let icon = NSMenuItem(title: "Icon", action: nil, keyEquivalent: "")
        icon.submenu = icons
        menu.addItem(icon)
        // The profile it signs in, keeps history and bookmarks as.
        let profiles = NSMenu()
        for profile in Profiles.shared.list {
            profiles.addItem(item(profile.name, checked: here.profileID == profile.id) { browser.askToMove(here.id, to: profile.id) })
        }
        profiles.addItem(.separator())
        profiles.addItem(item("New Profile…") {
            Ask.name("New Profile", detail: "Signed out of everything, with no history or bookmarks. “\(here.name)” moves into it.",
                     placeholder: "Work", confirm: "Create") { name in
                browser.setProfile(Profiles.shared.add(named: name).id, of: here.id)
            }
        })
        let profile = NSMenuItem(title: "Profile", action: nil, keyEquivalent: "")
        profile.submenu = profiles
        menu.addItem(profile)
        let folder = here.downloads.map { URL(fileURLWithPath: $0).lastPathComponent }
        menu.addItem(item(folder.map { "Downloads to “\($0)”…" } ?? "Downloads Folder…") {
            Ask.folder { browser.setSpaceDownloads(here.id, to: $0) }
        })
        if folder != nil {
            menu.addItem(item("Downloads to the Folder in Settings") { browser.setSpaceDownloads(here.id, to: nil) })
        }
        if !here.isFirst {
            menu.addItem(.separator())
            menu.addItem(item("Delete “\(here.name)”…") {
                Ask.sure("Delete “\(here.name)”?", detail: "Its tabs close, and its cookies and sign-ins are erased from this Mac. History and bookmarks stay.", confirm: "Delete") {
                    browser.deleteSpace(here.id)
                }
            })
        }
        return menu
    }
}

/// The dot's drawer: every space with its icon, name and ⌃ number. A click
/// goes there; dragging one up or down puts it in another place, which is
/// the swipe's order and ⌃1–⌃9's; + makes a new one.
struct SpaceDrawer: View {
    @ObservedObject var browser: Browser
    let close: () -> Void
    /// The space being carried, and how far.
    @State private var carried: UUID?
    @State private var travel: CGFloat = 0
    @State private var hovered: UUID?

    static let row: CGFloat = 30

    /// Where the carried space would land, from how far it has gone.
    private func landing(_ from: Int) -> Int {
        min(max(0, from + Int((travel / SpaceDrawer.row).rounded())), browser.spaces.count - 1)
    }

    var body: some View {
        let spaces = browser.spaces
        let from = carried.flatMap { id in spaces.firstIndex { $0.id == id } }
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(spaces.enumerated()), id: \.element.id) { index, space in
                entry(space, number: index)
                    .offset(y: offset(index, from: from))
                    .zIndex(space.id == carried ? 1 : 0)
                    .gesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { drag in
                                carried = space.id
                                travel = drag.translation.height
                            }
                            .onEnded { _ in
                                if let from { browser.moveSpace(space.id, to: landing(from)) }
                                carried = nil
                                travel = 0
                            }
                    )
            }
            Rectangle().fill(Palette.hairline).frame(height: 1).padding(.vertical, 4)
            Button {
                close()
                // Once the drawer is away: the card comes in where it was.
                DispatchQueue.main.async { browser.askForSpace() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus").frame(width: 18)
                    Text("New Space")
                    Spacer(minLength: 0)
                }
                .font(.system(size: 12.5))
                .foregroundStyle(hovered == SpaceDrawer.adding ? Palette.ink : Palette.muted)
                .padding(.horizontal, 8)
                .frame(height: SpaceDrawer.row)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(hovered == SpaceDrawer.adding ? Palette.hover : .clear))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovered = $0 ? SpaceDrawer.adding : nil }
        }
        .padding(6)
        .frame(width: 220)
        .animation(Motion.quick, value: carried == nil ? 0 : landing(from ?? 0))
    }

    /// The + row's stand-in for a space under the pointer.
    private static let adding = UUID()

    /// The carried space follows the pointer; the ones it passes make room.
    private func offset(_ index: Int, from: Int?) -> CGFloat {
        guard let from else { return 0 }
        if index == from { return travel }
        let to = landing(from)
        if from < to, index > from, index <= to { return -SpaceDrawer.row }
        if from > to, index < from, index >= to { return SpaceDrawer.row }
        return 0
    }

    private func entry(_ space: Space, number index: Int) -> some View {
        let here = space.id == browser.spaceID
        let lit = here || hovered == space.id || carried == space.id
        return HStack(spacing: 8) {
            Image(systemName: space.symbol)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 18)
            Text(space.name)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            if index < 9 {
                Text("⌃\(index + 1)")
                    .foregroundStyle(Palette.muted)
                    .monospacedDigit()
            }
        }
        .font(.system(size: 12.5, weight: here ? .medium : .regular))
        .foregroundStyle(here ? Palette.ink : Palette.ink.opacity(0.85))
        .padding(.horizontal, 8)
        .frame(height: SpaceDrawer.row)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(here ? Palette.wash : lit ? Palette.hover : .clear))
        .contentShape(Rectangle())
        .onHover { hovered = $0 ? space.id : (hovered == space.id ? nil : hovered) }
        .onTapGesture {
            close()
            if !here { browser.switchSpace(to: space.id) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(here ? "\(space.name), the space on screen" : space.name)
    }
}
