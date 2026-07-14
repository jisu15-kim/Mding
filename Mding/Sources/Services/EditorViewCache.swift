import AppKit

/// 문서별 에디터 NSScrollView(EditorTextView 포함)를 탭 수명 동안 유지하는 캐시.
/// 탭 전환으로 SwiftUI 가 NSViewRepresentable 을 파괴해도 뷰 인스턴스를 재사용해
/// undo 히스토리·선택·스크롤·IME 상태를 통째로 보존한다 (웹뷰 LRU 풀 §4.2 와 대칭 구조 —
/// 단, NSTextView 는 웹뷰와 달리 가벼우므로 개수 상한을 두지 않는다).
@MainActor
final class EditorViewCache {
    static let shared = EditorViewCache()

    private var views: [UUID: NSScrollView] = [:]

    private init() {}

    /// 캐시된 에디터 뷰 (없으면 nil — 호출측이 만들어 `store` 한다).
    func scrollView(for id: UUID) -> NSScrollView? {
        views[id]
    }

    func store(_ scrollView: NSScrollView, for id: UUID) {
        views[id] = scrollView
    }

    /// 탭 닫힘 — 즉시 해제.
    func release(_ id: UUID) {
        views[id]?.removeFromSuperview()
        views[id] = nil
    }
}
