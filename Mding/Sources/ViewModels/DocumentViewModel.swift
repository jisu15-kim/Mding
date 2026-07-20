import AppKit
import Observation

/// 탭 하나 = 파일 하나. 문서 상태와 액션의 중심 ViewModel.
@MainActor @Observable
final class DocumentViewModel: Identifiable {
    /// 탭 콘텐츠 분기: 빈 Welcome 화면 / 실제 에디터. (§4.1)
    enum Mode {
        case welcome
        case editor
    }

    let id = UUID()

    private(set) var mode: Mode = .welcome
    private(set) var fileURL: URL?
    private(set) var text: String = ""
    /// 디바운스(120ms)된 프리뷰 렌더 대상 텍스트 (§4.2).
    private(set) var previewText: String = ""
    /// `previewText` 로부터 파싱한 헤딩 목록(아웃라인 사이드바). `previewText` 가 바뀌는
    /// 모든 지점에서 함께 재계산한다 — 별도로 디바운스하지 않고 그 타이밍에 편승한다.
    private(set) var outline: [OutlineItem] = []
    private(set) var isDirty = false
    var viewMode: ViewMode

    /// 프리뷰 전체 너비(문서별, §전체너비). 켜면 본문 칼럼 상한(980px)을 풀어 창 폭을 쓴다.
    /// 저장된 파일은 경로-키 저장소(`DocumentPrefsStore`)에 영속되고, Untitled 는 메모리로만 유지하다
    /// 저장 시점에 기록한다. 관측 대상이라 `PreviewWebView` 가 변경을 받아 해당 웹뷰에 반영한다.
    var previewFullWidth = false

    /// 외부에서 파일이 바뀌었는데 로컬도 dirty 인 충돌 상태 — View 가 시트를 띄운다.
    var hasExternalChangeConflict = false

    /// 찾기(⌘F) 세션 — 편집기/프리뷰 공용. 뷰(NSTextView/WKWebView)는 소유하지 않고 캐시에서 빌려 검색한다.
    @ObservationIgnored lazy var find = FindSession(document: self)

    /// 프리뷰 마지막 스크롤 비율(0~1). 웹뷰 LRU 풀(§4.2)이 해제 후 복원에 쓴다.
    /// 고빈도 미러링이므로 관찰 대상에서 제외한다.
    @ObservationIgnored var previewScrollRatio: Double = 0

    @ObservationIgnored private var renderTask: Task<Void, Never>?
    @ObservationIgnored private var autosaveTask: Task<Void, Never>?
    @ObservationIgnored private var isWritingSelf = false
    @ObservationIgnored private var fileWatcher: FileWatcher?
    @ObservationIgnored private var resignActiveObserver: (any NSObjectProtocol)?

