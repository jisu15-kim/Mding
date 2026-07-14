import AppKit
import UniformTypeIdentifiers

/// 파일 열기/읽기 유틸. 무상태.
enum FileService {
    static let markdownType = UTType(importedAs: "net.daringfireball.markdown")

    /// 마크다운 파일 선택 패널을 띄우고 선택된 URL 을 반환한다(취소 시 nil).
    @MainActor
    static func presentOpenPanel() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [markdownType, .plainText]
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Untitled 문서 첫 저장용 Save Panel.
    @MainActor
    static func presentSavePanel(suggestedName: String) -> URL? {
        presentSavePanel(suggestedName: suggestedName, allowedType: markdownType)
    }

    /// 타입을 지정할 수 있는 Save Panel (예: PDF/HTML 내보내기, §4.6 확장).
    @MainActor
    static func presentSavePanel(suggestedName: String, allowedType: UTType) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [allowedType]
        panel.nameFieldStringValue = suggestedName
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func readText(from url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    /// 마크다운 확장자(대소문자 무시) 여부 — 윈도우/에디터/프리뷰 드래그&드롭 필터용 (§4.9 문서 타입 목록과 일치).
    static func isMarkdownFile(_ url: URL) -> Bool {
        ["md", "markdown", "mdown"].contains(url.pathExtension.lowercased())
    }

    /// File > Open Recent 목록에 반영.
    @MainActor
    static func noteRecentDocument(_ url: URL) {
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
    }
}
