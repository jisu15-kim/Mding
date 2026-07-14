import AppKit
import WebKit

/// 앱 크롬 + 프리뷰 테마를 동시에 전환한다 (§4.6). 무상태 서비스 — 상태 자체는 `AppSettings` 가 소유한다.
@MainActor
enum ThemeManager {
    /// 테마를 반영: `AppSettings` 갱신 + 앱 전역 appearance + 살아 있는 모든 프리뷰 웹뷰에 즉시 적용.
    /// 앱 크롬은 윈도우 단위 `.preferredColorScheme` 가 아니라 `NSApp.appearance` 로 강제한다 —
    /// 풀스크린 툴바는 별도 시스템 윈도우(NSToolbarFullScreenWindow)에 호스팅되어
    /// 윈도우 단위 appearance 를 상속받지 않으므로, 전역 설정만이 크롬 테마 분열을 막는다.
    static func apply(_ theme: AppTheme) {
        AppSettings.shared.theme = theme
        NSApp.appearance = theme.nsAppearance
        PreviewWebViewPool.shared.applyToAll { webView in
            MarkdownRenderer.setTheme(theme.previewName, in: webView)
        }
    }
}
