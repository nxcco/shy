import AppKit
import WebKit

// Dark pages for sites that have no dark look of their own.
//
// A site that answers prefers-color-scheme already goes dark with the frame
// (see Tab.build), so this is only for the ones that stay white. WebKit has
// no switch for it: Chromium darkens as it paints, and the paint-time filter
// Mail uses (-apple-color-filter) isn't parsed in a web view, flag or no
// flag (macOS 27.2). So a page is darkened in its own colours: each rule of
// its that sets one gets a dark twin (DuskColours.swift), and pictures are
// never touched. The twins take a moment to make, and until they are ready,
// or on a Mac whose WebKit can't do relative colours (before macOS 15), the
// page is turned over with a CSS filter on its root and the pictures on it
// are turned back.
//
// Whether a site needs it is measured, never read off what the site says:
// plenty declare `color-scheme: light dark` and only mean their form
// controls, and plenty more keep a dark theme behind a setting of their own.
// The page's colours are sampled across the screen just before its first
// frame, and again whenever it changes its theme; a site already dark is
// left alone. The filter changes no computed colour, and the twins are set
// aside while it looks, so the measuring always sees the site's own colours.
//
// Off unless turned on in Settings › Appearance, and only ever while the
// frame is dark. ⇧⌘D turns it off, or on, for the site you're on, and is
// kept; ⌥⇧⌘D pauses it everywhere until pressed again or Shy quits.

@MainActor
final class Dusk: ObservableObject {
    static let shared = Dusk()

    /// Settings › Appearance. Off, pages get nothing at all.
    var on = false {
        didSet { if on != oldValue { revision += 1 } }
    }

    /// For now, not for good: forgotten when Shy quits.
    @Published private(set) var paused = false

    /// Bumped whenever what the open pages should show has changed, for
    /// every window to pass on to its tabs.
    @Published private(set) var revision = 0

    /// The sites someone switched against what was measured: darkened on a
    /// site that measured dark, or left alone on one that measured light.
    /// A choice that agrees with the measuring isn't kept.
    /// Kept per profile (see SiteMemory).
    private var sites: [UUID: [String: Bool]] = [:]

    private func sites(in profile: UUID) -> [String: Bool] {
        if let known = sites[profile] { return known }
        let read = Store.settings.dictionary(forKey: SiteMemory.key("dusk.sites", profile)) as? [String: Bool] ?? [:]
        sites[profile] = read
        return read
    }

    /// What each site measured this session: true, dark by itself. Only so a
    /// site's next page can be darkened before its first frame rather than
    /// just after it. Never written down: kept, it would be a list of every
    /// site visited, outside History and its Clear.
    private var seen: [String: Bool] = [:]

    var active: Bool { on && !paused }

