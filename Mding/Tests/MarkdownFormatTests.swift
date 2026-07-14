import AppKit
import XCTest
@testable import Mding

/// MarkdownFormat.toggle 필수 단위 테스트 (ExecutionPlan §6).
@MainActor
final class MarkdownFormatTests: XCTestCase {
    private static let markers = ["**", "_", "~~", "`"]

    /// undoManager 를 공급하는 델리게이트 (standalone NSTextView 는 undoManager 가 없음).
    private final class UndoProvidingDelegate: NSObject, NSTextViewDelegate {
        let undoManager = UndoManager()
        func undoManager(for view: NSTextView) -> UndoManager? { undoManager }
    }

    private func makeTextView(_ text: String, selected: NSRange) -> (NSTextView, UndoProvidingDelegate) {
        let textView = NSTextView()
        let delegate = UndoProvidingDelegate()
        textView.delegate = delegate
        textView.allowsUndo = true
        textView.string = text
        textView.setSelectedRange(selected)
        return (textView, delegate)
    }

    func test_wrap_selection() {
        for marker in Self.markers {
            let (tv, _) = makeTextView("hello world", selected: NSRange(location: 0, length: 5))
            MarkdownFormat.toggle(marker, in: tv)
            XCTAssertEqual(tv.string, "\(marker)hello\(marker) world", "marker: \(marker)")
            XCTAssertEqual(tv.selectedRange(), NSRange(location: marker.count, length: 5), "marker: \(marker)")
        }
    }

    func test_unwrap_whenMarkersAreOutsideSelection() {
        for marker in Self.markers {
            let m = marker.count
            let (tv, _) = makeTextView("\(marker)hello\(marker) world", selected: NSRange(location: m, length: 5))
            MarkdownFormat.toggle(marker, in: tv)
            XCTAssertEqual(tv.string, "hello world", "marker: \(marker)")
            XCTAssertEqual(tv.selectedRange(), NSRange(location: 0, length: 5), "marker: \(marker)")
        }
    }

    func test_unwrap_whenSelectionIncludesMarkers() {
        for marker in Self.markers {
            let m = marker.count
            let (tv, _) = makeTextView("\(marker)hello\(marker) world", selected: NSRange(location: 0, length: 5 + 2 * m))
            MarkdownFormat.toggle(marker, in: tv)
            XCTAssertEqual(tv.string, "hello world", "marker: \(marker)")
            XCTAssertEqual(tv.selectedRange(), NSRange(location: 0, length: 5), "marker: \(marker)")
        }
    }

    func test_emptySelection_insertsMarkerPairWithCursorCentered() {
        for marker in Self.markers {
            let m = marker.count
            let (tv, _) = makeTextView("ab", selected: NSRange(location: 1, length: 0))
            MarkdownFormat.toggle(marker, in: tv)
            XCTAssertEqual(tv.string, "a\(marker)\(marker)b", "marker: \(marker)")
            XCTAssertEqual(tv.selectedRange(), NSRange(location: 1 + m, length: 0), "marker: \(marker)")
        }
    }

    func test_undo_restoresOriginalTextInOneStep() {
        let (tv, delegate) = makeTextView("hello world", selected: NSRange(location: 0, length: 5))
        MarkdownFormat.toggle("**", in: tv)
        XCTAssertEqual(tv.string, "**hello** world")
        delegate.undoManager.undo()
        XCTAssertEqual(tv.string, "hello world", "single undo must restore the original text")
    }

    func test_insertLink_wrapsSelectionAsMarkdownLink() {
        let (tv, _) = makeTextView("hello world", selected: NSRange(location: 0, length: 5))
        MarkdownFormat.insertLink(url: "https://example.com", in: tv)
        XCTAssertEqual(tv.string, "[hello](https://example.com) world")
    }

    func test_insertLink_emptySelection_placesCursorInLabel() {
        let (tv, _) = makeTextView("", selected: NSRange(location: 0, length: 0))
        MarkdownFormat.insertLink(url: "https://example.com", in: tv)
        XCTAssertEqual(tv.string, "[](https://example.com)")
        XCTAssertEqual(tv.selectedRange(), NSRange(location: 1, length: 0))
    }
}
