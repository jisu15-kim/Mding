import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// 윈도우가 아직 준비되기 전(런치 중 Finder 열기)에 도착한 URL 버퍼.
    private var pendingURLs: [URL] = []
    private var tabNavigationKeyMonitor: Any?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // 탭은 WindowViewModel 이 커스텀으로 관리한다 — 시스템 윈도우 탭 비활성화.
        NSWindow.allowsAutomaticWindowTabbing = false
        // 저장된 테마를 앱 전역 appearance 로 반영 (§4.6). 이후 변경은 ThemeManager.apply 가 담당.
        NSApp.appearance = AppSettings.shared.theme.nsAppearance
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // ⌘⌥←/→ = 이전/다음 탭 (Safari 관례의 보조 단축키 — ⌃Tab/⌘1…9 메뉴 항목과 병행).
        // 메뉴 대신 이벤트 모니터인 이유: SwiftUI Button 은 key equivalent 를 하나만 가질 수 있어
        // 기존 ⌃Tab 항목에 얹을 수 없고, 같은 동작의 메뉴 항목을 중복 노출하지 않기 위해.
        tabNavigationKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // NSEvent 는 Sendable 이 아니라 assumeIsolated 밖에서 원시값만 뽑아 넘긴다.
            let keyCode = event.keyCode
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let handled = MainActor.assumeIsolated {
                Self.handleTabNavigationKey(keyCode: keyCode, modifiers: modifiers)
            }
            return handled ? nil : event
        }
    }

    /// ⌘⌥←/→ 처리. key window 가 문서 윈도우일 때만 소비(true)하고, 그 외에는 통과시킨다.
    private static func handleTabNavigationKey(
        keyCode: UInt16, modifiers: NSEvent.ModifierFlags
    ) -> Bool {
        guard modifiers == [.command, .option],
              let window = WindowRegistry.shared.activeWindow,
              window.nsWindow === NSApp.keyWindow
        else { return false }

        switch keyCode {
        case 123:  // ←
            window.selectPreviousTab()
            return true
        case 124:  // →
            window.selectNextTab()
            return true
        default:
            return false
        }
    }

    deinit {
        if let tabNavigationKeyMonitor {
            NSEvent.removeMonitor(tabNavigationKeyMonitor)
        }
    }

    // Finder 더블클릭 / 드래그 열기 (§4.1). 활성 윈도우의 탭으로 라우팅.
    func application(_ application: NSApplication, open urls: [URL]) {
        pendingURLs.append(contentsOf: urls)
        flushPendingOpens()
    }

    /// 활성 윈도우가 준비될 때까지 main 큐에서 재시도하며 버퍼를 비운다.
    private func flushPendingOpens(attempt: Int = 0) {
        guard !pendingURLs.isEmpty else { return }
        if let window = WindowRegistry.shared.activeWindow {
            let urls = pendingURLs
            pendingURLs.removeAll()
            for url in urls {
                window.openFile(url: url)
            }
        } else if attempt < 20 {
            // 콜드 런치 시 WindowRootView.onAppear 등록까지 시간이 걸릴 수 있어 간격을 두고 재시도.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.flushPendingOpens(attempt: attempt + 1)
            }
        } else {
            pendingURLs.removeAll()  // 윈도우가 끝내 없으면 포기(방어적).
        }
    }

    // 종료 시 미저장 유실 방지 (§8.1). fileURL 있는 dirty 문서는 조용히 flush.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        for document in WindowRegistry.shared.allTabs where document.fileURL != nil && document.isDirty {
            _ = document.flush()
        }
        // Untitled dirty 문서의 저장 확인은 탭/윈도우 닫기 흐름에서 처리(§4.1). Quit 시엔 v1 범위 밖.
        return .terminateNow
    }
}
