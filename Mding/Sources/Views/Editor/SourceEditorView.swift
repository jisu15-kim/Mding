import SwiftUI
import AppKit

/// EditorTextView(NSTextView 서브클래스)를 호스팅하는 소스 에디터.
/// SwiftUI TextEditor 금지(한글 IME) — TechSpec §6.1.
/// 뷰 인스턴스는 `EditorViewCache` 가 탭 수명 동안 유지 — 탭 전환에도 undo/선택/스크롤 보존.
struct SourceEditorView: NSViewRepresentable {
    let document: DocumentViewModel
    /// 에디터 first-responder 획득/상실 콜백 (§4.3 Format 메뉴 활성화).
    var onFocusChange: ((Bool) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(document: document) }

    /// 에디터에 드롭된 md 파일을 문서가 속한 윈도우에서 연다(윈도우 전역 드롭 §4.1 확장).
    private var markdownFileDropHandler: ([URL]) -> Bool {
        { urls in
            guard let window = WindowRegistry.shared.window(containing: document.id) else { return false }
            for url in urls { window.openFile(url: url) }
            return true
        }
    }

    func makeNSView(context: Context) -> NSScrollView {
        // 탭 복귀: 캐시된 뷰 재사용. 죽은 코디네이터만 새로 배선한다.
        if let cached = EditorViewCache.shared.scrollView(for: document.id) {
            if let textView = cached.documentView as? EditorTextView {
                textView.delegate = context.coordinator
                textView.onFocusChange = onFocusChange
                textView.onMarkdownFileDrop = markdownFileDropHandler
            }
            return cached
        }

        let scrollView = EditorTextView.scrollableTextView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        // 크롬 통합 배경(WindowRootView)이 그대로 비치게 — 자체 배경을 그리지 않는다.
        scrollView.drawsBackground = false
        // 소프트랩이라 가로 스크롤 대상이 없는데도 가로 제스처에 출렁이는(elastic bounce) 것 방지 —
        // 사이드바 스와이프가 에디터를 흔들지 않게 한다.
        scrollView.horizontalScrollElasticity = .none

        guard let textView = scrollView.documentView as? EditorTextView else {
            assertionFailure("scrollableTextView() must host EditorTextView")
            return scrollView
        }
        textView.drawsBackground = false
        textView.delegate = context.coordinator
        textView.onFocusChange = onFocusChange
        textView.onMarkdownFileDrop = markdownFileDropHandler
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = .monospacedSystemFont(ofSize: AppSettings.shared.editorFontSize, weight: .regular)
        textView.tabIndentWidth = AppSettings.shared.tabIndentWidth
        // 행간을 폰트 자연 행간(~1.2)보다 넓혀 가독성 확보(VS Code 에디터 수준).
        // 절대값(lineSpacing)이 아니라 배율이라 폰트 크기 설정 변경에도 그대로 따라간다.
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineHeightMultiple = 1.35
        textView.defaultParagraphStyle = paragraphStyle
        textView.typingAttributes[.paragraphStyle] = paragraphStyle
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.string = document.text

        EditorViewCache.shared.store(scrollView, for: document.id)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.document = document
        guard let textView = scrollView.documentView as? EditorTextView else { return }
        textView.onFocusChange = onFocusChange
        textView.onMarkdownFileDrop = markdownFileDropHandler

        // 설정(§4.6) 반영 — 달라졌을 때만 set(불필요한 NSFont 재할당 방지).
        let fontSize = AppSettings.shared.editorFontSize
        if textView.font?.pointSize != CGFloat(fontSize) {
            textView.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        }
        let tabIndentWidth = AppSettings.shared.tabIndentWidth
        if textView.tabIndentWidth != tabIndentWidth {
            textView.tabIndentWidth = tabIndentWidth
        }

        // IME 조합 중에는 외부 갱신 금지. 에디터 자신의 편집은 문자열 비교로 무시된다.
        if textView.string != document.text, !textView.hasMarkedText() {
            let selection = textView.selectedRange()
            textView.string = document.text
            let length = (document.text as NSString).length
            textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var document: DocumentViewModel

        init(document: DocumentViewModel) {
            self.document = document
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            document.updateText(textView.string)
        }
    }
}
