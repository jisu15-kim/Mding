import AppKit

/// 마크다운 서식 스마트 토글. TechSpec §6.2 의 검증된 로직을 그대로 이식 — 재작성 금지.
/// 반드시 `shouldChangeText`/`didChangeText` 경로 사용 (undo 1회 복원 + IME 안전).
@MainActor
enum MarkdownFormat {
    /// 선택 영역을 marker 로 감싸거나 이미 감싸져 있으면 해제.
    static func toggle(_ marker: String, in tv: NSTextView) {
        guard let storage = tv.textStorage else { return }
        let full = storage.string as NSString
        let sel = tv.selectedRange()
        let m = marker as NSString, mLen = m.length

        tv.undoManager?.beginUndoGrouping()
        defer { tv.undoManager?.endUndoGrouping() }

        // 1) 선택 없음 → 마커 쌍 삽입 후 커서 가운데
        if sel.length == 0 {
            let ins = marker + marker
            if tv.shouldChangeText(in: sel, replacementString: ins) {
                storage.replaceCharacters(in: sel, with: ins)
                tv.didChangeText()
                tv.setSelectedRange(NSRange(location: sel.location + mLen, length: 0))
            }
            return
        }

        // 2) 선택 '바깥'이 이미 마커로 감싸져 있으면 언랩
        let canOutside = sel.location >= mLen && sel.location + sel.length + mLen <= full.length
        if canOutside,
           m.isEqual(to: full.substring(with: NSRange(location: sel.location - mLen, length: mLen))),
           m.isEqual(to: full.substring(with: NSRange(location: sel.location + sel.length, length: mLen))) {
            let outer = NSRange(location: sel.location - mLen, length: sel.length + 2 * mLen)
            let inner = full.substring(with: sel)
            if tv.shouldChangeText(in: outer, replacementString: inner) {
                storage.replaceCharacters(in: outer, with: inner)
                tv.didChangeText()
                tv.setSelectedRange(NSRange(location: sel.location - mLen, length: (inner as NSString).length))
            }
            return
        }

        // 3) 선택 텍스트 자체가 마커로 감싸져 있으면 언랩
        let selText = full.substring(with: sel) as NSString
        if selText.length >= 2 * mLen, selText.hasPrefix(marker), selText.hasSuffix(marker) {
            let stripped = selText.substring(with: NSRange(location: mLen, length: selText.length - 2 * mLen))
            if tv.shouldChangeText(in: sel, replacementString: stripped) {
                storage.replaceCharacters(in: sel, with: stripped)
                tv.didChangeText()
                tv.setSelectedRange(NSRange(location: sel.location, length: (stripped as NSString).length))
            }
            return
        }

        // 4) 기본 → 감싸기
        let wrapped = marker + (selText as String) + marker
        if tv.shouldChangeText(in: sel, replacementString: wrapped) {
            storage.replaceCharacters(in: sel, with: wrapped)
            tv.didChangeText()
            tv.setSelectedRange(NSRange(location: sel.location + mLen, length: selText.length))
        }
    }

    /// 선택 텍스트를 `[선택](url)` 링크로 치환. 선택이 없으면 `[](url)` 삽입 후 커서를 라벨 위치로.
    static func insertLink(url: String, in tv: NSTextView) {
        guard let storage = tv.textStorage else { return }
        let full = storage.string as NSString
        let sel = tv.selectedRange()
        let label = full.substring(with: sel)
        let replacement = "[\(label)](\(url))"

        tv.undoManager?.beginUndoGrouping()
        defer { tv.undoManager?.endUndoGrouping() }

        if tv.shouldChangeText(in: sel, replacementString: replacement) {
            storage.replaceCharacters(in: sel, with: replacement)
            tv.didChangeText()
            if label.isEmpty {
                tv.setSelectedRange(NSRange(location: sel.location + 1, length: 0))
            } else {
                tv.setSelectedRange(
                    NSRange(location: sel.location + (replacement as NSString).length, length: 0)
                )
            }
        }
    }
}
