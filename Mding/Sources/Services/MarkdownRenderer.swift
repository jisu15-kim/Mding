import Foundation
import WebKit

/// preview.html 셸에 대한 JS 브리지. 셸은 1회 로드, 이후 함수 호출로 본문만 갱신.
@MainActor
enum MarkdownRenderer {
    /// 번들된 프리뷰 셸(preview.html)의 URL.
    static var shellURL: URL? {
        Bundle.main.url(forResource: "preview", withExtension: "html", subdirectory: "Preview")
    }

    static func render(_ markdown: String, in webView: WKWebView) {
        let b64 = Data(markdown.utf8).base64EncodedString()
        webView.evaluateJavaScript("window.renderMarkdown('\(b64)')")
    }

    /// 웹뷰 LRU 풀(§4.2)이 퇴출된 프리뷰를 재생성할 때 마지막 스크롤 비율을 복원한다.
    static func restoreScroll(ratio: Double, in webView: WKWebView) {
        webView.evaluateJavaScript("window.scrollToRatio(\(ratio))")
    }

    /// name: "system" | "light" | "dark"
    static func setTheme(_ name: String, in webView: WKWebView) {
        webView.evaluateJavaScript("window.setTheme('\(name)')")
    }

    /// 전체 너비(§전체너비): on 이면 본문 칼럼 상한(980px)을 풀어 창 폭을 쓴다(문서별 설정).
    static func setFullWidth(_ on: Bool, in webView: WKWebView) {
        webView.evaluateJavaScript("window.setFullWidth(\(on))")
    }

    /// 아웃라인 사이드바 클릭 점프(§ 아웃라인 사이드바) — `line` 은 0-based 소스 라인 인덱스로
    /// heading_open 렌더러 룰이 심어둔 `data-line` 과 매칭한다.
    static func scrollToHeading(line: Int, in webView: WKWebView) {
        webView.evaluateJavaScript("window.scrollToLine(\(line))")
    }
}
