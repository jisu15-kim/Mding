import Foundation

/// 윈도우 간 탭 드래그 상태를 공유하는 싱글턴 (§4.1 확장 — 윈도우 간 탭 드래그 이동).
/// `.onDrag`/`DropDelegate` 는 서로 다른 뷰 트리(다른 윈도우)에 속해 `@State` 를 공유할 수
/// 없으므로, 드래그 중인 탭과 출발 윈도우를 여기 보관한다. 뷰 렌더링이 이 값을 직접 읽지
/// 않으므로(드롭 시점에만 참조) `@Observable` 은 불필요하다.
@MainActor
final class TabDragContext {
    static let shared = TabDragContext()

    private(set) var dragging: (tab: DocumentViewModel, source: WindowViewModel)?

    private init() {}

    /// 드래그 시작. 이전 드래그가 취소되어 `end()` 가 호출되지 않았더라도(stale 상태),
    /// 새 드래그가 항상 이전 값을 덮어쓰므로 안전하다.
    func begin(tab: DocumentViewModel, source: WindowViewModel) {
        dragging = (tab, source)
    }

    func end() {
        dragging = nil
    }
}
