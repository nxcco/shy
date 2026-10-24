import XCTest
@testable import Shy

/// Settings › General › The floating video: Shy's window unless picture
/// in picture is chosen, and the choice kept (idea 376). Entering picture
/// in picture puts a system window on screen, so that part is by eye.
@MainActor
final class NativePiPTests: XCTestCase {
    override class func setUp() {
        setenv("SHY_PROBE", "native-pip-\(getpid())", 1)
        super.setUp()
    }

    func testShysWindowUnlessChosen() {
        let saved = Store.settings.object(forKey: "float.style")
        defer { Store.settings.set(saved, forKey: "float.style") }
        Store.settings.removeObject(forKey: "float.style")
        XCTAssertEqual(Preferences().floatStyle, .shy)
        let prefs = Preferences()
        prefs.floatStyle = .system
        XCTAssertEqual(Preferences().floatStyle, .system)
        Store.settings.set("nonsense", forKey: "float.style")
        XCTAssertEqual(Preferences().floatStyle, .shy)
    }

    func testScriptsAskOnlyForPictureInPicture() {
        let on = NativePiP.script(toggle: false)
        XCTAssertTrue(on.contains("var toggle = false"))
        XCTAssertTrue(NativePiP.script(toggle: true).contains("var toggle = true"))
        XCTAssertTrue(on.contains("webkitSetPresentationMode('picture-in-picture')"))
        XCTAssertFalse(on.contains("fullscreen"))
        XCTAssertTrue(NativePiP.off.contains("webkitSetPresentationMode('inline')"))
    }
}
