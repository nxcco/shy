import SwiftUI

// Spaces, paged through: in the column, two fingers sideways go from one to
// the next, the rows following them, as in Arc — or a mouse wheel's notch
// sideways, one space at a time, or the mouse's back and forward buttons
// with the pointer over the tabs. Past the last space a new one is made in
// place (NewSpaceCard). The space's icon turns over as it goes (see SpaceDot).

/// The swipe between spaces. It reads the trackpad's own scroll events
/// before anything else sees them, and takes only a gesture that starts over
/// the tabs and sets off clearly sideways; everything else (scrolling the
/// tabs) goes on as it would have.
/// How far the column's rows have followed two fingers sideways. On its own
/// rather than on the browser: it changes with every event the trackpad
/// sends, and only the pages (SideBar.pages) have anything to draw for it.
@MainActor
final class SpaceTravel: ObservableObject {
    @Published var offset: CGFloat = 0
}

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
    private var gathered = CGSize.zero
    /// Where the fingers were over the last moments, for how fast they
    /// were going as they let go.
    private var trail: [(time: TimeInterval, travel: CGFloat)] = []
    /// When the wheel last turned over the tabs, whether a space came of it
    /// or not. A spin of the wheel is a run of notches close together, and
    /// it brings one space: the next waits for the wheel to have rested.
    private var notched = Date.distantPast
    /// Until when a new gesture is let go by: the hand that just brought a
    /// space is often still moving, and its next stroke would take one more.
    private var resting = Date.distantPast
    /// A gesture let go by while resting, kept whole, glide included.
    private var ignoring = false

    /// How long after a space comes before another can.
    static let rest: TimeInterval = 0.4

    /// How far the fingers have to go for the next space to come — or
    /// would have gone, carried on by their speed (see `carry`).
    static let enough: CGFloat = 50
    /// A flick counts from here: less is a twitch, however fast.
    static let least: CGFloat = 12
    /// How long the fingers' speed is taken to carry them on for.
    static let carry: TimeInterval = 0.15

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
    /// (PageView.otherMouseDown). Past the last space, as with the wheel,
    /// the card for a new one.
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
        let here = browser.spaceAt
        let target = here + step
        if target >= 0, target <= browser.spaces.count { slide(browser, to: target, from: here) }
        return true
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
            let here = browser.spaceAt
            let target = here + (step < 0 ? 1 : -1)
            if target >= 0, target <= browser.spaces.count { slide(browser, to: target, from: here) }
            return true
        }
        if !event.momentumPhase.isEmpty { return gliding }
        switch event.phase {
        case .began:
            gliding = false
            ignoring = false
            // Only a gesture that starts over the tabs.
            guard overTabs(event, in: browser) else {
                tracking = false
                return false
            }
            began()
            if ignoring { return true }
            return moved(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY, at: event.timestamp)
        case .changed:
            if ignoring { return true }
            guard tracking else { return false }
            return moved(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY, at: event.timestamp)
        case .ended, .cancelled:
            if ignoring {
                ignoring = false
                gliding = true
                return true
            }
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
        // Just after a space came: the same hand's next stroke is let go by.
        ignoring = Date() <= resting
        tracking = !ignoring
    }

    /// True while the gesture is this one's to take. The spaces lie
    /// sideways in the column. `time` is the event's own, on the clock
    /// that has run since the Mac started.
    @discardableResult
    func moved(dx: CGFloat, dy: CGFloat, at time: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Bool {
        guard tracking, let browser else { return false }
        // No further than the next page: there is nothing drawn beyond it.
        let width = browser.prefs.sideWidth
        gathered.width = min(max(gathered.width + dx, -width), width)
        gathered.height += dy
        if axis == .undecided {
            guard abs(gathered.width) + abs(gathered.height) > 6 else { return false }
            axis = abs(gathered.width) > abs(gathered.height) * 1.5 ? .across : .along
        }
        guard axis == .across else { return false }
        trail.append((time, gathered.width))
        trail.removeAll { time - $0.time > 0.08 }
        browser.spaceTravel.offset = resisted(gathered.width, in: browser)
        return true
    }

    /// Along the spaces' axis — for the bench.
    @discardableResult
    func moved(along travel: CGFloat) -> Bool {
        guard browser != nil else { return false }
        return moved(dx: travel, dy: 0)
    }

    /// How fast the fingers were going as they let go, in points a second:
    /// across the last moments of the trail. Nothing if they had stopped
    /// first, or if the trail is too short to tell (the bench's, all at once).
    private func speed(at time: TimeInterval) -> CGFloat {
        guard let first = trail.first, let last = trail.last,
              time - last.time < 0.1, last.time - first.time >= 0.008 else { return 0 }
        return (last.travel - first.travel) / (last.time - first.time)
    }

    func ended(cancelled: Bool = false, at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        defer { tracking = false }
        guard let browser, axis == .across else { return }
        let travel = gathered.width
        let speed = speed(at: time)
        // Where the fingers would have got to, going on as they were: a
        // short flick brings the next space as a long drag does, and a
        // drag turned back before letting go doesn't.
        let reach = travel + speed * SpaceSwipe.carry
        let far = abs(travel) >= SpaceSwipe.least && abs(reach) >= SpaceSwipe.enough && (reach < 0) == (travel < 0)
        let here = browser.spaceAt
        // Fingers to the left bring what is next.
        let target = cancelled || !far ? here : here + (travel < 0 ? 1 : -1)
        guard target != here, target >= 0, target <= browser.spaces.count else {
            withAnimation(landing(browser, to: 0, speed: speed)) { browser.spaceTravel.offset = 0 }
            return
        }
        slide(browser, to: target, from: here, speed: speed)
    }

    /// Nothing that way: the rows give a little, and come back.
    private func resisted(_ travel: CGFloat, in browser: Browser) -> CGFloat {
        let here = browser.spaceAt
        let blocked = (travel > 0 && here == 0) || (travel < 0 && here == browser.spaces.count)
        return blocked ? travel / 4 : travel
    }

    /// The rest of the way to `rest`, setting off at the speed the fingers
    /// left at, so nothing changes pace as they lift: a spring with no
    /// bounce in it. With motion reduced or light (see Motion), the short
    /// ease-out there was before.
    private func landing(_ browser: Browser, to rest: CGFloat, speed: CGFloat) -> Animation? {
        if Motion.reduced { return rest == 0 ? nil : .easeOut(duration: 0.22) }
        if Motion.light { return .easeOut(duration: rest == 0 ? 0.16 : 0.22) }
        let left = rest - browser.spaceTravel.offset
        // The spring takes its speed as a share of the way left, a second.
        // Past 2π / duration it would overshoot, and show what is beyond
        // the page coming in: nothing.
        let duration = 0.24
        let pace = abs(left) < 1 ? 0 : min(max(speed / left, -8), 0.8 * 2 * .pi / duration)
        return .interpolatingSpring(duration: duration, bounce: 0, initialVelocity: pace)
    }

    /// The pages carry on the way the fingers went until the next one is
    /// where this one was; then it becomes the one on screen, in the same
    /// frame and without anything moving — it was already there. One past
    /// the last space is the card for a new one.
    func slide(_ browser: Browser, to target: Int, from here: Int, speed: CGFloat = 0) {
        if browser.makingSpace, target != browser.spaces.count {
            browser.cancelSpaceCreation()
        }
        // A page is the column's width.
        let width = browser.prefs.sideWidth
        let away: CGFloat = target > here ? -1 : 1
        browser.spaceStep = target > here ? 1 : -1
        resting = Date().addingTimeInterval(SpaceSwipe.rest)
        withAnimation(landing(browser, to: away * width, speed: speed), completionCriteria: .removed) {
            browser.spaceTravel.offset = away * width
        } completion: {
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) {
                if target == browser.spaces.count {
                    browser.makingSpace = true
                } else {
                    browser.makingSpace = false
                    browser.switchSpace(to: browser.spaces[target].id)
                }
                browser.spaceTravel.offset = 0
            }
        }
    }
}
