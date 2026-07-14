import AppKit

/// 앱 테마: 시스템 / 라이트 / 다크 (§4.6). 사용자 노출 라벨은 View 쪽에서 로컬라이즈한다.
enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    /// `NSApp.appearance` 인자. system 은 nil(OS 설정을 그대로 따른다).
    /// 앱 전역 appearance 라 문서 윈도우뿐 아니라 풀스크린 툴바 오버레이
    /// (NSToolbarFullScreenWindow)·메뉴·패널까지 전파된다.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }

    /// preview.html 의 `window.setTheme(name)` 인자와 동일한 문자열 (§4.6).
    var previewName: String { rawValue }
}
