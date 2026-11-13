import SwiftUI
import QuartzCore

// Spaces, paged through: in the column, two fingers sideways go from one to
// the next, the rows following them, as in Arc — or a mouse wheel's notch
// sideways, one space at a time, or the mouse's back and forward buttons
// with the pointer over the tabs. The space's icon turns over as it goes
// (see SpaceDot).
//
// The card for a new space (NewSpaceCard) is a page past the last, and only
// New Space brings it: the fingers stop at the last space, where it would
// otherwise come in every time they went through them. While it is up they
// can send it back.
//
// The spaces are one band, a page each, and the band goes where the fingers
// do: past one space and on to the next, or back, for as long as they are
// down. Let go, it comes to rest on a page, and only then does that space
// become the one on screen — its tabs, its page — once, however many went
// by. The way to rest is worked out here, frame by frame, rather than handed
// to SwiftUI: where the band is and how fast is always known, so the next
// stroke takes hold of it wherever it is, still on its way or not.

/// The swipe between spaces. It reads the trackpad's own scroll events
/// before anything else sees them, and takes only a gesture that starts over
/// the tabs and sets off clearly sideways; everything else (scrolling the
/// tabs) goes on as it would have.
/// How far the band has gone from the space on screen: the page of the
/// space at `index` is drawn (index − Browser.spaceAt) pages along, and
/// this much further. On its own rather than on the browser: it changes
/// with every event the trackpad sends and every frame on the way to rest,
/// and only the pages (SpacePages) have anything to draw for it.
@MainActor
final class SpaceTravel: ObservableObject {
    @Published var offset: CGFloat = 0
    /// Whether the card for a new space is on its way in (SpaceSwipe.fly).
    /// Otherwise it isn't drawn past the last space, where the rows giving
    /// a little at the band's end would show its edge.
    var bringsCard = false
}

/// The swipe between spaces. It reads the trackpad's own scroll events
/// before anything else sees them, and takes only a gesture that starts over
/// the tabs and sets off clearly sideways; everything else (scrolling the
/// tabs) goes on as it would have.
@MainActor
final class SpaceSwipe {
    static let shared = SpaceSwipe()

    private weak var browser: Browser?
    private var monitor: Any?
    private var buttons: Any?
    private enum Axis { case undecided, across, along }
    private var axis = Axis.undecided
    private var tracking = false
    /// The glide after a swipe that was taken, which is taken too.
    private var gliding = false
    /// How far the fingers have gone since they came down, for telling
    /// which way they set off.
    private var gathered = CGSize.zero
    /// How far they have pulled the band, before its ends resist.
    private var pull: CGFloat = 0
    /// The page the stroke set off from: the one at rest, or the one the
    /// band was on its way to when the fingers took hold of it.
    private var origin = 0
    /// Where the band was over the last moments, for how fast it was
    /// going as the fingers let go.
    private var trail: [(time: TimeInterval, offset: CGFloat)] = []
    /// When the wheel last turned over the tabs, whether a space came of it
    /// or not. A spin of the wheel is a run of notches close together, and
    /// it brings one space: the next waits for the wheel to have rested.
    private var notched = Date.distantPast
    /// Until when another notch is let go by, after one that brought a space.
    private var resting = Date.distantPast

    /// The band on its way to rest, with nothing holding it.
    private struct Flight {
        weak var browser: Browser?
        /// The space on screen as it set off, which the band is drawn from.
        let base: Int
        /// The page it comes to rest on.
        var target: Int
        /// Points a second.
        var speed: CGFloat
        var last: TimeInterval?
    }
    private var flight: Flight?
    private var ticker: Ticker?

    /// How long after a notch brings a space before another can.
    static let rest: TimeInterval = 0.4
    /// How far into the next page the fingers have to go for it to come —
    /// or would have gone, carried on by their speed (see `carry`).
    static let enough: CGFloat = 50
    /// A flick counts from here: less is a twitch, however fast.
    static let least: CGFloat = 12
    /// How long the fingers' speed is taken to carry them on for.
    static let carry: TimeInterval = 0.15
    /// How long the band takes to look at rest; light, with the Mac short
    /// of power (see Motion.light).
    static let settle: TimeInterval = 0.24
    static let settleLight: TimeInterval = 0.16

