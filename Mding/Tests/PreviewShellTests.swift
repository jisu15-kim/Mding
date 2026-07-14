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
