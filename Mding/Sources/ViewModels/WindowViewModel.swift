import AppKit
import Observation

/// 한 윈도우의 탭 배열 + 선택 상태 (§4.1). 커스텀 탭 모델이라 시스템 윈도우 탭은 쓰지 않는다.
@MainActor @Observable
final class WindowViewModel: Identifiable {
    let id = UUID()
    var tabs: [DocumentViewModel] = []
    var selectedTabID: DocumentViewModel.ID?

    @ObservationIgnored weak var nsWindow: NSWindow?
    @ObservationIgnored private var closeInterceptor: WindowCloseInterceptor?
    @ObservationIgnored private var keyObserver: (any NSObjectProtocol)?

    var selectedTab: DocumentViewModel? { tabs.first { $0.id == selectedTabID } }
    var selectedIndex: Int? { tabs.firstIndex { $0.id == selectedTabID } }

    init() {
        // 레지스트리 등록은 실제 화면에 붙는 인스턴스만 하도록 WindowRootView.onAppear 에서 처리한다
        // (SwiftUI @State 가 생성 후 버리는 인스턴스가 유령으로 남지 않게).
        newTab()  // 시작 시 Welcome 탭 1개
    }

    deinit {
        if let keyObserver {
            NotificationCenter.default.removeObserver(keyObserver)
        }
    }

    // MARK: - 탭 조작

    @discardableResult
    func newTab(url: URL? = nil) -> DocumentViewModel {
        let doc = DocumentViewModel()
        if let url {
            doc.loadPresentingError(url: url)  // 실패 시 알럿 후 Welcome 탭으로 남는다
        }
        tabs.append(doc)
        selectedTabID = doc.id
        return doc
    }

    /// Finder 열기/드롭/⌘O: 이미 열린 파일이면 기존 탭 포커스(중복 열기 방지 — 같은 파일을
    /// 두 탭이 각자 자동저장하면 충돌·유실 위험). 아니면 빈 Welcome 탭 전환 또는 새 탭.
    func openFile(url: URL) {
        if WindowRegistry.shared.focusTab(for: url) { return }
        if let sel = selectedTab, sel.mode == .welcome {
            sel.loadPresentingError(url: url)
            selectedTabID = sel.id
        } else {
            newTab(url: url)
        }
    }

    func selectTab(_ id: DocumentViewModel.ID) { selectedTabID = id }

