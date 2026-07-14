import Foundation

/// 문서 뷰 모드: 프리뷰만 / 에디터만 / 좌우 분할.
/// 케이스 선언 순서 = 토글/설정 Picker 노출 순서(Preview | Editor | Split).
/// 기본값은 `AppSettings.defaultViewMode`(기본 Preview, 설정에서 변경 가능).
enum ViewMode: String, CaseIterable, Identifiable {
    case preview
    case editor
    case split

    var id: String { rawValue }

    var label: String {
        switch self {
        case .editor:
            String(localized: "Editor", comment: "View mode toggle: source editor only")
        case .split:
            String(localized: "Split", comment: "View mode toggle: editor and preview side by side")
        case .preview:
            String(localized: "Preview", comment: "View mode toggle: rendered preview only")
        }
    }
}
