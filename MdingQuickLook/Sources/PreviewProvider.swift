import CoreGraphics
import Foundation
import UniformTypeIdentifiers
#if canImport(QuickLook)
import QuickLook
#endif
#if canImport(QuickLookUI)
import QuickLookUI
#endif

/// Finder 스페이스바 Quick Look 진입점 (Info.plist NSExtensionPrincipalClass).
/// data-based 프리뷰: 변환을 마친 정적 HTML 을 반환하며 QL 쪽에서는 JS 실행 없이 그대로 렌더한다.
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let fileURL = request.fileURL
        return QLPreviewReply(
            dataOfContentType: .html,
            contentSize: CGSize(width: 800, height: 900)
        ) { reply in
            reply.stringEncoding = .utf8
            let markdown = try Self.readText(from: fileURL)
            let renderer = try MarkdownHTMLRenderer(bundle: .main)
            return Data(try renderer.renderDocument(markdown).utf8)
        }
    }

    /// UTF-8 우선, 실패 시 인코딩 자동 감지 폴백.
    private static func readText(from url: URL) throws -> String {
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
            return utf8
        }
        var encoding = String.Encoding.utf8
        return try String(contentsOf: url, usedEncoding: &encoding)
    }
}
