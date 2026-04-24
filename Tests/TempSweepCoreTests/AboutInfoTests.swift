import XCTest
@testable import TempSweepCore

final class AboutInfoTests: XCTestCase {
    func testDefaultAboutInfoContainsCreatorAndContact() {
        XCTAssertEqual(TempSweepAboutInfo.default.creator, "buhussy")
        XCTAssertEqual(TempSweepAboutInfo.default.contact, "x.com/buhusa")
    }
}
