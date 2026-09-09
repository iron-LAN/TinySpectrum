import XCTest
@testable import TinySpectrum

final class ScanPresetTests: XCTestCase {
    func testPresetKeepsTheMeasurementItWasSavedWith() throws {
        let preset = ScanPreset(
            id: UUID(),
            name: "UHF survey",
            startHz: 470_000_000,
            stopHz: 700_000_000,
            rbw: .khz30,
            interval: .minute1
        )

        let decoded = try JSONDecoder().decode(ScanPreset.self, from: JSONEncoder().encode(preset))

        XCTAssertEqual(decoded.rbw, .khz30)
        XCTAssertEqual(decoded.interval, .minute1)
        XCTAssertEqual(decoded.startHz, 470_000_000)
        XCTAssertEqual(decoded.stopHz, 700_000_000)
    }

    func testPresetsSavedBeforeVersion3StillDecode() throws {
        let legacy = """
        {"id":"F7B2B0E2-0000-4000-8000-000000000001","name":"FM Broadcast",\
        "startHz":87500000,"stopHz":108000000}
        """

        let decoded = try JSONDecoder().decode(ScanPreset.self, from: Data(legacy.utf8))

        XCTAssertEqual(decoded.name, "FM Broadcast")
        XCTAssertNil(decoded.rbw)
        XCTAssertNil(decoded.interval)
    }

    func testResolutionIsStoredAsBandwidthNotDisplayLabel() throws {
        let preset = ScanPreset(
            id: UUID(),
            name: "UHF survey",
            startHz: 470_000_000,
            stopHz: 700_000_000,
            rbw: .khz30,
            interval: .minute1
        )

        let json = String(decoding: try JSONEncoder().encode(preset), as: UTF8.self)

        // "30 kHz (AD600 scan)" must never reach disk: reworded labels would
        // stop decoding and take the surrounding store with them.
        XCTAssertFalse(json.contains("AD600"), json)
        XCTAssertTrue(json.contains("30000"), json)
    }

    func testEveryResolutionRoundTripsThroughItsBandwidth() throws {
        for rbw in RBW.allCases {
            let preset = ScanPreset(id: UUID(), name: "n", startHz: 1e5, stopHz: 2e5, rbw: rbw, interval: nil)
            let decoded = try JSONDecoder().decode(ScanPreset.self, from: JSONEncoder().encode(preset))
            XCTAssertEqual(decoded.rbw, rbw)
        }
    }
}
