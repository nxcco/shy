import AppKit
import Combine
import WebKit

// Agents' pages: what an AI agent on this Mac — any MCP client: Claude
// Code, Cursor, Codex and the like — can open and read through shy-mcp,
// the small program beside the app (Sources/ShyMCP), which speaks MCP on its standard
// input and output and passes each call to this over agent.sock.
//
// Off unless switched on in Settings › Agents, which also leaves the mark
// the switch needs at launch (see SwitchMark). What a page you never chose
// can ask of an agent, it can ask of these pages, so they hold as little as
// a page can:
//
// - none of your tabs: these are web views of their own, not tabs. Nothing
//   here can reach a tab of yours, its sign-ins or its history;
// - each page its own private store, gone with the page: no cookies of
//   yours, nothing kept;
// - none of Shy's own page scripts and no extensions: nothing fills in a
//   password, offers a passkey or reads the page on an extension's behalf;
// - http and https only, typed in or followed; a page can't open a window,
//   download, upload a file, use the camera, the microphone or where you
//   are, and its alerts are answered "no" without a word;
// - no script of the agent's own: it reads the page's text, takes a picture
//   of it, clicks and types into what a selector names, nothing else.
//
// Together they are the agent's session: the Agent folder at the top of the
// column, in every space, shows them (AgentSide.swift), and a page picked
// there is shown in the window, to watch or to use yourself. Off show, they
// live in a window of their own off every screen, so a picture of one is a
// picture of something, and never take a window from you.
//
// The one way anything of yours gets in is a handover (see `handOver`), and
// only from your right-click: a copy of one site's sign-in, in a page of
// the session's own, locked to that site, for a time you chose, read-only
// unless you said otherwise, every click asked about unless you said
// otherwise, and every step written down.

@MainActor
final class Agent: NSObject, ObservableObject {
    static let shared = Agent()

    /// Beside the bench's, in the app's own folder.
    static var socket: URL { Store.file("agent.sock") }
    /// Pages open at once, at most.
    static let most = 8
    /// The longest a page's text can be, in characters.
    static let longest = 100_000

    private var server: LocalSocket?
    private(set) var running = false
    /// Its pages, newest last: the Agent folder's rows.
    @Published private(set) var pages: [Page] = []
    /// What the agent last called itself (MCP's clientInfo, from shy-mcp).
    @Published private(set) var client: String?
    /// Questions for you: a click or typing on a handed-over page, waiting.
    @Published private(set) var pending: [Approval] = []
    /// The folder shown as its header alone.
    @Published var folded = false
    private var room: NSWindow?

    /// What can be taken away from agents in Settings › Agents, and the
    /// calls each covers. Waiting, listing and closing its own pages stay.
    enum Ability: String, CaseIterable, Identifiable {
        case open, read, picture, click, type
        var id: String { rawValue }
        var calls: Set<String> {
            switch self {
            case .open: return ["open", "go"]
            case .read: return ["text"]
            case .picture: return ["shot"]
            case .click: return ["click"]
            case .type: return ["type"]
            }
        }
        var title: String {
            switch self {
            case .open: return "Open pages"
            case .read: return "Read a page's text"
            case .picture: return "Take screenshots"
            case .click: return "Click"
            case .type: return "Type into fields"
            }
        }
        var detail: String {
            switch self {
            case .open: return "Only http and https addresses"
            case .read: return "Title, address and visible text"
            case .picture: return "Of what the page shows"
            case .click: return "Buttons, links and labels"
            case .type: return "Into fields and editable text"
            }
        }
    }

    /// The calls Settings lets through now.
    static var allowed: Set<String> {
        let denied = Shared.prefs.agentDenied
        let taken = Ability.allCases.filter { denied.contains($0.rawValue) }.flatMap(\.calls)
        return Set(["open", "go", "text", "shot", "click", "type", "wait", "close", "list", "tools"]).subtracting(taken)
    }

    /// The world an agent's clicks and typing run in, apart from the page's
    /// own scripts, which can neither see nor change them.
    private static let world = WKContentWorld.world(name: "shy-agent")

    /// One of your tabs' sign-ins, copied into a page of the session's own.
    struct Handover {
        /// The site it is locked to: the registrable domain, "google.com".
        let site: String
        /// The page's host when it was handed over, "mail.google.com".
        let host: String
        let cookies: Int
        /// Clicks and typing allowed at all; read-only otherwise.
        let acts: Bool
        /// Each click and each typing asked about first.
        let asks: Bool
        let ends: Date
        /// Why the copied sign-in is gone, once it is.
        var over: String?
    }