    init() {
        // @Observable 클래스의 stored property 기본값에서 다른 @MainActor 싱글턴을 참조하기
        // 애매하므로 init 본문에서 할당한다 (§4.6).
        viewMode = AppSettings.shared.defaultViewMode

        // 앱 비활성화 시 즉시 flush (§8.1 트리거 2).
        resignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                _ = self?.flush()
            }
        }
    }

    deinit {
        if let resignActiveObserver {
            NotificationCenter.default.removeObserver(resignActiveObserver)
        }
    }

    var displayName: String {
        if let fileURL { return fileURL.lastPathComponent }
        switch mode {
        case .welcome:
            return String(localized: "Welcome", comment: "Tab title for the empty welcome screen")
        case .editor:
            return String(localized: "Untitled", comment: "Title for a document that has not been saved to disk yet")
        }
    }

    // MARK: - 열기 / 편집

    func load(url: URL) throws {
        let loaded = try FileService.readText(from: url)
        mode = .editor
        fileURL = url
        text = loaded
        previewText = loaded
        outline = OutlineParser.parse(previewText)
        isDirty = false
        previewFullWidth = DocumentPrefsStore.fullWidth(for: url)
        FileService.noteRecentDocument(url)
        startWatchingFile()
    }

    /// `load` + 실패 시 사용자 알럿. Welcome 버튼/드롭/Open Recent/Finder 열기 경로 공용.
    @discardableResult
    func loadPresentingError(url: URL) -> Bool {
        do {
            try load(url: url)
            return true
        } catch {
            NSAlert(error: error).runModal()
            return false
        }
    }

    /// Welcome 탭에서 "New File" 선택 시: 빈 Untitled 에디터로 전환(같은 탭 유지).
    func startBlankDocument() {
        mode = .editor
        fileURL = nil
        text = ""
        previewText = ""
        outline = OutlineParser.parse(previewText)
        isDirty = false
        previewFullWidth = false
        // 빈 문서를 Preview 전용으로 열면 입력할 곳이 없다 — 기본값이 Preview 면 Editor 로 대체.
        if viewMode == .preview {
            viewMode = .editor
        }
    }

    /// 탭이 닫힐 때 웹뷰(풀)와 에디터 뷰(캐시)를 즉시 해제(§4.2).
    func teardownViews() {
        PreviewWebViewPool.shared.release(id)
        EditorViewCache.shared.release(id)
    }

    /// Untitled 이면서 실제로 편집된 내용이 있는지 — 탭 닫기 확인용.
    var hasUnsavedUntitledContent: Bool {
        fileURL == nil && mode == .editor && !text.isEmpty
    }

    /// 프리뷰 전체 너비 토글(문서별, §전체너비). 저장된 파일이면 경로-키 저장소에 영속하고,
    /// Untitled 면 메모리로만 유지하다 `saveDocument` 가 경로를 확보할 때 기록한다.
    func togglePreviewFullWidth() {
        previewFullWidth.toggle()
        if let fileURL {
            DocumentPrefsStore.setFullWidth(previewFullWidth, for: fileURL)
        }
    }

    /// 에디터 textDidChange 진입점.
    func updateText(_ newText: String) {
        guard newText != text else { return }
        text = newText
        isDirty = true
        scheduleRender()
        scheduleAutosave()
    }

    private func scheduleRender() {
        renderTask?.cancel()
        renderTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, let self else { return }
            self.previewText = self.text
            self.outline = OutlineParser.parse(self.previewText)
        }
    }

    // MARK: - 저장 (Xcode 식 autosave-in-place, §8.1)

    private func scheduleAutosave() {
        guard fileURL != nil else { return }          // Untitled 제외
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// 즉시 저장. 종료/전환/비활성화 시 호출.
    @discardableResult
    func flush() -> Bool {
        guard let url = fileURL, isDirty else { return true }
        do {
            isWritingSelf = true
            try Data(text.utf8).write(to: url, options: .atomic)
            isDirty = false
            isWritingSelf = false
            return true
        } catch {
            isWritingSelf = false
            return false
        }
    }

    /// ⌘S. Untitled 면 Save Panel 로 경로를 받는다.
    func saveDocument() {
        if fileURL == nil {
            guard let url = FileService.presentSavePanel(suggestedName: displayName + ".md") else { return }
            fileURL = url
            isDirty = true
            _ = flush()
            // Untitled 동안 켜둔 전체 너비 설정을 이제 경로가 생겼으니 영속화한다(§전체너비).
            DocumentPrefsStore.setFullWidth(previewFullWidth, for: url)
            FileService.noteRecentDocument(url)
            startWatchingFile()
        } else {
            _ = flush()
        }
    }

    // MARK: - 외부 변경 감시 (§8.1)

    private func startWatchingFile() {
        fileWatcher?.stop()
        fileWatcher = nil
        guard let url = fileURL else { return }
        let watcher = FileWatcher(url: url) {
            Task { @MainActor [weak self] in
                self?.handleExternalChange()
            }
        }
        fileWatcher = watcher
        watcher.start()
    }

    private func handleExternalChange() {
        guard !isWritingSelf, let url = fileURL else { return }
        guard let diskText = try? FileService.readText(from: url) else { return }
        // 자기 쓰기의 메아리(디스크 == 로컬)는 무시.
        guard diskText != text else { return }

        if isDirty {
            hasExternalChangeConflict = true
        } else {
            text = diskText
            previewText = diskText
            outline = OutlineParser.parse(previewText)
        }
    }

    /// 충돌 시트: 내 편집 유지 (다음 자동저장 때 디스크를 덮어쓰게 됨).
    func resolveConflictKeepingMine() {
        hasExternalChangeConflict = false
    }

    /// 충돌 시트: 지금 즉시 로컬 내용으로 디스크 덮어쓰기.
    func resolveConflictOverwriting() {
        hasExternalChangeConflict = false
        _ = flush()
    }

    /// 충돌 시트: 로컬 편집을 버리고 디스크 내용으로 리로드.
    func resolveConflictReloading() {
        hasExternalChangeConflict = false
        autosaveTask?.cancel()
        guard let url = fileURL, let diskText = try? FileService.readText(from: url) else { return }
        text = diskText
        previewText = diskText
        outline = OutlineParser.parse(previewText)
        isDirty = false
    }

    // MARK: - 경로 복사 / Finder (§4.5)

    /// 절대 경로를 클립보드에 복사. 미저장(Untitled) 문서는 no-op.
    func copyAbsolutePath() {
        guard let fileURL else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(fileURL.path, forType: .string)
    }

    /// 상대 경로를 클립보드에 복사. base 는 설정(§4.6)의 `relativePathBase` 를 따른다.
    /// 미저장(Untitled) 문서는 no-op.
    func copyRelativePath() {
        guard let fileURL else { return }
        let base = relativePathBase(for: fileURL)
        let relative = PathService.relativePath(of: fileURL, from: base)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(relative, forType: .string)
    }

    /// §4.6 설정에 따른 상대 경로 기준 디렉터리. 항상 Home 으로 폴백한다.
    private func relativePathBase(for fileURL: URL) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch AppSettings.shared.relativePathBase {
        case .gitRoot:
            return PathService.gitRoot(for: fileURL) ?? home
        case .home:
            return home
        case .custom:
            let custom = AppSettings.shared.customRelativeBasePath
            guard !custom.isEmpty else { return home }
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: custom, isDirectory: &isDirectory)
            return (exists && isDirectory.boolValue) ? URL(fileURLWithPath: custom) : home
        }
    }

    /// Finder 에서 파일 선택 표시. 미저장(Untitled) 문서는 no-op.
    func revealInFinder() {
        guard let fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }
}