    /// Pages take the window's appearance, and the window the app's.
    static var frameIsDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// The same host the hidden elements are kept by: no www.
    static func host(of url: URL?) -> String? {
        guard let url, ["http", "https"].contains(url.scheme?.lowercased()),
              let host = url.host()?.lowercased(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    func pause(_ paused: Bool) {
        guard self.paused != paused else { return }
        self.paused = paused
        revision += 1
    }

    /// `native`: what the page measured, true for dark by itself, nil when it
    /// hasn't been measured yet (it is then taken for light, which is what
    /// gets it darkened).
    func choose(_ darkened: Bool, for host: String, native: Bool?, in profile: UUID) {
        let measured = !(native ?? false)
        var list = sites(in: profile)
        if darkened == measured { list[host] = nil } else { list[host] = darkened }
        sites[profile] = list
        Store.settings.set(list, forKey: SiteMemory.key("dusk.sites", profile))
        revision += 1
    }

    func saw(_ host: String, dark: Bool) {
        seen[host] = dark
    }

    /// A page's darkening changed; the View menu's line says so.
    func heard() { objectWillChange.send() }

    /// Whether a page on `host` is darkened from its first frame: on, not
    /// paused, Shy dark, and the site switched on by hand or measured
    /// light already this session. Nothing goes into any other page.
    func wanted(_ host: String?, in profile: UUID) -> Bool {
        guard active, Dusk.frameIsDark, let host else { return false }
        if let chosen = sites(in: profile)[host] { return chosen }
        return seen[host] == false
    }

    /// Whether a page on `host` is still to be looked at, from outside it
    /// (see look): on, Shy dark, and neither switched nor known light.
    func unsure(_ host: String?, in profile: UUID) -> Bool {
        guard active, Dusk.frameIsDark, let host, sites(in: profile)[host] == nil else { return false }
        return seen[host] != false
    }

    /// For each new document on `host`, or nil. `light`: what the page up
    /// now was just seen to be, for a private tab, which keeps nothing.
    func script(for host: String?, light: Bool = false, in profile: UUID) -> String? {
        guard let host, wanted(host, in: profile) || light && active && Dusk.frameIsDark && sites(in: profile)[host] != false else { return nil }
        return Dusk.page(config(for: host, light: light, in: profile))
    }

    /// For the page up now: taking it over, or letting it go.
    func update(for host: String?, in profile: UUID) -> String {
        script(for: host, in: profile) ?? Dusk.letGo
    }

    static let letGo = "window.__officeDusk && window.__officeDusk.update({ on: false })"

    /// A private tab's ⇧⌘D: this page, whatever it measured, kept nowhere.
    func forced(for host: String, _ on: Bool) -> String {
        on ? Dusk.page(config(for: host, chosen: true, in: Profile.personalID)) : "window.__officeDusk && window.__officeDusk.force(false)"
    }

    /// Only the one site's answers, never the list of every site switched
    /// or measured: a page is told what it needs about itself.
    private func config(for host: String, light: Bool = false, chosen: Bool? = nil, in profile: UUID) -> String {
        // "filter" keeps a page to the filter even where the browser can do
        // colours: for comparing the two, set by hand.
        let mode = Store.settings.string(forKey: "dusk.mode") ?? "colours"
        let known: Bool? = light ? false : seen[host]
        let config: [String: Any] = ["on": true, "host": host, "mode": mode,
                                     "choice": (chosen ?? sites(in: profile)[host]).map { $0 as Any } ?? NSNull(),
                                     "known": known.map { $0 as Any } ?? NSNull()]
        guard let data = try? JSONSerialization.data(withJSONObject: config),
              let json = String(data: data, encoding: .utf8) else { return "{\"on\":false}" }
        return json
    }

    /// Whether a page is dark, from outside it: a picture of what it shows,
    /// 48 pixels wide, and how much of it is light. Nothing goes into the
    /// page to find out, so a dark page, or one already dark by itself, gets
    /// no script, observer or sheet at all. Nil when there is no picture to
    /// be had.
    static func look(at web: WKWebView, _ answer: @escaping (Bool?) -> Void) {
        let config = WKSnapshotConfiguration()
        config.snapshotWidth = 48
        web.takeSnapshot(with: config) { image, _ in
            guard let cg = image?.cgImage(forProposedRect: nil, context: nil, hints: nil),
                  let srgb = CGColorSpace(name: CGColorSpace.sRGB) else { return answer(nil) }
            let w = cg.width, h = cg.height
            var pixels = [UInt8](repeating: 0, count: w * h * 4)
            let drawn: Bool = pixels.withUnsafeMutableBytes { raw in
                guard let context = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                              bytesPerRow: w * 4, space: srgb,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                context.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
                return true
            }
            guard drawn, w * h > 0 else { return answer(nil) }
            func linear(_ c: UInt8) -> Double {
                let v = Double(c) / 255
                return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            var lit = 0
            for i in stride(from: 0, to: pixels.count, by: 4)
            where 0.2126 * linear(pixels[i]) + 0.7152 * linear(pixels[i + 1]) + 0.0722 * linear(pixels[i + 2]) > 0.35 {
                lit += 1
            }
            answer(lit * 2 < w * h)
        }
    }

    private static func page(_ config: String) -> String {
        "(\(whole))(\(config));"
    }

    /// The page script with the colour engine in its place (see DuskColours.swift).
    private static let whole = script.replacingOccurrences(of: DuskColours.slot, with: DuskColours.engine)

    /// The shade under the page, where a scroll past its end shows: the
    /// white a light page left there, turned over as the filter turns it.
    static let underPage = NSColor(srgbRed: 0.09, green: 0.09, blue: 0.09, alpha: 1)

    /// Where the page script lives, run as a function of its settings. One
    /// per main frame: a frame inside is turned over with its page, except
    /// for the ones turned back with the pictures.
    ///
    /// A page is darkened in its own colours where the browser can (see
    /// DuskColours.swift), and by the filter until they are ready, or where
    /// it can't. The page is filtered `invert hue-rotate contrast`; what is turned back
    /// is filtered by the exact reverse, in reverse order, so a photo comes
    /// out as it went in. The contrast of .85 is what keeps white from going
    /// to pure black and black text from going to pure white.
    static let script = Scripts.load("dusk")
}

/// A page saying whether it is darkened, and what it measured.
final class DuskRelay: NSObject, WKScriptMessageHandler {
    static let name = "officeDusk"

    weak var tab: Tab?

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let said = message.body as? [String: Any] else { return }
        let frame = message.frameInfo
        MainActor.assumeIsolated {
            guard let tab, let web = tab.built, web === message.webView else { return }
            // A frame asking whether its page is darkened: kept, to be told
            // again whenever that changes, and told now.
            guard frame.isMainFrame else {
                guard said["frame"] as? Bool == true else { return }
                tab.duskFrames.append(frame)
                DuskRelay.tell(frame, tab.dusked, in: web) { gone in if gone { tab.duskFrames.removeAll { $0 === frame } } }
                return
            }
            let on = said["on"] as? Bool ?? false
            let dark = said["dark"] as? Bool ?? false
            if said["known"] as? Bool == true {
                tab.duskNative = dark
                // A private tab remembers nothing, not even this.
                if !tab.shy, let host = Dusk.host(of: web.url) { Dusk.shared.saw(host, dark: dark) }
            }
            if tab.dusked != on {
                tab.dusked = on
                Dusk.shared.heard()
                // Every frame on the page follows it.
                for frame in tab.duskFrames {
                    DuskRelay.tell(frame, on, in: web) { gone in if gone { tab.duskFrames.removeAll { $0 === frame } } }
                }
            }
            web.underPageBackgroundColor = on ? Dusk.underPage : nil
        }
    }

    /// A frame's page is darkened, or not. A frame that has gone since
    /// (its page moved on, or it was taken out) answers with an error, and
    /// is forgotten.
    @MainActor static func tell(_ frame: WKFrameInfo, _ on: Bool, in web: WKWebView, gone: @escaping (Bool) -> Void) {
        web.evaluateJavaScript("window.__officeDusk && window.__officeDusk.top(\(on))", in: frame, in: Web.world) { result in
            if case .failure = result { gone(true) }
        }
    }
}
