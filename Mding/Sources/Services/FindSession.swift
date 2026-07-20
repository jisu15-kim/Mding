import AppKit
import Observation
import WebKit

/// 문서 하나의 찾기(⌘F) 세션 — 편집기와 프리뷰를 하나의 찾기 바로 아우른다.
///
/// 대상(target)은 뷰 모드가 결정한다: Preview 모드면 프리뷰 웹뷰, Editor/Split 모드면 소스 에디터.
/// 실제 뷰는 `EditorViewCache`(NSTextView) / `PreviewWebViewPool`(WKWebView)에서 문서 id 로 빌려온다 —
/// 찾기 세션은 뷰를 소유하지 않고 검색만 구동한다.
///
/// - 편집기: `NSLayoutManager` 임시 속성(temporary attribute)으로 매치를 하이라이트한다.
///   임시 속성은 표시 전용이라 텍스트 저장소/undo/디스크 저장에 영향을 주지 않는다.
/// - 프리뷰: preview.html 의 `window.mdFind` 브리지(CSS Custom Highlight API)를 호출한다 — DOM 을
///   바꾸지 않아 재렌더·스크롤 동기화와 간섭하지 않는다.
@MainActor
@Observable
final class FindSession {
    enum Target { case editor, preview }

    /// 찾기 바 표시 여부. `SplitEditorView` 가 이 값으로 바를 마운트한다.
    var isPresented = false
    /// 검색어. 찾기 바 TextField 가 바인딩한다.
    var query = ""
    /// 대소문자 구분. 기본 끔(macOS 관례).
    var caseSensitive = false

    /// 전체 매치 수.
    private(set) var matchCount = 0
    /// 현재 매치 순번(1-based). 매치 없으면 0.
    private(set) var currentIndex = 0
    /// 찾기 바 입력란 재포커스 요청 신호(⌘F 재입력 시 증가) — 뷰가 관찰해 포커스를 되돌린다.
    private(set) var focusRequest = 0

    private let documentID: UUID
    private weak var document: DocumentViewModel?

    @ObservationIgnored private var searchTask: Task<Void, Never>?
    /// 편집기 매치 범위 캐시(next/prev 이동용).
    @ObservationIgnored private var editorMatches: [NSRange] = []
    /// 편집기 현재 매치 인덱스(0-based). 매치 없으면 -1.
    @ObservationIgnored private var editorCurrent = -1

    init(document: DocumentViewModel) {
        self.document = document
        self.documentID = document.id
    }

    // MARK: - 대상 뷰

    /// Split 모드에서 마지막으로 확정(latch)된 검색 대상. 찾기를 열 때(⌘F) 직전 포커스로 정한다.
    @ObservationIgnored private var latchedSplitTarget: Target = .editor

    private var target: Target {
        switch document?.viewMode ?? .editor {
        case .preview: return .preview
        case .editor: return .editor
        // Split 은 포커스 따라가기 — 찾기를 열던 순간의 pane 을 유지한다.
        case .split: return latchedSplitTarget
        }
    }

    /// Split 모드 한정: 현재 first responder 로 검색 대상을 정한다.
    /// 프리뷰 웹뷰의 하위 뷰(WKContentView)가 first responder 면 프리뷰, 그 외(에디터/그 밖)면 에디터.
    /// ⌘F 액션은 찾기 입력란이 포커스를 가져가기 "전"에 실행되므로 이 시점의 응답자가 직전 pane 이다.
    private func latchSplitTargetFromFocus() {
        guard (document?.viewMode ?? .editor) == .split else { return }
        if let webView = previewWebView,
           let responder = webView.window?.firstResponder as? NSView,
           responder.isDescendant(of: webView) {
            latchedSplitTarget = .preview
        } else {
            latchedSplitTarget = .editor
        }
    }

    private var editorTextView: EditorTextView? {
        EditorViewCache.shared.scrollView(for: documentID)?.documentView as? EditorTextView
    }

    private var previewWebView: WKWebView? {
        PreviewWebViewPool.shared.webView(for: documentID)
    }

    // MARK: - 활성화 / 종료

