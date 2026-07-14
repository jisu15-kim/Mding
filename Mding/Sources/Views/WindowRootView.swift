import SwiftUI

/// 한 윈도우의 루트 뷰: 커스텀 탭 바 + 콘텐츠 스택(welcome/editor 분기) (§4.1).
/// 각 윈도우는 자신의 `WindowViewModel` 을 소유하고 `WindowRegistry` 에 등록한다.
struct WindowRootView: View {
    @State private var window = WindowViewModel()

    var body: some View {
        // 사이드바 = 창 전체 높이 기둥(시스템 머티리얼, 신호등 아래) + detail = 탭바/콘텐츠.
        // 접기/펼치기 토글 버튼은 NavigationSplitView 가 자동 제공한다.
        NavigationSplitView(columnVisibility: outlineVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 320)
        } detail: {
            VStack(spacing: 0) {
                TabBarView(window: window)
                content
            }
            .navigationTitle(window.selectedTab?.displayName ?? "Mding")
            .toolbar {
                // 크롬 높이 통일: 툴바 구성이 탭 종류(Welcome/에디터)와 무관하게 항상 같아야
                // 타이틀바 높이가 튀지 않는다 — Welcome 탭에서는 표시만 하고 비활성 처리.
                ToolbarItem {
                    viewModePicker
                }
                ToolbarItem {
                    pathMenu
                }
            }
        }
        .frame(minWidth: 560, minHeight: 360)
        // 윈도우 어디든 md 파일 드롭 시 열기(§4.1 확장). WelcomeView 자체 dropDestination 이
        // Welcome 영역 드롭은 먼저 가로채므로(동일 동작) 여기선 나머지 영역만 처리된다.
        .dropDestination(for: URL.self) { urls, _ in
            let mdURLs = urls.filter(FileService.isMarkdownFile)
            guard !mdURLs.isEmpty else { return false }
            for url in mdURLs { window.openFile(url: url) }
            return true
        }
        .background(WindowAccessor { window.attach(window: $0) })
        // 두손가락 가로 스와이프로 아웃라인 토글(§ 아웃라인 사이드바) — 스크롤 이벤트를 관찰만 한다.
        .background(SwipeRevealMonitor())
        // Bear 스타일 크롬 통합: 툴바/탭바/콘텐츠를 하나의 배경으로 잇는다(밴드·구분선 제거).
        // 창 배경은 preview.html 문서 배경과 동일한 dynamic color 라 프리뷰 웹뷰와 시임이 없다.
        // 사이드바 칼럼만 시스템 머티리얼로 미묘하게 구분된다(레퍼런스 UI와 동일).
        .containerBackground(Color(nsColor: AppColors.contentBackground), for: .window)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .focusedSceneValue(\.activeWindow, window)
        .focusedSceneValue(\.activeDocument, window.selectedTab)
        .onAppear {
            WindowRegistry.shared.register(window)
        }
        .onDisappear {
            WindowRegistry.shared.unregister(window.id)
        }
    }

    /// 사이드바 칼럼 내용. 탭이 없으면 빈 화면(통합 배경 투과).
    @ViewBuilder
    private var sidebar: some View {
        if let tab = window.selectedTab {
            OutlineSidebarView(document: tab)
        } else {
            Color.clear
        }
    }

    /// `AppSettings.showOutline`(영속, ⌃⌘S·스와이프·시스템 토글 버튼 공용) ↔ 칼럼 가시성 변환.
    private var outlineVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { AppSettings.shared.showOutline ? .all : .detailOnly },
            set: { AppSettings.shared.showOutline = ($0 != .detailOnly) }
        )
    }

    @ViewBuilder
    private var content: some View {
        if let tab = window.selectedTab {
            switch tab.mode {
            case .welcome:
                WelcomeView(document: tab)
                    .id(tab.id)
            case .editor:
                // 탭마다 독립 에디터/프리뷰 — 웹뷰 LRU 풀(§4.2)의 마운트/해제 단위가 된다.
                SplitEditorView(document: tab)
                    .id(tab.id)
            }
        } else {
            Color.clear  // 통합 창 배경(containerBackground)이 그대로 보인다.
        }
    }

    /// 뷰 모드 토글. Welcome 탭에서도 항상 표시(비활성)해 크롬 높이를 탭 종류와 무관하게 유지한다.
    @ViewBuilder
    private var viewModePicker: some View {
        if let tab = window.selectedTab, tab.mode == .editor {
            @Bindable var document = tab
            Picker(selection: $document.viewMode) {
                ForEach(ViewMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            } label: {
                Text("View Mode", comment: "Toolbar picker that switches between editor, split, and preview")
            }
            .pickerStyle(.segmented)
        } else {
            Picker(selection: .constant(ViewMode.preview)) {
                ForEach(ViewMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            } label: {
                Text("View Mode", comment: "Toolbar picker that switches between editor, split, and preview")
            }
            .pickerStyle(.segmented)
            .disabled(true)
        }
    }

    /// 경로 복사 / Finder 드롭다운 (SplitEditorView 에서 승격 — 크롬 높이 통일).
    /// 툴바 아이템은 macOS 26 에서 자동 glass 처리된다(§4.5) — 별도 glassEffect 불필요.
    private var pathMenu: some View {
        let document = window.selectedTab
        return Menu {
            Button {
                document?.copyAbsolutePath()
            } label: {
                Text("Copy Path (⌘⌥C)", comment: "Toolbar menu item that copies the file's absolute path, with its keyboard shortcut shown")
            }
            .disabled(document?.fileURL == nil)

            Button {
                document?.copyRelativePath()
            } label: {
                Text("Copy Relative Path (⌘⌥⇧C)", comment: "Toolbar menu item that copies the file's relative path, with its keyboard shortcut shown")
            }
            .disabled(document?.fileURL == nil)

            Divider()

            Button {
                document?.revealInFinder()
            } label: {
                Text("Open in Finder", comment: "Toolbar menu item that reveals the file in Finder")
            }
            .disabled(document?.fileURL == nil)
        } label: {
            Image(systemName: "document.on.clipboard")
        }
        .disabled(document == nil || document?.mode != .editor)
    }
}

/// SwiftUI WindowGroup 의 NSWindow 를 캡처해 콜백으로 넘긴다(§4.1 close 훅·활성화 추적용).
private struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            if let window = view?.window { onWindow(window) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in
            if let window = nsView?.window { onWindow(window) }
        }
    }
}

extension FocusedValues {
    /// 현재 key window 의 활성 문서. 메뉴 커맨드가 이 값으로 라우팅한다.
    @Entry var activeDocument: DocumentViewModel?
    /// 현재 key window 의 WindowViewModel. 탭/파일 메뉴 커맨드가 사용한다.
    @Entry var activeWindow: WindowViewModel?
    /// 소스 에디터가 first responder 인지 — Format 메뉴 활성/비활성 판단.
    @Entry var editorHasFocus: Bool?
}
