import XCTest
@testable import TinySpectrum

final class TinySAProfileTests: XCTestCase {
    func testBasicUsesRegularLimitsAndInputModes() throws {
        let basic = TinySAProfile.from(info: "tinySA_v1.4")
        XCTAssertFalse(basic.isUltra)
        XCTAssertEqual(basic.maximumPoints, 290)
        XCTAssertEqual(try basic.inputMode(startHz: 87_500_000, stopHz: 108_000_000), "low")
        XCTAssertEqual(try basic.inputMode(startHz: 470_000_000, stopHz: 700_000_000), "high")
        XCTAssertThrowsError(try basic.inputMode(startHz: 100_000_000, stopHz: 700_000_000))
        XCTAssertFalse(basic.supports(.hz200))
        XCTAssertTrue(basic.supports(.khz30))
    }

    func testUltraDetectionKeepsWideCapabilities() throws {
        let ultra = TinySAProfile.from(info: "tinySA4 Ultra")
        XCTAssertTrue(ultra.isUltra)
        XCTAssertEqual(ultra.maximumPoints, 450)
        XCTAssertNil(try ultra.inputMode(startHz: 100_000, stopHz: 5_300_000_000))
        XCTAssertTrue(ultra.supports(.hz200))
    }
}
