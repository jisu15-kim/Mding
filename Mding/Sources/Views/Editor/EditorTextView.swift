import AppKit

/// 소스 에디터. 서식 액션을 first-responder 셀렉터로 노출한다 (메뉴가 NSApp.sendAction 으로 호출).
final class EditorTextView: NSTextView {
    /// 탭 키 입력 시 삽입할 스페이스 개수.
    var tabIndentWidth = 4

    /// first responder 획득/상실 콜백 (§4.3 Format 메뉴 활성화).
    var onFocusChange: ((Bool) -> Void)?

    /// 사이드바 스와이프 모니터가 스크롤 이벤트를 관찰할 수 있도록 responsive scrolling
    /// (동시 이벤트 트래킹)을 끈다 — 켜져 있으면 이 뷰 위의 스크롤 제스처가 일반 이벤트
    /// 경로를 우회해 로컬 NSEvent 모니터(SwipeRevealMonitor)에 보이지 않는다.
    override class var isCompatibleWithResponsiveScrolling: Bool { false }

    /// md 파일 드롭 콜백(윈도우 전역 드롭 §4.1 확장) — true 반환 시 텍스트 삽입 대신 파일을 연다.
    var onMarkdownFileDrop: (([URL]) -> Bool)?

    override func becomeFirstResponder() -> Bool {
        let didBecome = super.becomeFirstResponder()
        if didBecome { onFocusChange?(true) }
        return didBecome
    }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if didResign { onFocusChange?(false) }
        return didResign
    }

    @objc func toggleBold(_ sender: Any?)          { MarkdownFormat.toggle("**", in: self) }
    @objc func toggleItalic(_ sender: Any?)        { MarkdownFormat.toggle("_",  in: self) }
    @objc func toggleStrikethrough(_ sender: Any?) { MarkdownFormat.toggle("~~", in: self) }
    @objc func toggleInlineCode(_ sender: Any?)    { MarkdownFormat.toggle("`",  in: self) }

    @objc func insertLink(_ sender: Any?) {
        guard isEditable, let window else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Insert Link", comment: "Title of the URL input sheet for inserting a Markdown link")
        alert.informativeText = String(localized: "Enter the destination URL.", comment: "Message of the URL input sheet for inserting a Markdown link")
        alert.addButton(withTitle: String(localized: "Insert", comment: "Confirm button of the insert link sheet"))
        alert.addButton(withTitle: String(localized: "Cancel", comment: "Cancel button of the insert link sheet"))
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "https://"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn else { return }
            MarkdownFormat.insertLink(url: field.stringValue, in: self)
        }
    }

    // 탭 = 스페이스. insertText 경로라 undo/IME 안전.
    override func insertTab(_ sender: Any?) {
        insertText(String(repeating: " ", count: max(1, tabIndentWidth)), replacementRange: selectedRange())
    }

    // 메뉴 항목 자동 enable/disable — 에디터가 편집 가능할 때만 서식 액션 허용.
    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if [#selector(toggleBold(_:)), #selector(toggleItalic(_:)),
            #selector(toggleStrikethrough(_:)), #selector(toggleInlineCode(_:)),
            #selector(insertLink(_:))].contains(item.action) {
            return isEditable
        }
        return super.validateUserInterfaceItem(item)
    }

    // MARK: - md 파일 드롭 (윈도우 전역 드롭 §4.1 확장)
    // NSTextView 는 기본적으로 드래그된 파일 경로를 텍스트로 삽입한다.
    // 마크다운 파일이 섞여 있을 때만 가로채고, 그 외(텍스트 드래그 등)는 기존 동작을 보존한다.

    private func markdownFileURLs(from draggingInfo: NSDraggingInfo) -> [URL]? {
        guard let urls = draggingInfo.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] else { return nil }
        let mdURLs = urls.filter(FileService.isMarkdownFile)
        return mdURLs.isEmpty ? nil : mdURLs
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        markdownFileURLs(from: sender) != nil ? .copy : super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        markdownFileURLs(from: sender) != nil ? .copy : super.draggingUpdated(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let mdURLs = markdownFileURLs(from: sender) {
            return onMarkdownFileDrop?(mdURLs) ?? false
        }
        return super.performDragOperation(sender)
    }
}
