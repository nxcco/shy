import SwiftUI

/// A new space, made where the next one would have been: its name, its
/// icon, and on its way. Escape, Cancel or two fingers back leave it.
struct NewSpaceCard: View {
    @ObservedObject var browser: Browser
    /// In the bar across the top: one row, the height of the tabs.
    var inline = false
    @State private var name = ""
    @State private var icon = "briefcase"
    @State private var choosing = false
    /// The profile it is in: signed in, and keeping history and bookmarks,
    /// as that profile does.
    @State private var profile = Profile.personalID
    @ObservedObject private var profiles = Profiles.shared
    @State private var hovering = false
    @FocusState private var typing: Bool

    /// The profiles to choose from, and New Profile…, which makes one.
    private var profilePicker: some View {
        Picker("", selection: Binding(
            get: { profile },
            set: { picked in
                guard picked == ProfileChoice.making else { return profile = picked }
                Ask.name("New Profile", detail: "Signed out of everything, with no history or bookmarks.",
                         placeholder: "Work", confirm: "Create") { profile = profiles.add(named: $0).id }
            }
        )) {
            ForEach(profiles.list) { Text($0.name).tag($0.id) }
            Divider()
            Text("New Profile…").tag(ProfileChoice.making)
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
        .help("The profile it signs in as, and keeps its history and bookmarks in")
    }

    var body: some View {
        Group {
            if inline {
                // The bar's row: the icon, the name, the sign-ins, and on its way.
                HStack(spacing: 8) {
                    pick(size: 13, box: CGSize(width: 28, height: 26))
                    field
                        .frame(width: 170)
                    profilePicker
                    Pill("Cancel") { cancel() }
                    Pill("Create", filled: true) { create() }
                }
                .frame(height: Metrics.strip)
            } else {
                VStack(spacing: 12) {
                    pick(size: 20, box: CGSize(width: 44, height: 40))
                    VStack(spacing: 4) {
                        Text("New space")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.ink)
                        Text("Its own tabs, in a profile.")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.muted)
                            .multilineTextAlignment(.center)
                    }
                    field
                    profilePicker
                    HStack(spacing: 8) {
                        Pill("Cancel") { cancel() }
                        Pill("Create", filled: true) { create() }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            icon = browser.freeIcon
            profile = browser.newSpaceProfile ?? browser.profileID
            DispatchQueue.main.async { typing = true }
        }
        .onExitCommand(perform: cancel)
    }

    /// The space's icon, and a click on it for the others: they aren't all
    /// laid out in the card.
    private func pick(size: CGFloat, box: CGSize) -> some View {
        Button { choosing = true } label: {
            Image(systemName: icon)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(Palette.ink)
                .frame(width: box.width, height: box.height)
                .background(
                    RoundedRectangle(cornerRadius: inline ? 8 : 10, style: .continuous)
                        .fill(hovering || choosing ? Palette.hover : .clear)
                )
                .contentShape(Rectangle())
                .id(icon)
                .transition(.opacity)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(inline ? "New space — choose its icon" : "Choose an icon")
        .popover(isPresented: $choosing, arrowEdge: .bottom) { icons }
    }

    private var field: some View {
        TextField(inline ? "New space" : "Name", text: $name)
            .textFieldStyle(.plain)
            .font(.system(size: inline ? 12.5 : 13))
            .padding(.horizontal, 10)
            .frame(height: inline ? 26 : 30)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.wash))
            .focused($typing)
            .onSubmit(create)
    }

    /// Every icon, a few to a row, the chosen one on a grey of its own;
    /// picking one puts the list away.
    private var icons: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 4), count: 6), spacing: 4) {
            ForEach(Array(zip(Spaces.icons, Spaces.iconNames)), id: \.0) { symbol, name in
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(symbol == icon ? Palette.ink : Palette.muted)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(symbol == icon ? Palette.wash : .clear)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(Motion.quick) { icon = symbol }
                        choosing = false
                        typing = true
                    }
                    .help(name)
            }
        }
        .padding(10)
    }

    private func create() {
        let named = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !named.isEmpty else { typing = true; return }
        browser.addSpace(named: named, icon: icon, profile: profile)
    }

    /// Back to the space it was made from, the way it came.
    private func cancel() {
        browser.cancelSpaceCreation()
        let back = browser.spaces.firstIndex { $0.id == browser.spaceID } ?? 0
        SpaceSwipe.shared.fly(browser, to: back)
    }
}

/// The menu's New Profile…, among the profiles' ids.
private enum ProfileChoice {
    static let making = UUID(uuidString: "00000000-0000-0000-0000-00000000FFFF") ?? UUID()
}
