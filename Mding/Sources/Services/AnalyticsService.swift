import FirebaseAnalytics
import FirebaseCore

/// Firebase Analytics 커스텀 이벤트 중앙화 (§온보딩 계측). 자동 수집(스크린뷰 등) 외에
/// 우리가 명시적으로 남기는 이벤트를 여기로 모은다. 이벤트명·파라미터 키는 Firebase 규칙
/// (영문 소문자+언더스코어, 40자 이내)을 따른다.
enum AnalyticsService {
    enum Event {
        /// 온보딩 투어가 최초로 노출됨.
        static let onboardingShown = "onboarding_shown"
        /// 온보딩에서 .md 기본 앱 지정이 성공함.
        static let onboardingSetDefault = "onboarding_set_default"
        /// 투어를 끝까지 진행해 "Get Started" 로 닫음.
        static let onboardingCompleted = "onboarding_completed"
        /// 투어를 끝내지 않고 도중에 닫음(Esc 등).
        static let onboardingSkipped = "onboarding_skipped"
    }

    /// Firebase 가 구성된 경우에만 이벤트를 남긴다. GoogleService-Info.plist 가 없는 개발 빌드에서는
    /// `FirebaseApp.configure()` 를 호출하지 않으므로(AppDelegate) 여기서도 조용히 no-op 한다.
    static func log(_ name: String, _ parameters: [String: Any]? = nil) {
        guard FirebaseApp.app() != nil else { return }
        Analytics.logEvent(name, parameters: parameters)
    }
}
