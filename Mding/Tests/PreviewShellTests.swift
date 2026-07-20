import WebKit
import XCTest
@testable import Mding

/// preview.html 셸이 번들 에셋만으로(GFM 표/체크박스/링크 + 코드 하이라이팅) 렌더되는지 검증한다.
@MainActor
final class PreviewShellTests: XCTestCase {
    private static let sampleMarkdown = """
    # Title

    | A | B |
    |---|---|
    | 1 | 2 |

    - [x] done
    - [ ] todo

    [link](https://example.com)

    ```swift
    let x = 1
    ```

    ~~strike~~
    """

    func test_shellURL_existsInBundle() {
        XCTAssertNotNil(MarkdownRenderer.shellURL, "preview.html must be bundled under Preview/")
    }

    func test_renderMarkdown_producesGFMAndHighlightedHTML() throws {
        let shellURL = try XCTUnwrap(MarkdownRenderer.shellURL)
        let webView = WKWebView()
        webView.loadFileURL(shellURL, allowingReadAccessTo: shellURL.deletingLastPathComponent())

        try waitUntil(timeout: 10, description: "shell loaded") {
            try await self.evaluate(in: webView, "typeof window.renderMarkdown === 'function'") as? Bool == true
        }

        MarkdownRenderer.render(Self.sampleMarkdown, in: webView)

        var html = ""
        try waitUntil(timeout: 10, description: "content rendered") {
            html = try await self.evaluate(in: webView, "document.getElementById('content').innerHTML") as? String ?? ""
            return html.contains("<table>")
        }

        XCTAssertTrue(html.contains("<table>"), "GFM table should render")
        XCTAssertTrue(html.contains("task-list-item"), "GFM task list should render")
        XCTAssertTrue(html.contains("checkbox"), "task list checkboxes should render")
        XCTAssertTrue(html.contains("<a href=\"https://example.com\""), "links should render")
        XCTAssertTrue(html.contains("hljs-keyword"), "code block should be highlighted by highlight.js")
        XCTAssertTrue(html.contains("<s>strike</s>"), "GFM strikethrough should render")
    }

    // MARK: - 찾기(⌘F) 브리지

    private func loadShellRendered(_ markdown: String) throws -> WKWebView {
        let shellURL = try XCTUnwrap(MarkdownRenderer.shellURL)
        let webView = WKWebView()
        webView.loadFileURL(shellURL, allowingReadAccessTo: shellURL.deletingLastPathComponent())
        try waitUntil(timeout: 10, description: "shell loaded") {
            try await self.evaluate(in: webView, "typeof window.mdFind === 'function'") as? Bool == true
        }
        MarkdownRenderer.render(markdown, in: webView)
        try waitUntil(timeout: 10, description: "content rendered") {
            let html = try await self.evaluate(in: webView, "document.getElementById('content').innerHTML") as? String ?? ""
            return html.contains("apple")
        }
        return webView
    }

    func test_mdFind_countsMatchesAndCyclesWithCaseSensitivity() throws {
        let webView = try loadShellRendered("apple banana apple\n\napple pie")

        // CSS Custom Highlight API 가 이 WebKit 에서 실제로 지원되어야 프리뷰 하이라이트가 보인다.
        let supported = try awaitEval(webView, "typeof CSS !== 'undefined' && !!CSS.highlights && typeof Highlight !== 'undefined'") as? Bool
        XCTAssertEqual(supported, true, "CSS Custom Highlight API must be available in WKWebView")

        // 대소문자 무시: apple 3회, 첫 매치가 현재(1).
        XCTAssertEqual(try awaitEval(webView, "window.mdFind('apple', false).count") as? Int, 3)
        XCTAssertEqual(try awaitEval(webView, "window.mdFind('apple', false).index") as? Int, 1)
        XCTAssertEqual(try awaitEval(webView, "CSS.highlights.has('md-find')") as? Bool, true)

        // 다음/이전 순환.
        XCTAssertEqual(try awaitEval(webView, "window.mdFindStep(1).index") as? Int, 2)
        XCTAssertEqual(try awaitEval(webView, "window.mdFindStep(1).index") as? Int, 3)
        XCTAssertEqual(try awaitEval(webView, "window.mdFindStep(1).index") as? Int, 1, "끝에서 처음으로 순환")
        XCTAssertEqual(try awaitEval(webView, "window.mdFindStep(-1).index") as? Int, 3, "처음에서 끝으로 순환")

        // 대소문자 구분: 대문자 APPLE 은 본문에 없다.
        XCTAssertEqual(try awaitEval(webView, "window.mdFind('APPLE', true).count") as? Int, 0)
        XCTAssertEqual(try awaitEval(webView, "window.mdFind('APPLE', false).count") as? Int, 3)

        // Split 비활성 pane: showCurrent=false → 노란 매치만, 현재(주황) 없음, 카운트 index=0.
        XCTAssertEqual(try awaitEval(webView, "window.mdFind('apple', false, false).count") as? Int, 3)
        XCTAssertEqual(try awaitEval(webView, "window.mdFind('apple', false, false).index") as? Int, 0)
        XCTAssertEqual(try awaitEval(webView, "CSS.highlights.has('md-find')") as? Bool, true, "비활성 pane 도 노란 매치는 칠한다")
        XCTAssertEqual(try awaitEval(webView, "CSS.highlights.has('md-find-current')") as? Bool, false, "비활성 pane 은 현재(주황) 강조 없음")

        // clear 후 하이라이트 제거.
        _ = try awaitEval(webView, "window.mdFindClear()")
        XCTAssertEqual(try awaitEval(webView, "CSS.highlights.has('md-find')") as? Bool, false)
    }

    func test_setTheme_switchesBodyDataTheme() throws {
        let shellURL = try XCTUnwrap(MarkdownRenderer.shellURL)
        let webView = WKWebView()
        webView.loadFileURL(shellURL, allowingReadAccessTo: shellURL.deletingLastPathComponent())

        try waitUntil(timeout: 10, description: "shell loaded") {
            try await self.evaluate(in: webView, "typeof window.setTheme === 'function'") as? Bool == true
        }

        MarkdownRenderer.setTheme("dark", in: webView)

        try waitUntil(timeout: 10, description: "theme applied") {
            try await self.evaluate(in: webView, "document.body.dataset.theme") as? String == "dark"
        }
    }

    // MARK: - Helpers

    /// 비동기 evaluateJavaScript 를 메인 런루프를 돌리며 동기적으로 기다린다(테스트 편의).
    private func awaitEval(_ webView: WKWebView, _ script: String) throws -> Any? {
        var captured: Any?
        var caught: Error?
        let expectation = expectation(description: "eval: \(script)")
        let task = Task { @MainActor in
            do { captured = try await self.evaluate(in: webView, script) }
            catch { caught = error }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 10)
        task.cancel()
        if let caught { throw caught }
        return captured
    }

    private func evaluate(in webView: WKWebView, _ script: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result)
                }
            }
        }
    }

    /// 메인 런루프를 돌리면서 condition 이 참이 될 때까지 폴링한다.
    private func waitUntil(
        timeout: TimeInterval,
        description: String,
        condition: @escaping () async throws -> Bool
    ) throws {
        let expectation = expectation(description: description)
        let task = Task { @MainActor in
            while !Task.isCancelled {
                if (try? await condition()) == true {
                    expectation.fulfill()
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        wait(for: [expectation], timeout: timeout)
        task.cancel()
    }
}
