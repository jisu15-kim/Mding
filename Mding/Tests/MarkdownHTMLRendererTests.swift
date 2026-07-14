import XCTest
@testable import Mding

/// JSC 기반 MarkdownHTMLRenderer 가 앱 프리뷰 셸(preview.html)과 동일한 규칙으로 변환하는지
/// 검증한다. Quick Look 익스텐션은 이 렌더러의 출력을 그대로 QLPreviewReply 로 반환한다.
final class MarkdownHTMLRendererTests: XCTestCase {

    private func makeRenderer() throws -> MarkdownHTMLRenderer {
        try MarkdownHTMLRenderer(bundle: Bundle(for: MarkdownHTMLRenderer.self))
    }

    func test_heading_rendersH1() throws {
        let html = try makeRenderer().renderBody("# Hello")
        XCTAssertTrue(html.contains("<h1>Hello</h1>"))
    }

    func test_fencedCode_isHighlighted() throws {
        let html = try makeRenderer().renderBody("```swift\nlet x = 1\n```")
        XCTAssertTrue(html.contains("hljs-keyword"), "swift 코드는 highlight.js 로 하이라이트되어야 함")
    }

    func test_taskList_rendersDisabledCheckbox() throws {
        let html = try makeRenderer().renderBody("- [x] done\n- [ ] todo")
        XCTAssertTrue(html.contains("task-list-item"))
        XCTAssertTrue(html.contains("checkbox"))
        XCTAssertTrue(html.contains("disabled"), "enabled:false 이므로 체크박스는 disabled 여야 함")
    }

    func test_bareURL_isLinkified() throws {
        let html = try makeRenderer().renderBody("https://example.com")
        XCTAssertTrue(html.contains("<a href=\"https://example.com\""))
    }

    func test_rawHTML_isEscaped() throws {
        let html = try makeRenderer().renderBody("<script>alert(1)</script>")
        XCTAssertFalse(html.contains("<script>"), "html:false 이므로 raw HTML 은 이스케이프되어야 함")
        XCTAssertTrue(html.contains("&lt;script&gt;"))
    }

    func test_renderDocument_wrapsBodyWithThemedCSS() throws {
        let html = try makeRenderer().renderDocument("# Hello")
        XCTAssertTrue(html.contains("markdown-body"))
        XCTAssertTrue(html.contains("prefers-color-scheme: dark"))
        XCTAssertTrue(html.contains("#0d1117"), "다크 배경은 preview.html 과 동일해야 함")
    }
}
