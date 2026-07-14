import SwiftUI

/// 앱 테마: 시스템 / 라이트 / 다크 (§4.6). 사용자 노출 라벨은 View 쪽에서 로컬라이즈한다.
enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    /// `.preferredColorScheme` 인자. system 은 nil(OS 설정을 그대로 따른다).
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    /// preview.html 의 `window.setTheme(name)` 인자와 동일한 문자열 (§4.6).
    var previewName: String { rawValue }
}