    func selectTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        selectedTabID = tabs[index].id
    }

    func selectNextTab() {
        guard let i = selectedIndex, tabs.count > 1 else { return }
        selectedTabID = tabs[(i + 1) % tabs.count].id
    }

    func selectPreviousTab() {
        guard let i = selectedIndex, tabs.count > 1 else { return }
        selectedTabID = tabs[(i - 1 + tabs.count) % tabs.count].id
    }

    func moveTab(from source: IndexSet, to destination: Int) {
        tabs.move(fromOffsets: source, toOffset: destination)
    }

    /// 다른 윈도우의 탭을 이 윈도우로 이동(§4.1 확장 — 윈도우 간 탭 드래그).
    /// 웹뷰 풀/에디터 캐시가 문서 id 키라 뷰 상태(스크롤/undo/IME)가 그대로 따라온다 — teardown 금지.
    func adoptTab(_ doc: DocumentViewModel, from source: WindowViewModel, at index: Int? = nil) {
        guard source !== self, let removeIdx = source.tabs.firstIndex(where: { $0.id == doc.id }) else { return }

        source.tabs.remove(at: removeIdx)
        if source.selectedTabID == doc.id {
            source.selectedTabID = source.tabs.isEmpty ? nil : source.tabs[min(removeIdx, source.tabs.count - 1)].id
        }

        let insertIdx = min(max(index ?? tabs.count, 0), tabs.count)
        tabs.insert(doc, at: insertIdx)
        selectedTabID = doc.id

        // source.nsWindow?.close() 는 windowShouldClose 델리게이트 훅을 타지 않으므로
        // handleWindowShouldClose 의 flush/teardown 루프에 걸리지 않는다(이동한 탭은 이미 처리됨).
        if source.tabs.isEmpty {
            source.nsWindow?.close()
        }
    }

    /// 탭 닫기. dirty Untitled 는 저장 확인, 마지막 탭이면 윈도우를 닫는다.
    func closeTab(_ id: DocumentViewModel.ID) {
        guard let idx = tabs.firstIndex(where: { $0.id == id }) else { return }
        let doc = tabs[idx]

        if doc.hasUnsavedUntitledContent, !confirmClose(doc) { return }
        if !doc.flush(), !confirmCloseDespiteFailedSave(doc) { return }
        doc.teardownViews()
        tabs.remove(at: idx)

        if tabs.isEmpty {
            nsWindow?.close()
            return
        }
        if selectedTabID == id {
            selectedTabID = tabs[min(idx, tabs.count - 1)].id
        }
    }

    func closeSelectedTab() {
        if let id = selectedTabID { closeTab(id) }
    }

    // MARK: - NSWindow 연결

    /// WindowAccessor 가 실제 NSWindow 를 잡으면(매 업데이트) 호출. close 훅 설치 + 활성화 추적.
    func attach(window: NSWindow) {
        if nsWindow !== window {
            nsWindow = window
            // 타이틀바 hairline 제거 — 크롬 통합 배경(WindowRootView)이 끊김 없이 이어지게.
            window.titlebarSeparatorStyle = .none
            keyObserver.map(NotificationCenter.default.removeObserver)
            keyObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    WindowRegistry.shared.noteActivated(self.id)
                }
            }
        }

        // 델리게이트가 우리 인터셉터가 아니면 재설치(SwiftUI 가 되돌렸을 수 있음).
        // 자기 자신을 previous 로 감싸면 포워딩 루프가 되므로 반드시 타입 체크로 방지한다.
        if !(window.delegate is WindowCloseInterceptor) {
            let interceptor = WindowCloseInterceptor(model: self, previous: window.delegate)
            closeInterceptor = interceptor
            window.delegate = interceptor
        }
    }

    /// windowShouldClose 훅. ⌘W(키 이벤트)는 선택 탭만 닫고, 빨간 닫기 버튼(마우스)은
    /// Safari 처럼 윈도우 전체를 닫는다. 마지막 탭에서의 ⌘W 는 윈도우 닫기로 이어진다.
    func handleWindowShouldClose() -> Bool {
        let isKeyClose = NSApp.currentEvent?.type == .keyDown
        if isKeyClose, tabs.count > 1 {
            closeSelectedTab()
            return false
        }

        // 윈도우 전체 닫기: 모든 탭 확인 → flush → 뷰 해제.
        for doc in tabs where doc.hasUnsavedUntitledContent {
            if !confirmClose(doc) { return false }
        }
        for doc in tabs where !doc.flush() {
            if !confirmCloseDespiteFailedSave(doc) { return false }
        }
        for doc in tabs {
            doc.teardownViews()
        }
        return true  // 실제 윈도우 닫힘 → WindowRootView.onDisappear 에서 unregister
    }

    /// dirty Untitled 저장 확인. true = 닫기 진행, false = 취소.
    private func confirmClose(_ doc: DocumentViewModel) -> Bool {
        let alert = NSAlert()
        alert.messageText = String(
            localized: "Do you want to save the changes you made?",
            comment: "Title of the confirmation shown when closing an unsaved untitled document"
        )
        alert.informativeText = String(
            localized: "Your changes will be lost if you don't save them.",
            comment: "Message of the unsaved-changes confirmation when closing a tab"
        )
        alert.addButton(withTitle: String(localized: "Save…", comment: "Button that saves an untitled document before closing"))
        alert.addButton(withTitle: String(localized: "Cancel", comment: "Button that cancels closing a tab"))
        alert.addButton(withTitle: String(localized: "Don't Save", comment: "Button that discards unsaved changes and closes the tab"))

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            doc.saveDocument()
            return doc.fileURL != nil  // Save 패널을 취소했으면 닫기도 취소
        case .alertThirdButtonReturn:
            return true                // Don't Save
        default:
            return false               // Cancel
        }
    }

    /// 디스크 flush 실패 시 확인. true = 그래도 닫기, false = 취소.
    private func confirmCloseDespiteFailedSave(_ doc: DocumentViewModel) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(
            localized: "Couldn't save \"\(doc.displayName)\".",
            comment: "Title of the warning shown when saving to disk failed while closing a tab"
        )
        alert.informativeText = String(
            localized: "Your latest changes could not be written to disk. Close anyway and lose them?",
            comment: "Message of the failed-save warning when closing a tab"
        )
        alert.addButton(withTitle: String(localized: "Cancel", comment: "Button that cancels closing a tab"))
        alert.addButton(withTitle: String(localized: "Close Anyway", comment: "Button that closes the tab despite a failed save"))
        return alert.runModal() == .alertSecondButtonReturn
    }
}

/// SwiftUI 가 설정한 기존 NSWindowDelegate 를 보존하면서 windowShouldClose 만 가로챈다 (§4.1).
/// 표준 ⌘W(Close)가 윈도우 대신 현재 탭을 닫도록 만들기 위함. 다른 델리게이트 메시지는 그대로 전달.
final class WindowCloseInterceptor: NSObject, NSWindowDelegate {
    private weak var model: WindowViewModel?
    private weak var previous: NSWindowDelegate?

    init(model: WindowViewModel, previous: NSWindowDelegate?) {
        self.model = model
        self.previous = previous
        super.init()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        MainActor.assumeIsolated { model?.handleWindowShouldClose() ?? true }
    }

    override func responds(to aSelector: Selector!) -> Bool {
        if super.responds(to: aSelector) { return true }
        return previous?.responds(to: aSelector) ?? false
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if let previous, previous.responds(to: aSelector) { return previous }
        return nil
    }
}
