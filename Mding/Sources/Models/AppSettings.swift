import Foundation
import Observation

/// 영속 앱 설정 (§4.6). `UserDefaults` 를 직접 래핑한다 — `@AppStorage` 는 View 전용 프로퍼티
/// 래퍼라 ViewModel/모델에는 쓰지 않는다. `@Observable` 이므로 이 값을 읽는 View 는 변경을 자동 추적한다.
@MainActor @Observable
final class AppSettings {
    static let shared = AppSettings()

    private enum Key {
        static let theme = "selectedTheme"
        static let relativePathBase = "relativePathBase"
        static let customRelativeBasePath = "customRelativeBasePath"
        static let editorFontSize = "editorFontSize"
        static let tabIndentWidth = "tabIndentWidth"
        static let defaultViewMode = "defaultViewMode"
        static let showOutline = "showOutline"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }

    private let defaults: UserDefaults

    var theme: AppTheme {
        didSet { defaults.set(theme.rawValue, forKey: Key.theme) }
    }
    var relativePathBase: RelativePathBase {
        didSet { defaults.set(relativePathBase.rawValue, forKey: Key.relativePathBase) }
    }
    var customRelativeBasePath: String {
        didSet { defaults.set(customRelativeBasePath, forKey: Key.customRelativeBasePath) }
    }
    var editorFontSize: Double {
        didSet { defaults.set(editorFontSize, forKey: Key.editorFontSize) }
    }
    var tabIndentWidth: Int {
        didSet { defaults.set(tabIndentWidth, forKey: Key.tabIndentWidth) }
    }
    var defaultViewMode: ViewMode {
        didSet { defaults.set(defaultViewMode.rawValue, forKey: Key.defaultViewMode) }
    }
    /// 아웃라인(TOC) 사이드바 표시 여부 — 앱 전역, 창/탭 공용(§4.6 확장).
    var showOutline: Bool {
        didSet { defaults.set(showOutline, forKey: Key.showOutline) }
    }
    /// 최초 실행 온보딩 투어 완료 여부 (§온보딩). 투어를 끝내거나 도중에 닫으면 true —
    /// 이후로는 다시 노출하지 않는다. 기본값 false 는 신규 설치의 미설정 상태와 일치한다.
    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) }
    }

    /// 테스트 주입용. 기본은 `.standard`.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        theme = Self.loadEnum(Key.theme, default: .system, from: defaults)
        relativePathBase = Self.loadEnum(Key.relativePathBase, default: .gitRoot, from: defaults)
        customRelativeBasePath = defaults.string(forKey: Key.customRelativeBasePath) ?? ""

        let storedFontSize = defaults.object(forKey: Key.editorFontSize) as? Double
        editorFontSize = storedFontSize ?? 13

        let storedTabWidth = defaults.object(forKey: Key.tabIndentWidth) as? Int
        tabIndentWidth = storedTabWidth ?? 4

        defaultViewMode = Self.loadEnum(Key.defaultViewMode, default: .preview, from: defaults)

        showOutline = defaults.object(forKey: Key.showOutline) as? Bool ?? false

        hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
    }

    /// 에디터 폰트 크기 허용 범위 — Settings 스테퍼와 ⌘+/⌘- 조정이 공유하는 단일 출처.
    static let editorFontSizeRange: ClosedRange<Double> = 9...24
    static let defaultEditorFontSize: Double = 13

    /// ⌘+/⌘- 폰트 크기 조정. 범위를 벗어나지 않게 클램프한다.
    func adjustEditorFontSize(by delta: Double) {
        let adjusted = editorFontSize + delta
        editorFontSize = min(max(adjusted, Self.editorFontSizeRange.lowerBound), Self.editorFontSizeRange.upperBound)
    }

    /// 잘못된(또는 저장되지 않은) rawValue 는 기본값으로 폴백한다.
    private static func loadEnum<T: RawRepresentable>(
        _ key: String, default defaultValue: T, from defaults: UserDefaults
    ) -> T where T.RawValue == String {
        guard let raw = defaults.string(forKey: key), let value = T(rawValue: raw) else {
            return defaultValue
        }
        return value
    }
}