    /// One step an agent took on a page, for you to look back over.
    struct Step: Identifiable {
        let id = UUID()
        let at = Date()
        let what: String
    }

    /// A click or typing on a handed-over page, waiting for your yes.
    struct Approval: Identifiable {
        var id = UUID()
        let page: String
        let site: String
        let what: String
        let reply: (Bool) -> Void
    }

    @MainActor
    final class Page: ObservableObject, Identifiable {
        let id: String
        let web: WKWebView
        /// When an agent last asked anything of it (see `tidy`).
        var used = Date()
        @Published var title = ""
        @Published var address: URL?
        /// What the agent is doing to it right now, in a word: "clicking".
        @Published var acting: String?
        @Published var steps: [Step] = []
        @Published var handover: Handover?
        private var watching: [NSKeyValueObservation] = []

        init(id: String, web: WKWebView) {
            self.id = id
            self.web = web
            watching = [
                web.observe(\.title, options: [.new]) { [weak self] _, _ in
                    MainActor.assumeIsolated { self?.title = self?.web.title ?? "" }
                },
                web.observe(\.url, options: [.new]) { [weak self] _, _ in
                    MainActor.assumeIsolated { self?.address = self?.web.url }
                },
            ]
        }

        /// Its handover, while the copied sign-in is still in it.
        var live: Handover? { handover.flatMap { $0.over == nil ? $0 : nil } }

        func note(_ what: String) {
            steps.append(Step(what: what))
            if steps.count > 200 { steps.removeFirst(steps.count - 200) }
        }
    }

    /// A page no agent has asked anything of for this long is closed: what
    /// it runs, it runs from your Mac.
    static let idle: TimeInterval = 10 * 60
    private var tidying: Timer?

    /// What each call is doing, as the folder says it.
    private static let doing = ["open": "opening", "go": "going", "text": "reading", "shot": "looking",
                                "click": "clicking", "type": "typing", "wait": "waiting"]

    /// The page being acted on, and what to, for the folder's header.
    var busy: (page: Page, doing: String)? {
        pages.last { $0.acting != nil }.map { ($0, $0.acting ?? "") }
    }

    // MARK: - starting and stopping

