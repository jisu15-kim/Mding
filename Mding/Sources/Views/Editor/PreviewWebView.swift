import SwiftUI
import WebKit

/// 프리뷰 웹뷰. 웹뷰 자체는 `PreviewWebViewPool`(§4.2)이 소유·재사용하며, 이 뷰는
/// 문서 단위(`.id(doc.id)`)로 마운트되어 풀에서 웹뷰를 빌려 렌더링만 구동한다.
/// 셸(preview.html)은 1회 로드하고 markdown 변경 시 JS 브리지로 본문만 갱신한다.
struct PreviewWebView: NSViewRepresentable {
    let document: DocumentViewModel

    func makeCoordinator() -> Coordinator { Coordinator(documentID: document.id) }

    func makeNSView(context: Context) -> WKWebView {
        let (webView, isNew) = PreviewWebViewPool.shared.acquire(for: document)
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.document = document
        context.coordinator.pendingMarkdown = document.previewText

        // md 파일 드롭을 문서가 속한 윈도우로 라우팅(윈도우 전역 드롭 §4.1 확장).
        let documentID = document.id
        (webView as? PreviewWKWebView)?.onMarkdownFileDrop = { urls in
            guard let window = WindowRegistry.shared.window(containing: documentID) else { return false }
            for url in urls { window.openFile(url: url) }
            return true
        }

        if isNew {
            // 새로 만든(또는 퇴출 후 재생성된) 웹뷰: 셸 로드 → didFinish 후 렌더 + 스크롤 복원.
            context.coordinator.isShellLoaded = false
            context.coordinator.restoreScrollRatio = document.previewScrollRatio
            if let shellURL = MarkdownRenderer.shellURL {
                webView.loadFileURL(shellURL, allowingReadAccessTo: shellURL.deletingLastPathComponent())
            } else {
                assertionFailure("preview.html shell missing from bundle")
            }
        } else {
            // 풀에서 재사용: 셸은 이미 로드됨. 마지막 렌더 상태를 유지한 채 최신 본문만 반영.
            // 재사용 웹뷰의 body 에는 이전 문서의 전체 너비 상태가 남아 있으므로 이 문서 값으로 재설정.
            context.coordinator.isShellLoaded = true
            context.coordinator.renderIfNeeded()
            context.coordinator.applyFullWidthIfNeeded()
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.document = document
        context.coordinator.pendingMarkdown = document.previewText
        context.coordinator.renderIfNeeded()
        context.coordinator.applyFullWidthIfNeeded()
        Self.applyZoom(to: webView)
    }

    /// 프리뷰 zoom 을 에디터 폰트 크기에 비례시킨다(⌘+/⌘- 글자 크기 조정, 기본 크기 = 1.0).
    /// AppSettings 읽기는 Observation 에 추적되어 설정 변경 시 updateNSView 가 다시 불린다.
    static func applyZoom(to webView: WKWebView) {
        let zoom = AppSettings.shared.editorFontSize / AppSettings.defaultEditorFontSize
        if abs(webView.pageZoom - zoom) > 0.001 {
            webView.pageZoom = zoom
        }
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        // 탭 전환: 웹뷰를 파괴하지 않고 풀에 반납(비표시 표시). 탭 닫힘은 VM.teardownViews 가 처리.
        PreviewWebViewPool.shared.markInactive(coordinator.documentID)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        let documentID: UUID
        weak var webView: WKWebView?
        weak var document: DocumentViewModel?
        var pendingMarkdown = ""
        var isShellLoaded = false
        /// 퇴출 후 재생성 시 복원할 스크롤 비율. 재사용 웹뷰에는 적용하지 않는다.
        var restoreScrollRatio: Double?
        private var renderedMarkdown: String?
        /// 웹뷰에 마지막으로 반영한 전체 너비 값(§전체너비). 중복 JS 호출을 막는 디프 기준.
        private var appliedFullWidth: Bool?

        init(documentID: UUID) {
            self.documentID = documentID
        }

        func renderIfNeeded() {
            guard isShellLoaded, let webView, renderedMarkdown != pendingMarkdown else { return }
            renderedMarkdown = pendingMarkdown
            MarkdownRenderer.render(pendingMarkdown, in: webView)
            if let ratio = restoreScrollRatio {
                restoreScrollRatio = nil
                MarkdownRenderer.restoreScroll(ratio: ratio, in: webView)
            }
            // 재렌더로 CSS 하이라이트가 사라지므로 찾기 바가 프리뷰를 대상으로 열려 있으면 다시 적용.
            document?.find.previewDidRerender()
        }

        /// 문서별 전체 너비(§전체너비)를 웹뷰에 반영. 값이 바뀌었고 셸이 로드된 경우에만 JS 를 호출한다.
        func applyFullWidthIfNeeded() {
            guard isShellLoaded, let webView, let document else { return }
            let target = document.previewFullWidth
            guard appliedFullWidth != target else { return }
            appliedFullWidth = target
            MarkdownRenderer.setFullWidth(target, in: webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isShellLoaded = true
            // 새로 로드된 셸은 현재 설정 테마로 초기화 (재사용 웹뷰는 ThemeManager 일괄 적용으로 이미 최신).
            MarkdownRenderer.setTheme(AppSettings.shared.theme.previewName, in: webView)
            // 셸이 새로 로드되면 body 속성이 초기화되므로 이 문서의 전체 너비 값을 다시 반영.
            appliedFullWidth = nil
            applyFullWidthIfNeeded()
            renderIfNeeded()
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            // file: 요청은 navigationType 과 무관하게 항상 검사한다 — 드롭이 유발하는 file: 네비게이션은
            // linkActivated 가 아닐 수 있어 navigationType 필터만으로는 셸 대체를 막지 못한다.
            if url.scheme?.lowercased() == "file" {
                // 같은 셸 문서(최초 로드/내부 앵커 이동)만 허용, 다른 파일로의 이동은 차단(v1).
                decisionHandler(url.path == MarkdownRenderer.shellURL?.path ? .allow : .cancel)
                return
            }

            // 그 외 스킴은 사용자가 클릭한 링크일 때만 가로챈다 — 내부 스크립트 네비게이션은 허용.
            guard navigationAction.navigationType == .linkActivated else {
                decisionHandler(.allow)
                return
            }
            switch url.scheme?.lowercased() {
            case "http", "https", "mailto":
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            default:
                decisionHandler(.cancel)
            }
        }
    }
}