    func start(for browser: Browser) {
        self.browser = browser
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            MainActor.assumeIsolated { SpaceSwipe.shared.takes(event) } ? nil : event
        }
        buttons = NSEvent.addLocalMonitorForEvents(matching: [.otherMouseDown, .swipe]) { event in
            MainActor.assumeIsolated { SpaceSwipe.shared.pressed(event) } ? nil : event
        }
    }

    /// The mouse's back and forward buttons over the tabs: the space before,
    /// or the one after. Over the page they stay the page's back and forward
    /// (PageView.otherMouseDown).
    ///
    /// Most mice send them as buttons 3 and 4. A Logitech mouse set up with
    /// Logi Options+, Logitech's own driver, doesn't: it turns them into the
    /// swipe a trackpad sends for going back or forward a page — deltaX 1
    /// for back, -1 for forward, which is how Safari reads it. A swipe of
    /// that kind over the tabs is taken the same way, whoever sends it.
    private func pressed(_ event: NSEvent) -> Bool {
        let step: Int
        switch event.type {
        case .otherMouseDown where event.buttonNumber == 3: step = -1
        case .otherMouseDown where event.buttonNumber == 4: step = 1
        case .swipe where event.deltaX != 0: step = event.deltaX > 0 ? -1 : 1
        default: return false
        }
        guard let browser = Browsers.browser(for: event.window), !browser.isPopup,
              !browser.folded || browser.peeking, overTabs(event, in: browser) else { return false }
        self.browser = browser
        self.step(browser, by: step)
        return true
    }

    /// One space on from where the band is, or is heading.
    private func step(_ browser: Browser, by step: Int) {
        let target = heading(in: browser) + step
        if target >= 0, target <= furthest(in: browser) { fly(browser, to: target) }
    }

    /// The last page the fingers, the wheel or the buttons go to: the last
    /// space, or the card for a new one while it is up.
    private func furthest(in browser: Browser) -> Int {
        browser.makingSpace ? browser.spaces.count : max(browser.spaces.count - 1, 0)
    }

    /// The page the band is on, or on its way to.
    private func heading(in browser: Browser) -> Int {
        if let flight, flight.browser === browser { return flight.target }
        return browser.spaceAt
    }

    /// Where the tabs are: the column.
    private func overTabs(_ event: NSEvent, in browser: Browser) -> Bool {
        guard let window = event.window, window === browser.window else { return false }
        return browser.prefs.sidePosition == .right
            ? event.locationInWindow.x >= window.frame.width - browser.prefs.sideWidth
            : event.locationInWindow.x < browser.prefs.sideWidth
    }

    /// True for an event the swipe keeps for itself.
    private func takes(_ event: NSEvent) -> Bool {
        // The window the fingers are over, at the start of a gesture or a
        // turn of the wheel; the rest of a gesture stays with it.
        if event.phase == .began || !event.hasPreciseScrollingDeltas, let over = Browsers.browser(for: event.window) {
            browser = over
        }
        guard let browser, !browser.folded || browser.peeking else { return false }
        // A mouse wheel over the tabs: a notch sideways brings one space.
        // Only a notch more sideways than up or down: scrolling the tabs
        // is never taken for it.
        if !event.hasPreciseScrollingDeltas {
            let dx = event.scrollingDeltaX, dy = event.scrollingDeltaY
            let step = (abs(dx) > abs(dy) ? dx : 0)
            guard step != 0, overTabs(event, in: browser) else { return false }
            let now = Date()
            let rested = now.timeIntervalSince(notched) > 0.3 && now > resting
            notched = now
            guard rested else { return true }
            resting = now.addingTimeInterval(SpaceSwipe.rest)
            self.step(browser, by: step < 0 ? 1 : -1)
            return true
        }
        if !event.momentumPhase.isEmpty { return gliding }
        switch event.phase {
        case .began:
            gliding = false
            // Only a gesture that starts over the tabs.
            guard overTabs(event, in: browser) else {
                tracking = false
                return false
            }
            began()
            return moved(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY, at: event.timestamp)
        case .changed:
            guard tracking else { return false }
            return moved(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY, at: event.timestamp)
        case .ended, .cancelled:
            guard tracking else { return false }
            let taken = axis == .across
            ended(cancelled: event.phase == .cancelled, at: event.timestamp)
            gliding = taken
            return taken
        default:
            return false
        }
    }

    // MARK: - the gesture, apart from where its events come from (the bench drives these)

    func began() {
        axis = .undecided
        gathered = .zero
        trail = []
        tracking = true
    }

    /// True while the gesture is this one's to take. The spaces lie
    /// sideways in the column. `time` is the event's own, on the clock
    /// that has run since the Mac started.
    @discardableResult
    func moved(dx: CGFloat, dy: CGFloat, at time: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        guard tracking, let browser else { return false }
        gathered.width += dx
        gathered.height += dy
        if axis == .undecided {
            guard abs(gathered.width) + abs(gathered.height) > 6 else { return false }
            axis = abs(gathered.width) > abs(gathered.height) * 1.5 ? .across : .along
            guard axis == .across else { return false }
            // The fingers take hold of the band where it is — at rest, or
            // on its way somewhere, which a stroke up or down leaves it to.
            if let flight, flight.browser !== browser { land() }
            origin = heading(in: browser)
            halt()
            pull = unresisted(browser.spaceTravel.offset, in: browser) + gathered.width
        } else {
            guard axis == .across else { return false }
            pull += dx
        }
        // A page past either end, and no further: nothing is drawn there.
        let ends = ends(in: browser), width = browser.prefs.sideWidth
        pull = min(max(pull, ends.lowerBound - width), ends.upperBound + width)
        let offset = resisted(pull, in: browser)
        trail.append((time, offset))
        trail.removeAll { time - $0.time > 0.08 }
        browser.spaceTravel.offset = offset
        return true
    }

    /// Along the spaces' axis — for the bench.
    @discardableResult
    func moved(along travel: CGFloat) -> Bool {
        guard browser != nil else { return false }
        return moved(dx: travel, dy: 0)
    }

    /// How fast the band was going as the fingers let go, in points a
    /// second: across the last moments of the trail. Nothing if they had
    /// stopped first, or if the trail is too short to tell (the bench's,
    /// all at once).
    private func speed(at time: TimeInterval) -> CGFloat {
        guard let first = trail.first, let last = trail.last,
              time - last.time < 0.1, last.time - first.time >= 0.008 else { return 0 }
        return (last.offset - first.offset) / (last.time - first.time)
    }

    func ended(cancelled: Bool = false, at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        defer { tracking = false }
        guard let browser, axis == .across else { return }
        let width = browser.prefs.sideWidth
        let speed = speed(at: time)
        let ends = ends(in: browser)
        // Where the band is, in pages: 1.5 is halfway from the second space
        // to the third. Fingers to the left bring what is next.
        let place = CGFloat(browser.spaceAt) - min(max(browser.spaceTravel.offset, ends.lowerBound), ends.upperBound) / width
        var target = origin
        if !cancelled, abs(place - CGFloat(origin)) * width >= SpaceSwipe.least {
            // Where it would have got to, going on as it was: a short
            // flick brings the next space as a long drag does, and a drag
            // turned back before letting go doesn't. `enough` into a page
            // and it is that page's.
            let reach = place - speed * SpaceSwipe.carry / width
            let share = SpaceSwipe.enough / width
            target = reach > CGFloat(origin)
                ? Int(reach.rounded(.down)) + (reach - reach.rounded(.down) >= share ? 1 : 0)
                : Int(reach.rounded(.up)) - (reach.rounded(.up) - reach >= share ? 1 : 0)
        }
        // One of the two pages the band lies across: speed brings the
        // next one sooner, never one beyond it.
        target = min(max(target, Int(place.rounded(.down))), Int(place.rounded(.up)))
        fly(browser, to: min(max(target, 0), furthest(in: browser)), speed: speed)
    }

    // MARK: - the band

    /// How far the band goes each way from the space on screen: back to
    /// the first space, and on to the last.
    private func ends(in browser: Browser) -> ClosedRange<CGFloat> {
        let width = browser.prefs.sideWidth, at = browser.spaceAt
        return -CGFloat(max(furthest(in: browser) - at, 0)) * width ... CGFloat(at) * width
    }

    /// Nothing that way: the rows give a little, and come back.
    private func resisted(_ pull: CGFloat, in browser: Browser) -> CGFloat {
        let ends = ends(in: browser)
        if pull > ends.upperBound { return ends.upperBound + (pull - ends.upperBound) / 4 }
        if pull < ends.lowerBound { return ends.lowerBound + (pull - ends.lowerBound) / 4 }
        return pull
    }

    /// The pull that puts the band there: `resisted`, the other way round.
    private func unresisted(_ offset: CGFloat, in browser: Browser) -> CGFloat {
        let ends = ends(in: browser)
        if offset > ends.upperBound { return ends.upperBound + (offset - ends.upperBound) * 4 }
        if offset < ends.lowerBound { return ends.lowerBound + (offset - ends.lowerBound) * 4 }
        return offset
    }

    /// The band let go, on its way to rest on the page at `target`, setting
    /// off at the speed the fingers left at so nothing changes pace as they
    /// lift. One past the last space is the card for a new one, which only
    /// New Space asks for (Browser.askForSpace). Already on
    /// its way, it keeps the speed it has and heads there instead.
    func fly(_ browser: Browser, to target: Int, speed: CGFloat = 0) {
        if let flight, flight.browser !== browser { land() }
        if target != browser.spaces.count {
            browser.cancelSpaceCreation()
        }
        let at = browser.spaceAt
        // Which way the icon at the foot turns over.
        if target != at { browser.spaceStep = target > at ? 1 : -1 }
        browser.spaceTravel.bringsCard = target == browser.spaces.count
        flight = Flight(browser: browser, base: at, target: target, speed: flight?.speed ?? speed)
        guard !Motion.reduced else { return land() }
        if ticker == nil {
            ticker = Ticker(window: browser.window) { SpaceSwipe.shared.tick($0) }
        }
    }

    /// One frame of the way to rest: a spring with no bounce in it, worked
    /// out exactly for the time since the last frame, however long that was.
    private func tick(_ now: TimeInterval) {
        guard var flight, let browser = flight.browser, browser.spaceAt == flight.base else {
            // The space changed some other way meanwhile: the band is its.
            let gone = flight?.browser
            halt()
            gone?.spaceTravel.offset = 0
            return
        }
        let passed = min(max(now - (flight.last ?? now - 1 / 120), 0), 1 / 30)
        let stiffness = 2 * .pi / (Motion.light ? SpaceSwipe.settleLight : SpaceSwipe.settle)
        let rest = CGFloat(flight.base - flight.target) * browser.prefs.sideWidth
        let away = browser.spaceTravel.offset - rest
        // Faster than this towards its page, it would run past it.
        var speed = flight.speed
        if speed * away < 0, abs(speed) > stiffness * abs(away) { speed = -stiffness * away }
        let pace = speed + stiffness * away
        let fade = exp(-stiffness * passed)
        let left = (away + pace * passed) * fade
        flight.speed = (speed - pace * stiffness * passed) * fade
        flight.last = now
        self.flight = flight
        if abs(left) < 0.5, abs(flight.speed) < 30 {
            land()
        } else {
            browser.spaceTravel.offset = rest + left
        }
    }

    /// The band left where it is, with nothing moving it.
    private func halt() {
        ticker?.stop()
        ticker = nil
        flight = nil
    }

    /// At rest: the page the band was heading for becomes the space on
    /// screen, in the same frame and without anything moving — it was
    /// already there.
    private func land() {
        guard let flight else { return }
        halt()
        guard let browser = flight.browser else { return }
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            if browser.spaceAt == flight.base, flight.target != flight.base {
                if flight.target == browser.spaces.count {
                    browser.makingSpace = true
                } else if browser.spaces.indices.contains(flight.target) {
                    browser.makingSpace = false
                    browser.switchSpace(to: browser.spaces[flight.target].id)
                }
            }
            browser.spaceTravel.bringsCard = false
            browser.spaceTravel.offset = 0
        }
    }
}

/// A call for every frame the screen draws, for as long as it is kept. A
/// window not on any screen has no frames to follow (a test run's, started
/// hidden): a timer stands in.
@MainActor
private final class Ticker: NSObject {
    private var link: CADisplayLink?
    private var timer: Timer?
    private let beat: (TimeInterval) -> Void

    init(window: NSWindow?, beat: @escaping (TimeInterval) -> Void) {
        self.beat = beat
        super.init()
        if let window, window.occlusionState.contains(.visible), let view = window.contentView {
            let link = view.displayLink(target: self, selector: #selector(frame))
            link.add(to: .main, forMode: .common)
            self.link = link
        } else {
            let timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.beat(CACurrentMediaTime()) }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    @objc private func frame(_ link: CADisplayLink) {
        beat(link.targetTimestamp)
    }

    func stop() {
        link?.invalidate()
        timer?.invalidate()
        link = nil
        timer = nil
    }
}