    func start() {
        guard !running else { return }
        let server = LocalSocket(at: Agent.socket) { [weak self] request, answer in
            self?.handle(request, answer)
        }
        guard server.start() else { return }
        self.server = server
        running = true
        tidying = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated { Agent.shared.tidy() }
        }
    }

    private func tidy() {
        let stale = pages.filter { Date().timeIntervalSince($0.used) > Agent.idle }
        stale.forEach(close)
        for page in pages {
            if let handover = page.live, handover.ends <= Date() { end(page, "its time was up") }
        }
    }

    func stop() {
        guard running else { return }
        server?.stop()
        server = nil
        tidying?.invalidate()
        tidying = nil
        running = false
        closeAll()
    }

    /// The session over: every page closed, and with each its store.
    func closeAll() {
        pages.forEach(drop)
        pages = []
        pending.forEach { $0.reply(false) }
        pending = []
        client = nil
    }

    func close(_ page: Page) {
        pending.filter { $0.page == page.id }.forEach { $0.reply(false) }
        pending.removeAll { $0.page == page.id }
        drop(page)
        pages.removeAll { $0 === page }
        if pages.isEmpty { client = nil }
    }

    func page(_ id: String?) -> Page? {
        id.flatMap { id in pages.first { $0.id == id } }
    }

    // MARK: - the calls

    private func handle(_ request: [String: Any], _ given: @escaping ([String: Any]) -> Void) {
        // One answer, and always one, however a page behaves.
        var answered = false
        var acted: Page?
        let answer: ([String: Any]) -> Void = { reply in
            guard !answered else { return }
            answered = true
            acted?.acting = nil
            given(reply)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 45) { answer(["error": "no answer within 45 s"]) }

        let verb = request["do"] as? String ?? ""
        guard Agent.allowed.contains(verb) else {
            return answer(["error": "“\(verb)” is turned off in Shy's Settings › Agents"])
        }
        if let name = request["client"] as? String {
            let plain = String(name.filter { $0.isLetter || $0.isNumber || " -_.".contains($0) }.prefix(40))
            if !plain.isEmpty, client != plain { client = plain }
        }
        // What shy-mcp offers the agent: only what is allowed now.
        if verb == "tools" {
            return answer(["allowed": Agent.allowed.sorted()])
        }
        if verb == "open" {
            guard let url = Agent.web(request["url"]) else { return answer(["error": "open needs an http or https address"]) }
            guard pages.count < Agent.most else {
                return answer(["error": "\(Agent.most) pages are open — close one first"])
            }
            let page = make()
            acted = page
            page.acting = "opening"
            page.note("Opened \(url.host() ?? url.absoluteString)")
            page.web.load(URLRequest(url: url))
            return settle(page, within: 15, answer)
        }
        if verb == "list" {
            return answer(["pages": pages.map(describe)])
        }
        if verb == "close", request["id"] as? String == "all" {
            let count = pages.count
            closeAll()
            return answer(["closed": count])
        }
        guard let page = page(request["id"] as? String) else {
            return answer(["error": "no page “\(request["id"] as? String ?? "")” — open one, or list them"])
        }
        page.used = Date()
        drawn(page)
        if let words = Agent.doing[verb] {
            acted = page
            page.acting = words
        }
        switch verb {
        case "go":
            guard let url = Agent.web(request["url"]) else { return answer(["error": "go needs an http or https address"]) }
            page.note("Went to \(url.host() ?? "")\(url.path())")
            page.web.load(URLRequest(url: url))
            settle(page, within: 15, answer)

        case "wait":
            let seconds = min(30, max(0, (request["seconds"] as? Double) ?? 10))
            settle(page, within: seconds, answer)

        case "text":
            page.note("Read the page")
            run(Agent.reading, on: page) { value, trouble in
                if let trouble { return answer(["error": trouble]) }
                guard var text = value as? String else { return answer(["error": "the page has no text to read"]) }
                var cut = false
                if text.count > Agent.longest { text = String(text.prefix(Agent.longest)); cut = true }
                var said = self.describe(page)
                said["text"] = text
                said["truncated"] = cut
                answer(said)
            }

        case "shot":
            page.note("Took a screenshot")
            let shot = WKSnapshotConfiguration()
            shot.afterScreenUpdates = true
            page.web.takeSnapshot(with: shot) { image, _ in
                MainActor.assumeIsolated {
                    guard let image, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                          let png = bitmap.representation(using: .png, properties: [:])
                    else { return answer(["error": "nothing drawn yet"]) }
                    answer(["png": png.base64EncodedString(), "width": bitmap.pixelsWide, "height": bitmap.pixelsHigh])
                }
            }

        case "click", "type":
            guard let selector = request["selector"] as? String, !selector.isEmpty, selector.count <= 1000 else {
                return answer(["error": "\(verb) needs a selector"])
            }
            let text = request["text"] as? String ?? ""
            guard verb == "click" || text.count <= 10_000 else { return answer(["error": "that is a lot to type"]) }
            let what = verb == "click"
                ? "Click \(Agent.quoted(selector))"
                : "Type \(Agent.quoted(text)) into \(Agent.quoted(selector))"
            let act = {
                page.note(what)
                self.run(verb == "click" ? Agent.clicking : Agent.typing, on: page, ["selector": selector, "text": text]) { value, trouble in
                    let said = trouble ?? value as? String ?? "the page didn't answer"
                    answer(said == "ok" ? ["ok": true] : ["error": said])
                }
            }
            // A page with your sign-in in it: only what you allowed, and
            // asked about first unless you said not to.
            guard let handover = page.live else { return act() }
            guard handover.acts else {
                page.note("Refused: \(what) (read only)")
                return answer(["error": "this page was handed over read-only: the person allowed reading, not clicking or typing"])
            }
            guard handover.asks else { return act() }
            page.acting = "waiting for you"
            ask(page, handover, what) { yes in
                guard yes else {
                    page.note("You refused: \(what)")
                    return answer(["error": "the person said no to this"])
                }
                page.acting = verb == "click" ? "clicking" : "typing"
                act()
            }

        case "close":
            close(page)
            answer(["closed": 1])

        default:
            answer(["error": "unknown call “\(verb)”"])
        }
    }

    /// Short enough for a line in the folder, and plainly someone's words.
    static func quoted(_ text: String) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        return "“" + (flat.count > 60 ? String(flat.prefix(59)) + "…" : flat) + "”"
    }

    /// An http or https address with a host, and nothing else: no file on
    /// this Mac, no page of Shy's own, no other app's scheme.
    static func web(_ value: Any?) -> URL? {
        guard let text = value as? String, text.count <= 8192,
              let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host(), !host.isEmpty
        else { return nil }
        return url
    }

    private func describe(_ page: Page) -> [String: Any] {
        var said: [String: Any] = ["id": page.id, "url": page.web.url?.absoluteString ?? "", "title": page.web.title ?? "",
                                   "loading": page.web.isLoading]
        if let handover = page.handover {
            said["handedOver"] = handover.over == nil
                ? (handover.acts ? (handover.asks ? "signed in to \(handover.site); each click and typing is asked about" : "signed in to \(handover.site)") : "signed in to \(handover.site), read-only")
                : "the sign-in to \(handover.site) was taken back: \(handover.over ?? "")"
        }
        return said
    }

    /// Answered once the page has stopped loading, or when the time is up.
    private func settle(_ page: Page, within seconds: Double, _ answer: @escaping ([String: Any]) -> Void) {
        let until = Date().addingTimeInterval(seconds)
        func look() {
            guard pages.contains(where: { $0 === page }) else { return answer(["error": "the page was closed"]) }
            if !page.web.isLoading || Date() >= until { return answer(describe(page)) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { look() }
        }
        // A turn first: a load just asked for hasn't started yet.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { look() }
    }

    /// Run without a user gesture. WebKit's public way runs a script as
    /// though the page had been clicked, and an agent's click would then
    /// let the page do what only a person's click allows: write to your
    /// clipboard, play sound, open a system sheet. WebKit's own variant
    /// without one is asked for by name; without it nothing is run.
    private func run(_ script: String, on page: Page, _ arguments: [String: Any] = [:], then: @escaping (Any?, String?) -> Void) {
        typealias Done = @convention(block) (Any?, NSError?) -> Void
        typealias Call = @convention(c) (AnyObject, Selector, NSString, NSDictionary, WKFrameInfo?, WKContentWorld, ObjCBool, Done) -> Void
        let call = NSSelectorFromString("_callAsyncJavaScript:arguments:inFrame:inContentWorld:withUserGesture:completionHandler:")
        guard page.web.responds(to: call), let imp = page.web.method(for: call) else {
            return then(nil, "this version of macOS can't act on a page without a click of its own")
        }
        let done: Done = { value, error in
            MainActor.assumeIsolated { then(value, error?.localizedDescription) }
        }
        unsafeBitCast(imp, to: Call.self)(page.web, call, script as NSString, arguments as NSDictionary, nil, Agent.world, false, done)
    }

    // MARK: - asking you

    /// Waits for your yes in the folder; no answer in 40 seconds is a no.
    private func ask(_ page: Page, _ handover: Handover, _ what: String, _ reply: @escaping (Bool) -> Void) {
        var replied = false
        let id = UUID()
        let once: (Bool) -> Void = { [weak self] yes in
            guard !replied else { return }
            replied = true
            self?.pending.removeAll { $0.id == id }
            reply(yes)
        }
        pending.append(Approval(id: id, page: page.id, site: handover.site, what: what, reply: once))
        NSApp.requestUserAttention(.informationalRequest)
        DispatchQueue.main.asyncAfter(deadline: .now() + 40) { once(false) }
    }

    func answer(_ approval: Approval, _ yes: Bool) {
        approval.reply(yes)
    }

    // MARK: - handing over

    /// The cookies a page of `host` is sent: those set for it, and for a
    /// domain it is under. Nothing for a sibling or a parent's other
    /// children, and nothing past its date.
    static func sent(_ cookie: HTTPCookie, to host: String) -> Bool {
        if let expires = cookie.expiresDate, expires <= Date() { return false }
        let domain = cookie.domain.lowercased()
        if domain.hasPrefix(".") {
            let bare = String(domain.dropFirst())
            return host == bare || host.hasSuffix("." + bare)
        }
        return host == domain
    }

    /// What a handover of this tab would copy: its address, and the
    /// cookies its page is sent.
    static func offer(_ tab: Tab, _ found: @escaping (URL, [HTTPCookie]) -> Void) {
        guard let url = Agent.web(tab.address?.absoluteString), let host = url.host()?.lowercased() else { return }
        tab.store.httpCookieStore.getAllCookies { all in
            MainActor.assumeIsolated { found(url, all.filter { sent($0, to: host) }) }
        }
    }

    /// A page of the session's own, with a copy of `cookies` and nothing
    /// else of yours, at `url`. Nil, with why, when there's no room.
    @discardableResult
    func handOver(_ url: URL, cookies: [HTTPCookie], acts: Bool, asks: Bool, minutes: Int) -> String? {
        guard running else { return "Agents are off in Settings › Agents" }
        guard pages.count < Agent.most else { return "The agent has \(Agent.most) pages open — close one first" }
        guard let host = url.host()?.lowercased() else { return "Not a page on the web" }
        let page = make()
        page.handover = Handover(site: Vault.registrable(host), host: host, cookies: cookies.count,
                                 acts: acts, asks: asks, ends: Date().addingTimeInterval(TimeInterval(minutes * 60)))
        page.note("You handed over \(host): \(cookies.count) cookies, \(acts ? (asks ? "asking before each click" : "clicks allowed") : "read only"), \(minutes) min")
        let store = page.web.configuration.websiteDataStore.httpCookieStore
        let group = DispatchGroup()
        for cookie in cookies {
            group.enter()
            store.setCookie(cookie) { group.leave() }
        }
        group.notify(queue: .main) {
            page.web.load(URLRequest(url: url))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + TimeInterval(minutes * 60)) { [weak self, weak page] in
            guard let self, let page, page.live != nil else { return }
            self.end(page, "its time was up")
        }
        return nil
    }

    /// The copied sign-in deleted: the page stays, signed out.
    func end(_ page: Page, _ why: String, then: (() -> Void)? = nil) {
        guard page.live != nil else { then?(); return }
        page.handover?.over = why
        page.note("Sign-in removed: \(why)")
        pending.filter { $0.page == page.id }.forEach { $0.reply(false) }
        let store = page.web.configuration.websiteDataStore
        store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {
            MainActor.assumeIsolated { then?() }
        }
    }

    // MARK: - the pages

    private func make() -> Page {
        let config = WKWebViewConfiguration()
        // Its own, forgotten with the page.
        config.websiteDataStore = .nonPersistent()
        config.applicationNameForUserAgent = Web.userAgentName
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        config.preferences.isElementFullscreenEnabled = false
        config.mediaTypesRequiringUserActionForPlayback = .all
        Web.fileIsolation(config)
        let window = room ?? makeRoom()
        let web = WKWebView(frame: window.contentView?.bounds ?? NSRect(x: 0, y: 0, width: 1280, height: 800), configuration: config)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.autoresizingMask = [.width, .height]
        // Never a sound on your speakers from a page you can't see.
        let mute = NSSelectorFromString("_setPageMuted:")
        if web.responds(to: mute), let imp = web.method(for: mute) {
            typealias Muting = @convention(c) (AnyObject, Selector, UInt) -> Void
            unsafeBitCast(imp, to: Muting.self)(web, mute, 1)
        }
        window.contentView?.addSubview(web)
        let page = Page(id: String(UUID().uuidString.prefix(8)).lowercased(), web: web)
        pages.append(page)
        return page
    }

    /// Back in the room off screen, when no window is showing it: a page
    /// out of every window draws nothing to take a picture of.
    func drawn(_ page: Page) {
        guard page.web.window == nil else { return }
        let window = room ?? makeRoom()
        page.web.frame = window.contentView?.bounds ?? page.web.frame
        window.contentView?.addSubview(page.web)
    }

    /// Every page out of every window put back in the room, a turn after a
    /// window stopped showing one.
    func reroom() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pages.forEach(self.drawn)
        }
    }

    private func drop(_ page: Page) {
        page.web.stopLoading()
        page.web.navigationDelegate = nil
        page.web.uiDelegate = nil
        page.web.removeFromSuperview()
        page.acting = nil
    }

    private func makeRoom() -> NSWindow {
        // Off every screen, and never key or main, as the bench's.
        let window = NSWindow(
            contentRect: NSRect(x: -20000, y: -20000, width: 1280, height: 800),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.isExcludedFromWindowsMenu = true
        window.collectionBehavior = [.transient, .ignoresCycle, .stationary]
        window.level = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue - 1)
        window.hasShadow = false
        window.orderBack(nil)
        room = window
        return window
    }

    // MARK: - what runs in the page

    /// The words on the page, as it shows them.
    private static let reading = "return document.body ? document.body.innerText : ''"

    /// The element a selector names — a CSS one, or `text=Sign in` for a
    /// button, link or label by its words — found apart from the page.
    private static let finding = """
        function find(s) {
          if (s.indexOf('text=') === 0) {
            const want = s.slice(5).trim().toLowerCase();
            const all = Array.from(document.querySelectorAll('a, button, input[type=submit], input[type=button], [role=button], [role=link], label, summary'));
            const words = e => (e.innerText || e.value || e.getAttribute('aria-label') || '').trim().toLowerCase();
            return all.find(e => words(e) === want) || all.find(e => words(e).includes(want)) || null;
          }
          try { return document.querySelector(s); } catch (e) { return undefined; }
        }
        """

    private static let clicking = finding + """
        const el = find(selector);
        if (el === undefined) return 'not a selector: ' + selector;
        if (!el) return 'nothing matches ' + selector;
        el.scrollIntoView({ block: 'center', inline: 'nearest' });
        el.click();
        return 'ok';
        """

    /// Through the field's own setter, with the events a keystroke fires,
    /// so the page's framework notices.
    private static let typing = finding + """
        const el = find(selector);
        if (el === undefined) return 'not a selector: ' + selector;
        if (!el) return 'nothing matches ' + selector;
        el.scrollIntoView({ block: 'center', inline: 'nearest' });
        el.focus();
        if (el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement) {
          if (el instanceof HTMLInputElement && el.type === 'file') return 'not a field to type into: ' + selector;
          const proto = el instanceof HTMLInputElement ? HTMLInputElement.prototype : HTMLTextAreaElement.prototype;
          Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, text);
          el.dispatchEvent(new Event('input', { bubbles: true }));
          el.dispatchEvent(new Event('change', { bubbles: true }));
          return 'ok';
        }
        if (el.isContentEditable) {
          document.execCommand('insertText', false, text);
          return 'ok';
        }
        return 'not a field: ' + selector;
        """
}

