import AppKit
import WebKit

// Agents' pages: what an AI agent on this Mac — any MCP client: Claude
// Code, Cursor, Codex and the like — can open and read through search-mcp,
// the small program beside the app (Sources/SearchMCP), which speaks MCP on its standard
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
// - none of Search's own page scripts and no extensions: nothing fills in a
//   password, offers a passkey or reads the page on an extension's behalf;
// - http and https only, typed in or followed; a page can't open a window,
//   download, upload a file, use the camera, the microphone or where you
//   are, and its alerts are answered "no" without a word;
// - no script of the agent's own: it reads the page's text, takes a picture
//   of it, clicks and types into what a selector names, nothing else.
//
// The pages live in a window of their own off every screen, so a picture of
// one is a picture of something, and never take a window from you.

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
    /// Its pages, newest last, for Settings to count and close.
    @Published private(set) var pages: [Page] = []
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
            case .picture: return "Take pictures of pages"
            case .click: return "Click"
            case .type: return "Type into fields"
            }
        }
        var detail: String {
            switch self {
            case .open: return "Open http and https addresses, and go to another in a page it has open"
            case .read: return "The page's title, address and visible words"
            case .picture: return "What the page shows, as an image"
            case .click: return "A button, link or label, picked by a selector or its words"
            case .type: return "Into a field or an editable part of the page"
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
    private static let world = WKContentWorld.world(name: "search-agent")

    final class Page {
        let id: String
        let web: WKWebView
        /// When an agent last asked anything of it (see `tidy`).
        var used = Date()
        init(id: String, web: WKWebView) {
            self.id = id
            self.web = web
        }
    }

    /// A page no agent has asked anything of for this long is closed: what
    /// it runs, it runs from your Mac.
    static let idle: TimeInterval = 10 * 60
    private var tidying: Timer?

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
        stale.forEach(drop)
        pages.removeAll { page in stale.contains { $0 === page } }
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

    func closeAll() {
        pages.forEach(drop)
        pages = []
    }

    // MARK: - the calls

    private func handle(_ request: [String: Any], _ given: @escaping ([String: Any]) -> Void) {
        // One answer, and always one, however a page behaves.
        var answered = false
        let answer: ([String: Any]) -> Void = { reply in
            guard !answered else { return }
            answered = true
            given(reply)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 45) { answer(["error": "no answer within 45 s"]) }

        let verb = request["do"] as? String ?? ""
        guard Agent.allowed.contains(verb) else {
            return answer(["error": "“\(verb)” is turned off in Search's Settings › Agents"])
        }
        // What search-mcp offers the agent: only what is allowed now.
        if verb == "tools" {
            return answer(["allowed": Agent.allowed.sorted()])
        }
        if verb == "open" {
            guard let url = Agent.web(request["url"]) else { return answer(["error": "open needs an http or https address"]) }
            guard pages.count < Agent.most else {
                return answer(["error": "\(Agent.most) pages are open — close one first"])
            }
            let page = make()
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
        guard let page = (request["id"] as? String).flatMap({ id in pages.first { $0.id == id } }) else {
            return answer(["error": "no page “\(request["id"] as? String ?? "")” — open one, or list them"])
        }
        page.used = Date()
        switch verb {
        case "go":
            guard let url = Agent.web(request["url"]) else { return answer(["error": "go needs an http or https address"]) }
            page.web.load(URLRequest(url: url))
            settle(page, within: 15, answer)

        case "wait":
            let seconds = min(30, max(0, (request["seconds"] as? Double) ?? 10))
            settle(page, within: seconds, answer)

        case "text":
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
            run(verb == "click" ? Agent.clicking : Agent.typing, on: page, ["selector": selector, "text": text]) { value, trouble in
                let said = trouble ?? value as? String ?? "the page didn't answer"
                answer(said == "ok" ? ["ok": true] : ["error": said])
            }

        case "close":
            drop(page)
            pages.removeAll { $0 === page }
            answer(["closed": 1])

        default:
            answer(["error": "unknown call “\(verb)”"])
        }
    }

    /// An http or https address with a host, and nothing else: no file on
    /// this Mac, no page of Search's own, no other app's scheme.
    static func web(_ value: Any?) -> URL? {
        guard let text = value as? String, text.count <= 8192,
              let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host(), !host.isEmpty
        else { return nil }
        return url
    }

    private func describe(_ page: Page) -> [String: Any] {
        ["id": page.id, "url": page.web.url?.absoluteString ?? "", "title": page.web.title ?? "", "loading": page.web.isLoading]
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

    private func drop(_ page: Page) {
        page.web.stopLoading()
        page.web.navigationDelegate = nil
        page.web.uiDelegate = nil
        page.web.removeFromSuperview()
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
        decisionHandler(.allow)
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
        drop(page)
        pages.removeAll { $0 === page }
    }
}
