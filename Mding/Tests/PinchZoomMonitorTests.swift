import XCTest
@testable import Mding

/// 핀치 배율 → 폰트 크기 매핑 검증: 1pt 반올림, 범위 클램프, 시작 크기 기준 비례.
final class PinchZoomMonitorTests: XCTestCase {
    @MainActor
    func test_zeroMagnification_keepsStart() {
        XCTAssertEqual(PinchZoomMonitor.targetFontSize(start: 13, magnification: 0), 13)
        XCTAssertEqual(PinchZoomMonitor.targetFontSize(start: 20, magnification: 0), 20)
    }

    @MainActor
    func test_roundsToWholePoint() {
        // 13 × 1.03 = 13.39 → 13 (아직 한 눈금 못 넘음), 13 × 1.1 = 14.3 → 14.
        XCTAssertEqual(PinchZoomMonitor.targetFontSize(start: 13, magnification: 0.03), 13)
        XCTAssertEqual(PinchZoomMonitor.targetFontSize(start: 13, magnification: 0.1), 14)
        // 13 × 0.9 = 11.7 → 12.
        XCTAssertEqual(PinchZoomMonitor.targetFontSize(start: 13, magnification: -0.1), 12)
    }

    @MainActor
    func test_scalesFromGestureStart_notDefault() {
        // 시작 크기가 기본값이 아니어도 그 크기 기준으로 비례한다: 20 × 1.2 = 24.
        XCTAssertEqual(PinchZoomMonitor.targetFontSize(start: 20, magnification: 0.2), 24)
    }

    @MainActor
    func test_clampsToEditorFontSizeRange() {
        let range = AppSettings.editorFontSizeRange
        XCTAssertEqual(PinchZoomMonitor.targetFontSize(start: 13, magnification: 3), range.upperBound)
        XCTAssertEqual(PinchZoomMonitor.targetFontSize(start: 13, magnification: -0.9), range.lowerBound)
        // 이미 경계에 있을 때 그 방향으로 더 벌려도 경계를 넘지 않는다.
        XCTAssertEqual(PinchZoomMonitor.targetFontSize(start: range.upperBound, magnification: 0.5), range.upperBound)
        XCTAssertEqual(PinchZoomMonitor.targetFontSize(start: range.lowerBound, magnification: -0.5), range.lowerBound)
    }
}