// MARK: - what a page may do

extension Agent: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard !action.shouldPerformDownload, let url = action.request.url, let scheme = url.scheme?.lowercased() else {
            return decisionHandler(.cancel)
        }
        // The page itself: the web, or nothing. A frame in it may also be
        // made of what the page has in hand.
        let main = action.targetFrame?.isMainFrame ?? true
        let allowed = main ? ["http", "https", "about"] : ["http", "https", "about", "data", "blob"]
        guard allowed.contains(scheme), scheme != "about" || url.absoluteString == "about:blank" || !main else {
            return decisionHandler(.cancel)
        }
        // A page with your sign-in in it stays on its site. Leaving it, the
        // copy is deleted before the request goes, so it can't be carried
        // anywhere else; the page goes on, signed out.
        guard main, let page = pages.first(where: { $0.web === webView }), let handover = page.live,
              ["http", "https"].contains(scheme)
        else { return decisionHandler(.allow) }
        let host = url.host()?.lowercased() ?? ""
        guard Vault.registrable(host) == handover.site else {
            return end(page, "the page left \(handover.site) for \(host)") { decisionHandler(.allow) }
        }
        // A form sent with your sign-in: never on a read-only handover, and
        // asked about first unless you said not to.
        guard action.request.httpMethod?.uppercased() == "POST" else { return decisionHandler(.allow) }
        guard handover.acts else {
            page.note("Blocked a form sent to \(host) (read only)")
            return decisionHandler(.cancel)
        }
        guard handover.asks else { return decisionHandler(.allow) }
        ask(page, handover, "Send a form to \(host)\(url.path())") { yes in
            page.note(yes ? "You allowed a form sent to \(host)" : "You refused a form sent to \(host)")
            decisionHandler(yes ? .allow : .cancel)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        // What can't be shown would be a download.
        decisionHandler(response.canShowMIMEType ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.cancel { _ in }
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.cancel { _ in }
    }

    /// No window of its own: a link meant for one opens in the same page,
    /// when it is a link to the web someone could have followed.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if action.navigationType == .linkActivated, let url = Agent.web(action.request.url?.absoluteString) {
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor () -> Void) {
        completionHandler()
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (Bool) -> Void) {
        completionHandler(false)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (String?) -> Void) {
        completionHandler(nil)
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor ([URL]?) -> Void) {
        completionHandler(nil)
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void) {
        decisionHandler(.deny)
    }

    @objc(_webView:requestGeolocationPermissionForOrigin:initiatedByFrame:decisionHandler:)
    func location(_ webView: WKWebView, origin: WKSecurityOrigin, frame: WKFrameInfo,
                  decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(.deny)
    }

    @objc(_webView:requestNotificationPermissionForSecurityOrigin:decisionHandler:)
    func notifications(_ webView: WKWebView, origin: WKSecurityOrigin, decisionHandler: @escaping (Bool) -> Void) {
        decisionHandler(false)
    }

    /// A page whose process went away is closed rather than left blank.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard let page = pages.first(where: { $0.web === webView }) else { return }
        close(page)
    }
}
