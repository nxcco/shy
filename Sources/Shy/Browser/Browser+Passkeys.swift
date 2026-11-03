import SwiftUI
import WebKit

// MARK: - passkeys under a sign-in box

extension Browser {
    struct Suggesting: Equatable {
        let tab: Tab.ID
        var spot: CGRect
        /// The Mac's passkeys for a page waiting for one under its field.
        var passkeys: [Passkeys.Offered]
        /// The page the list was made for: its site, and whether it came in
        /// the clear. A click answers only a page that still is that one.
        let host: String
        let clear: Bool
        /// When it came up. A page can put the caret in a sign-in box
        /// itself, an invisible one under the pointer included: a click that
        /// was already on its way is not a choice, so the list takes none for
        /// its first half second, as Chrome's does.
        var shown = Date()
    }

    /// The caret in a box the page marks for passkeys: the Mac's passkeys
    /// for a page waiting for one hang from the box, and go when the caret
    /// does. Nothing reaches the page until one is picked.
    func hang(from tab: Tab, _ spot: CGRect?) {
        guard let spot else {
            if field?.tab == tab.id { field = nil }
            if looked?.tab == tab.id { looked = nil }
            if pickedInto == tab.id { pickedInto = nil }
            guard suggesting?.tab == tab.id else { return }
            lowering?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self, suggesting?.tab == tab.id else { return }
                suggesting = nil
            }
            lowering = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
            return
        }
        lowering?.cancel()
        field = (tab.id, spot)
        guard tab.id == activeID, pickedInto != tab.id,
              let host = curtain.host(of: tab.pageAddress)
        else { return }
        let inTheClear = tab.pageAddress?.scheme?.lowercased() == "http"
        // The same box, moved by a scroll: the list up follows it, keeping
        // the moment it came up (a click is refused for its first half
        // second, which every frame used to start again).
        if let looked, looked.tab == tab.id, looked.host == host {
            if var up = suggesting, up.tab == tab.id, up.spot != spot {
                up.spot = spot
                suggesting = up
            }
            return
        }
        looked = (tab.id, host)
        let passkeys = Passkeys.shared.offered(in: tab.built)
        guard !passkeys.isEmpty else {
            suggesting = nil
            return
        }
        // What is under the pointer changed: the half second starts again.
        if let up = suggesting, up.tab == tab.id, up.passkeys == passkeys {
            suggesting?.spot = spot
            return
        }
        suggesting = Suggesting(tab: tab.id, spot: spot, passkeys: passkeys, host: host, clear: inTheClear)
    }

    /// One of the passkeys in the list: the Mac's sheet for it, and the
    /// page's request answered with it.
    func choose(_ passkey: Passkeys.Offered) {
        lowering?.cancel()
        guard let list = suggesting, let tab = tabs.first(where: { $0.id == list.tab }), let web = tab.built else { return }
        guard Date().timeIntervalSince(list.shown) > 0.5 else { return }
        suggesting = nil
        guard curtain.host(of: tab.pageAddress) == list.host,
              (tab.pageAddress?.scheme?.lowercased() == "http") == list.clear
        else { return }
        pickedInto = tab.id
        Passkeys.shared.sign(in: web, with: passkey.id)
    }

    func dropChoice() { suggesting = nil }
}
