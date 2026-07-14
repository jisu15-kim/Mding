import AppKit

/// 아웃라인 사이드바 항목 클릭 시 프리뷰/에디터를 동시에 해당 헤딩으로 이동시킨다.
/// Split 모드에서는 양쪽 다 이동하며, 비표시 중인 쪽이 이동해도 무해하다(다음에 보일 때 이미 맞는 위치).
@MainActor
enum OutlineNavigator {
    static func jump(to item: OutlineItem, in document: DocumentViewModel) {
        if let webView = PreviewWebViewPool.shared.webView(for: document.id) {
            MarkdownRenderer.scrollToHeading(line: item.line, in: webView)
        }
        jumpEditor(to: item.line, documentID: document.id)
    }

    private static func jumpEditor(to line: Int, documentID: DocumentViewModel.ID) {
        guard let scrollView = EditorViewCache.shared.scrollView(for: documentID),
              let textView = scrollView.documentView as? EditorTextView else { return }

        let nsText = textView.string as NSString
        let offset = lineStartOffset(line, in: nsText)
        let range = NSRange(location: offset, length: 0)
        textView.setSelectedRange(range)
        textView.scrollRangeToVisible(range)
    }

    /// `line`(0-based) 이 시작하는 문자 오프셋. 문서의 실제 라인 수를 넘으면 문서 끝으로 클램프한다.
    private static func lineStartOffset(_ line: Int, in text: NSString) -> Int {
        guard line > 0 else { return 0 }

        let length = text.length
        var offset = 0
        var currentLine = 0
        while offset < length, currentLine < line {
            let lineRange = text.lineRange(for: NSRange(location: offset, length: 0))
            offset = NSMaxRange(lineRange)
            currentLine += 1
        }
        return min(offset, length)
    }
}
