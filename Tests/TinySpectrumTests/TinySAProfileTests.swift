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
        XCTAssertEqual(ultra.maximumHz, 6_000_000_000)
        XCTAssertNil(try ultra.inputMode(startHz: 100_000, stopHz: 6_000_000_000))
        XCTAssertTrue(ultra.supports(.hz200))
        let zs407 = TinySAProfile.from(info: "tinySA Ultra+ HW V0.5.3 ZS407")
        XCTAssertEqual(zs407.name, "tinySA Ultra+ ZS407")
        XCTAssertEqual(zs407.maximumHz, 7_300_000_000)
    }
}
