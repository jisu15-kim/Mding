import AppKit
import WebKit

/// 스플릿 모드 에디터↔프리뷰 스크롤 동기화 (비율 기반, 양방향).
///
/// 비율은 "스크롤 가능 범위(콘텐츠 높이 − 뷰포트)" 기준이라 양쪽 문서 끝이 서로의 끝에 맞는다.
/// 에코 루프 차단은 양쪽에서 각각 수행한다:
/// - 프리뷰→에디터 프로그램 스크롤 동안 `suppressedEditors` 로 에디터 bounds 알림을 무시
/// - 에디터→프리뷰 프로그램 스크롤 직후에는 JS 쪽 `suppressSyncUntil` 이 sync 메시지를 생략
@MainActor
enum ScrollSyncService {
    private static var suppressedEditors: Set<UUID> = []
    private static var lastSentRatio: [UUID: Double] = [:]

    /// 에디터 스크롤 → 프리뷰 반영. 에디터 clip view 의 bounds 변경에서 호출된다.
    static func editorDidScroll(_ document: DocumentViewModel, scrollView: NSScrollView) {
        guard document.viewMode == .split,
              !suppressedEditors.contains(document.id),
              let webView = PreviewWebViewPool.shared.webView(for: document.id)
        else { return }

        let ratio = scrollableRatio(of: scrollView)
        // 리사이즈 등 스크롤과 무관한 bounds 변경 노이즈 억제 — 유의미한 변화만 전송.
        guard abs((lastSentRatio[document.id] ?? -1) - ratio) > 0.0005 else { return }
        lastSentRatio[document.id] = ratio
        webView.evaluateJavaScript("window.syncScrollFromEditor(\(ratio))")
    }

    /// 프리뷰 스크롤 → 에디터 반영. ScrollReporter(sync 메시지)에서 호출된다.
    static func previewDidScroll(_ document: DocumentViewModel, syncRatio: Double) {
        guard document.viewMode == .split,
              let scrollView = EditorViewCache.shared.scrollView(for: document.id),
              let documentView = scrollView.documentView
        else { return }

        // setBoundsOrigin 이 동기적으로 bounds 알림을 발화하므로 defer 해제로 충분하다.
        suppressedEditors.insert(document.id)
        defer { suppressedEditors.remove(document.id) }

        let clip = scrollView.contentView
        let maxY = max(0, documentView.frame.height - clip.bounds.height)
        let clamped = min(1, max(0, syncRatio))
        clip.setBoundsOrigin(NSPoint(x: clip.bounds.origin.x, y: clamped * maxY))
        scrollView.reflectScrolledClipView(clip)
    }

    private static func scrollableRatio(of scrollView: NSScrollView) -> Double {
        guard let documentView = scrollView.documentView else { return 0 }
        let clip = scrollView.contentView
        let maxY = documentView.frame.height - clip.bounds.height
        guard maxY > 0 else { return 0 }
        return min(1, max(0, clip.bounds.origin.y / maxY))
    }
}
