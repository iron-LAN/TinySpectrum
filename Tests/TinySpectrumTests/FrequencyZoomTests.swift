import XCTest
@testable import TinySpectrum

final class FrequencyZoomTests: XCTestCase {
    func testZoomKeepsCursorFrequencyAnchored() {
        let result = FrequencyZoom.window(current: 100...200, full: 100...200, anchor: 0.25, scale: 0.5)

        XCTAssertEqual(result.lowerBound, 112.5, accuracy: 0.0001)
        XCTAssertEqual(result.upperBound, 162.5, accuracy: 0.0001)
    }

    func testZoomOutStopsAtVisibleScanRange() {
        let result = FrequencyZoom.window(current: 125...175, full: 100...200, anchor: 0.5, scale: 10)

        XCTAssertEqual(result, 100...200)
    }

    func testZoomNearEdgeStaysInsideVisibleScanRange() {
        let result = FrequencyZoom.window(current: 100...200, full: 100...200, anchor: 0.95, scale: 0.25)

        XCTAssertGreaterThanOrEqual(result.lowerBound, 100)
        XCTAssertLessThanOrEqual(result.upperBound, 200)
        XCTAssertEqual(result.upperBound - result.lowerBound, 25, accuracy: 0.0001)
    }
}
