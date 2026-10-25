import Foundation
import XCTest
@testable import Shy

/// Searching history by a page's title as well as its address.
@MainActor
final class HistoryTitleTests: XCTestCase {
    override class func setUp() {
        setenv("SHY_PROBE", "history-title-\(getpid())", 1)
        super.setUp()
    }

    func testTitleWordsFindThePageAfterTheAddressMatches() {
        let history = History(file: "history-title-\(UUID().uuidString).json", profile: UUID())
        defer { history.forget() }
        history.record(URL(string: "https://browserbench.org/Speedometer3.1/")!, title: "Speedometer 3.1")
        history.record(URL(string: "https://speedy.example/")!, title: "Fast hosting")

        // Partial, any case, found by title alone.
        let byTitle = history.suggestions(for: "SPEEDOM")
        XCTAssertEqual(byTitle.map(\.title), ["Speedometer 3.1"])
        XCTAssertEqual(history.everything(matching: "speedometer").count, 1)

        // The host match comes before a title-only match.
        history.record(URL(string: "https://news.example/a")!, title: "Why speedy sites win")
        XCTAssertEqual(history.suggestions(for: "speedy").first?.title, "Fast hosting")
        XCTAssertEqual(history.suggestions(for: "speedy").count, 2)

        // Clear takes the titles with the addresses.
        history.forget()
        XCTAssertTrue(history.suggestions(for: "speedometer").isEmpty)
    }
}