    /// ⌘F. 바를 열고(이미 열려 있으면 입력란만 재포커스) 현재 검색어로 재검색한다.
    /// Split 모드면 직전 포커스로 검색 대상(에디터/프리뷰)을 정한다.
    func activate() {
        latchSplitTargetFromFocus()
        isPresented = true
        focusRequest += 1
        if !query.isEmpty { runSearch(resetToFirst: true) }
    }

    /// Escape / 닫기 버튼. 바를 닫고 양쪽 하이라이트를 모두 지운다(검색어는 보존).
    func deactivate() {
        isPresented = false
        clearHighlights()
        matchCount = 0
        currentIndex = 0
        editorMatches = []
        editorCurrent = -1
    }

    /// ⌘E — 에디터 선택 텍스트를 검색어로 가져와 찾기를 연다. 에디터 선택 기반이므로 대상은 에디터로 고정.
    func useSelection() {
        latchedSplitTarget = .editor
        if let textView = editorTextView {
            let selection = textView.selectedRange()
            if selection.length > 0 {
                query = (textView.string as NSString).substring(with: selection)
            }
        }
        isPresented = true
        focusRequest += 1
        runSearch(resetToFirst: true)
    }

    // MARK: - 변경 반응

    /// 검색어 변경(타이핑) — 짧게 디바운스 후 첫 매치부터 재검색.
    func queryDidChange() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled else { return }
            self?.runSearch(resetToFirst: true)
        }
    }

    /// 대소문자 토글 — 즉시 재검색.
    func caseSensitiveDidChange() {
        runSearch(resetToFirst: true)
    }

    /// 뷰 모드 전환 — 대상이 바뀔 수 있으니 양쪽을 지우고 새 대상에서 다시 검색.
    func modeDidChange() {
        guard isPresented else { return }
        runSearch(resetToFirst: true)
    }

    /// 편집기 텍스트 변경 — 편집기가 보이면(에디터/Split) 하이라이트를 갱신한다.
    /// 프리뷰 쪽은 재렌더가 별도로 `previewDidRerender` 를 부르므로 여기서 건드리지 않는다(깜빡임 방지).
    func editorTextDidChange() {
        guard isPresented, !query.isEmpty, (document?.viewMode ?? .editor) != .preview else { return }
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, let self else { return }
            self.searchEditor(active: self.target == .editor, resetToFirst: false)
        }
    }

    /// 프리뷰 재렌더 직후 — 프리뷰가 보이면(프리뷰/Split) 하이라이트를 다시 적용한다(CSS 하이라이트는 재렌더로 사라진다).
    func previewDidRerender() {
        guard isPresented, !query.isEmpty, (document?.viewMode ?? .editor) != .editor else { return }
        searchPreview(active: target == .preview)
    }

    // MARK: - 이동

    func next() { step(1) }
    func previous() { step(-1) }

    private func step(_ delta: Int) {
        guard isPresented, matchCount > 0 else { return }
        // 이동/카운트는 활성 pane(Split 은 latch, 그 외는 유일한 pane)만 담당한다.
        switch target {
        case .editor:
            guard !editorMatches.isEmpty, let textView = editorTextView else { return }
            editorCurrent = (editorCurrent + delta + editorMatches.count) % editorMatches.count
            applyEditorHighlights(in: textView, emphasizeCurrent: true, scroll: true)
            currentIndex = editorCurrent + 1
        case .preview:
            previewWebView?.evaluateJavaScript("window.mdFindStep(\(delta))") { [weak self] result, _ in
                self?.applyPreviewResult(result)
            }
        }
    }

    // MARK: - 검색 실행

    /// 보이는 pane 을 모두 하이라이트한다. Split 은 양쪽 다 노란 매치, 활성 pane 만 현재(주황)+스크롤+카운트.
    private func runSearch(resetToFirst: Bool) {
        clearHighlights()
        guard isPresented, !query.isEmpty else {
            matchCount = 0
            currentIndex = 0
            editorMatches = []
            editorCurrent = -1
            return
        }
        let mode = document?.viewMode ?? .editor
        let active = target
        if mode != .preview {
            searchEditor(active: active == .editor, resetToFirst: resetToFirst)
        }
        if mode != .editor {
            searchPreview(active: active == .preview)
        }
    }

    /// - Parameter active: 이 pane 이 이동/카운트/현재(주황) 강조를 담당하는지. false 면 노란 매치만 칠한다.
    private func searchEditor(active: Bool, resetToFirst: Bool) {
        guard let textView = editorTextView else {
            editorMatches = []
            editorCurrent = -1
            if active { matchCount = 0; currentIndex = 0 }
            return
        }
        let haystack = textView.string as NSString
        let options: NSString.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        var matches: [NSRange] = []
        var searchStart = 0
        while searchStart < haystack.length {
            let found = haystack.range(
                of: query,
                options: options,
                range: NSRange(location: searchStart, length: haystack.length - searchStart)
            )
            if found.location == NSNotFound { break }
            matches.append(found)
            searchStart = found.location + max(found.length, 1)
        }

        editorMatches = matches

        guard !matches.isEmpty else {
            editorCurrent = -1
            applyEditorHighlights(in: textView, emphasizeCurrent: active, scroll: false)
            if active { matchCount = 0; currentIndex = 0 }
            return
        }

        if active {
            if resetToFirst || editorCurrent < 0 {
                // 커서 위치 이후 첫 매치부터 시작(제자리에서 자연스럽게 찾기 시작).
                let caret = textView.selectedRange().location
                editorCurrent = matches.firstIndex(where: { $0.location >= caret }) ?? 0
            } else {
                editorCurrent = min(editorCurrent, matches.count - 1)
            }
        }

        applyEditorHighlights(in: textView, emphasizeCurrent: active, scroll: active)
        if active {
            matchCount = matches.count
            currentIndex = editorCurrent + 1
        }
    }

    private func applyEditorHighlights(in textView: EditorTextView, emphasizeCurrent: Bool, scroll: Bool) {
        guard let layoutManager = textView.layoutManager else { return }
        let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
        for (index, range) in editorMatches.enumerated() {
            let color = (emphasizeCurrent && index == editorCurrent) ? Self.currentMatchColor : Self.matchColor
            layoutManager.addTemporaryAttribute(.backgroundColor, value: color, forCharacterRange: range)
        }
        if scroll, emphasizeCurrent, editorMatches.indices.contains(editorCurrent) {
            textView.scrollRangeToVisible(editorMatches[editorCurrent])
        }
    }

    /// - Parameter active: 이 pane 이 현재(주황)+스크롤+카운트를 담당하는지. false 면 노란 매치만 칠하고 카운트는 건드리지 않는다.
    private func searchPreview(active: Bool) {
        guard let webView = previewWebView else {
            if active { matchCount = 0; currentIndex = 0 }
            return
        }
        let js = "window.mdFind(\(Self.jsStringLiteral(query)), \(caseSensitive), \(active))"
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            guard let self, active else { return }
            self.applyPreviewResult(result)
        }
    }

    private func applyPreviewResult(_ result: Any?) {
        guard let dict = result as? [String: Any] else {
            matchCount = 0
            currentIndex = 0
            return
        }
        matchCount = (dict["count"] as? Int) ?? 0
        currentIndex = (dict["index"] as? Int) ?? 0
    }

    private func clearHighlights() {
        if let textView = editorTextView, let layoutManager = textView.layoutManager {
            let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
            layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: fullRange)
        }
        previewWebView?.evaluateJavaScript("window.mdFindClear && window.mdFindClear()")
    }

    // MARK: - 상수 / 유틸

    private static let matchColor = NSColor.systemYellow.withAlphaComponent(0.35)
    private static let currentMatchColor = NSColor.systemOrange.withAlphaComponent(0.7)

    /// Swift 문자열을 JS 문자열 리터럴(따옴표 포함, 안전 이스케이프)로 변환한다.
    private static func jsStringLiteral(_ string: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [string]),
              var encoded = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        // JSONSerialization 은 배열만 최상위로 허용 → ["..."] 에서 대괄호를 벗겨 문자열 리터럴만 남긴다.
        encoded.removeFirst()
        encoded.removeLast()
        return encoded
    }
}
