import AppKit
import WebKit

/// 프리뷰 WKWebView 를 앱 전체 최대 5개(LRU)로 관리한다 (§4.2).
/// VSCode 의 hidden-webview dispose 전략 변형: 화면에서 오래 벗어난 웹뷰를 파괴하고
/// 문서에는 원본 텍스트 + 마지막 스크롤 비율만 남겼다가, 재선택 시 재생성·재렌더·스크롤 복원한다.
@MainActor
final class PreviewWebViewPool {
    static let shared = PreviewWebViewPool()

    private let maxLive = 5
    private var webViews: [UUID: WKWebView] = [:]
    private var order: [UUID] = []       // LRU: 뒤로 갈수록 최근 사용
    private var mounted: Set<UUID> = []  // 현재 화면에 붙어 있는 문서 — 퇴출 금지

    private init() {}

    /// 살아 있는 웹뷰 수 (테스트/디버깅용).
    var liveCount: Int { webViews.count }

    /// 문서용 웹뷰를 확보한다. 풀에 있으면 재사용(LRU 갱신), 없으면 생성.
    /// 생성으로 상한(5)을 넘으면 가장 오래 안 본 비표시 웹뷰를 해제한다.
    /// 반환 `isNew == true` 면 호출측이 셸을 로드해야 한다.
    func acquire(for document: DocumentViewModel) -> (webView: WKWebView, isNew: Bool) {
        touch(document.id)
        mounted.insert(document.id)

        if let existing = webViews[document.id] {
            return (existing, false)
        }

        let webView = makeWebView(for: document)
        webViews[document.id] = webView
        evictIfNeeded(keeping: document.id)
        return (webView, true)
    }

    /// 웹뷰가 화면에서 분리됨(탭 전환). 파괴하지 않고 풀에 남긴다.
    func markInactive(_ id: UUID) {
        mounted.remove(id)
    }

    /// 탭 닫힘 — 즉시 파괴.
    func release(_ id: UUID) {
        if let webView = webViews[id] {
            teardown(webView)
        }
        webViews[id] = nil
        order.removeAll { $0 == id }
        mounted.remove(id)
    }

    /// 살아 있는 모든 웹뷰에 동작을 적용한다 (테마 일괄 전환 §4.6).
    func applyToAll(_ body: (WKWebView) -> Void) {
        for webView in webViews.values {
            body(webView)
        }
    }

    /// 풀에 살아있는 웹뷰(있으면). 아웃라인 사이드바 점프(OutlineNavigator)가 프리뷰 스크롤에 쓴다.
    /// 퇴출된(비표시) 문서는 nil — 그 경우 점프는 no-op(재선택 시 스크롤 비율 복원 경로로 대체됨).
    func webView(for id: UUID) -> WKWebView? {
        webViews[id]
    }

    // MARK: - 내부

    private func touch(_ id: UUID) {
        order.removeAll { $0 == id }
        order.append(id)
    }

    private func evictIfNeeded(keeping keep: UUID) {
        while webViews.count > maxLive {
            // 화면에 붙어 있지 않은 것 중 가장 오래된 것을 퇴출. keep 은 항상 보존.
            guard let victim = order.first(where: { $0 != keep && !mounted.contains($0) }) else {
                break  // 전부 표시 중이면 상한을 넘겨서라도 유지(정확성 우선).
            }
            if let webView = webViews[victim] {
                teardown(webView)
            }
            webViews[victim] = nil
            order.removeAll { $0 == victim }
            // 퇴출된 문서는 previewScrollRatio 만 유지(미러링됨) → 재선택 시 복원.
        }
    }

    private func makeWebView(for document: DocumentViewModel) -> WKWebView {
        let config = WKWebViewConfiguration()
        let reporter = ScrollReporter(document: document)
        config.userContentController.add(reporter, name: "scroll")
        let webView = PreviewWKWebView(frame: .zero, configuration: config)
        // 로드 전 흰 플래시 방지 — 크롬 통합 배경(§4.8 확장)과 동일한 색이라 셸 로드가
        // 끝나기 전에도 창 배경과 이어져 보인다. CSS 문서 배경(github-markdown-*.css)과 정확히 일치.
        webView.underPageBackgroundColor = AppColors.contentBackground
        return webView
    }

    private func teardown(_ webView: WKWebView) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "scroll")
        webView.removeFromSuperview()
    }
}

/// md 파일 드롭을 받는 WKWebView 서브클래스(윈도우 전역 드롭 §4.1 확장).
/// WKWebView 는 기본적으로 파일 드롭을 자체 file: 네비게이션으로 처리해 프리뷰 셸을 대체할 수 있어
/// 마크다운 파일이 섞인 드롭만 가로챈다. 그 외 드래그는 기존 동작(WebKit 기본)을 보존한다.
final class PreviewWKWebView: WKWebView {
    var onMarkdownFileDrop: (([URL]) -> Bool)?

    private func markdownFileURLs(from draggingInfo: NSDraggingInfo) -> [URL]? {
        guard let urls = draggingInfo.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] else { return nil }
        let mdURLs = urls.filter(FileService.isMarkdownFile)
        return mdURLs.isEmpty ? nil : mdURLs
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        markdownFileURLs(from: sender) != nil ? .copy : super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        markdownFileURLs(from: sender) != nil ? .copy : super.draggingUpdated(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let mdURLs = markdownFileURLs(from: sender) {
            return onMarkdownFileDrop?(mdURLs) ?? false
        }
        return super.performDragOperation(sender)
    }
}

/// 프리뷰 스크롤 메시지 핸들러 (§4.2, § 스크롤 동기화).
/// restore(전체 높이 비율)는 문서로 미러링(풀 해제 후 복원 기준), sync(스크롤 가능 범위 비율)는
/// 스플릿 모드 에디터 동기화로 전달한다. 콜백은 메인 스레드라 `assumeIsolated` 가 안전하다.
private final class ScrollReporter: NSObject, WKScriptMessageHandler {
    private weak var document: DocumentViewModel?

    init(document: DocumentViewModel) {
        self.document = document
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let body = message.body as? [String: Any] else { return }
        MainActor.assumeIsolated {
            guard let document else { return }
            if let restore = (body["restore"] as? NSNumber)?.doubleValue {
                document.previewScrollRatio = restore
            }
            if let sync = (body["sync"] as? NSNumber)?.doubleValue {
                ScrollSyncService.previewDidScroll(document, syncRatio: sync)
            }
        }
    }
}
