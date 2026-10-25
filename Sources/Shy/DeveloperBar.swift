import SwiftUI

// Developer Mode: a thin bar along the bottom of the page, for whoever is
// building the page rather than reading it. It says the address of the page
// on screen in full — path, query and fragment, where the tab itself says
// only the site (see AtRest.swift) — as text that can be picked and copied, and has one button
// for the Web Inspector (see Inspector.swift). Turned on and off from a
// tab's right-click menu, for every window at once (Preferences.developer).

/// The bar, for the tab in front. It watches that tab, so a page moving on
/// redraws the address; the window hands down a new tab when you switch.
struct DeveloperBar: View {
    @ObservedObject var browser: Browser

    var body: some View {
        Group {
            if let tab = browser.active {
                Line(browser: browser, tab: tab)
            } else {
                Color.clear
            }
        }
        .frame(height: 26)
        .frame(maxWidth: .infinity)
        .background(Palette.ground)
        .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 1) }
    }

    #if DEBUG
    /// The address a bar on screen shows, for the bench to ask; nil with
    /// none up.
    static var shown: String?
    #endif

    private struct Line: View {
        let browser: Browser
        @ObservedObject var tab: Tab

        /// The page on screen, never one only on its way: a page can start
        /// a load of another site's address and stall it, and that address
        /// must not stand under what is still its own (see Tab.restAddress).
        /// Without the name and password an address can carry before its
        /// host, which are a secret, or a way to dress one host as another.
        private var address: String {
            guard let url = tab.restAddress else { return "" }
            guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  parts.user != nil || parts.password != nil else { return url.absoluteString }
            parts.user = nil
            parts.password = nil
            return parts.string ?? ""
        }

        var body: some View {
            HStack(spacing: 6) {
                Text(address)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("Developer address")
                Button { browser.toggleInspector() } label: {
                    Image(systemName: "hammer")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(tab.isWeb ? Palette.muted : Palette.faint)
                        .frame(width: 24, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!tab.isWeb)
                .accessibilityLabel("Web Inspector")
                .help("Show or hide the Web Inspector for this page (⌥⌘I).")
            }
            .padding(.leading, 12)
            .padding(.trailing, 6)
            #if DEBUG
            .onAppear { DeveloperBar.shown = address }
            .onChange(of: address) { _, now in DeveloperBar.shown = now }
            .onDisappear { DeveloperBar.shown = nil }
            #endif
        }
    }
}
