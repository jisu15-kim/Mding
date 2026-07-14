import AppKit
import Observation

/// 전 윈도우 VM 의 단일 레지스트리 (§4.1).
/// AppDelegate(종료 flush·Finder 열기 라우팅)와 메뉴 커맨드가 SwiftUI `@State` 소유 VM 에
/// 접근할 통로가 없으므로 이 싱글턴을 둔다.
@MainActor @Observable
final class WindowRegistry {
    static let shared = WindowRegistry()

    private(set) var windows: [WindowViewModel] = []
    private(set) var lastActiveWindowID: WindowViewModel.ID?

    private init() {}

    /// 모든 윈도우의 모든 탭 (종료 flush 용 — DocumentViewModel.liveDocuments 를 대체).
    var allTabs: [DocumentViewModel] { windows.flatMap(\.tabs) }

    /// key window 우선 → lastActive → 첫 윈도우.
    var activeWindow: WindowViewModel? {
        if let keyModel = windows.first(where: { $0.nsWindow?.isKeyWindow == true }) {
            return keyModel
        }
        if let id = lastActiveWindowID, let model = windows.first(where: { $0.id == id }) {
            return model
        }
        return windows.first
    }

    func register(_ vm: WindowViewModel) {
        guard !windows.contains(where: { $0.id == vm.id }) else { return }
        windows.append(vm)
        lastActiveWindowID = vm.id
    }

    func unregister(_ id: WindowViewModel.ID) {
        windows.removeAll { $0.id == id }
        if lastActiveWindowID == id {
            lastActiveWindowID = windows.last?.id
        }
    }

    func noteActivated(_ id: WindowViewModel.ID) {
        lastActiveWindowID = id
    }

    /// 해당 문서 id 를 탭으로 가진 윈도우를 찾는다 — 에디터/프리뷰의 파일 드롭 라우팅용.
    func window(containing id: DocumentViewModel.ID) -> WindowViewModel? {
        windows.first { $0.tabs.contains { $0.id == id } }
    }

    /// 이미 열려 있는 파일의 (윈도우, 탭) — 중복 열기 방지용. 심링크 해소 + 표준화 경로로 비교.
    func openTab(for url: URL) -> (window: WindowViewModel, tab: DocumentViewModel)? {
        let target = url.resolvingSymlinksInPath().standardizedFileURL.path
        for window in windows {
            if let tab = window.tabs.first(where: { tab in
                guard let fileURL = tab.fileURL else { return false }
                return fileURL.resolvingSymlinksInPath().standardizedFileURL.path == target
            }) {
                return (window, tab)
            }
        }
        return nil
    }

    /// 파일이 이미 열려 있으면 그 윈도우를 앞으로 가져오고 탭을 선택한다. true = 처리됨.
    /// 표준 macOS 문서 동작: 같은 파일을 다시 열면 중복 탭 대신 기존 탭 포커스.
    @discardableResult
    func focusTab(for url: URL) -> Bool {
        guard let found = openTab(for: url) else { return false }
        found.window.selectTab(found.tab.id)
        found.window.nsWindow?.makeKeyAndOrderFront(nil)
        return true
    }
}
