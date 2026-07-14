import AppKit
import UniformTypeIdentifiers

/// .md 기본 앱 조회·지정 (설정 ▸ Files). LaunchServices 는 번들 선언
/// (CFBundleDocumentTypes + UTImportedTypeDeclarations)을 근거로 후보를 인정한다.
@MainActor
enum DefaultAppService {
    /// 앱이 UTImportedTypeDeclarations 로 임포트하는 마크다운 UTI.
    static let markdownType = UTType(importedAs: "net.daringfireball.markdown")

    /// 현재 .md 기본 앱의 표시 이름 (없으면 nil).
    static func currentHandlerName() -> String? {
        guard let url = currentHandlerURL() else { return nil }
        return FileManager.default.displayName(atPath: url.path)
    }

    /// Mding 이 이미 기본 앱인지 — 설치 경로가 달라질 수 있으므로 번들 ID 로 비교한다.
    static func isCurrentHandler() -> Bool {
        guard let url = currentHandlerURL() else { return false }
        return Bundle(url: url)?.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    /// Mding 을 .md 기본 앱으로 지정. 파일 타입 핸들러 변경은 시스템 확인 팝업 없이 적용된다.
    static func setAsDefault() async throws {
        try await NSWorkspace.shared.setDefaultApplication(
            at: Bundle.main.bundleURL,
            toOpen: markdownType
        )
    }

    private static func currentHandlerURL() -> URL? {
        NSWorkspace.shared.urlForApplication(toOpen: markdownType)
    }
}
