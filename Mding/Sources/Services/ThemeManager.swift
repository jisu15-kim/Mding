import AppKit
import WebKit

/// 앱 크롬 + 프리뷰 테마를 동시에 전환한다 (§4.6). 무상태 서비스 — 상태 자체는 `AppSettings` 가 소유한다.
@MainActor
enum ThemeManager {
    /// 테마를 반영: `AppSettings` 갱신 + 살아 있는 모든 프리뷰 웹뷰에 즉시 적용.
    /// 앱 크롬은 `AppSettings.shared.theme` 를 읽는 `.preferredColorScheme` 가 Observation 으로 자동 반영한다.
    static func apply(_ theme: AppTheme) {
        AppSettings.shared.theme = theme
        PreviewWebViewPool.shared.applyToAll { webView in
            MarkdownRenderer.setTheme(theme.previewName, in: webView)
        }
    }
}
