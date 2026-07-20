import Foundation

/// 문서별(파일 경로 키) 프리뷰 설정의 영속 저장소 (§ 전체 너비).
///
/// 파일 내용이나 폴더를 건드리지 않고 `UserDefaults` 에 `경로 → 설정` 맵으로 보관한다.
/// 앱은 non-sandbox 라 절대 경로를 그대로 키로 쓴다. 경로가 키이므로 앱 밖에서 파일을
/// 옮기거나 이름을 바꾸면 연결이 끊겨 기본값으로 돌아간다 — 미리보기 외형 설정이라 감수한다.
///
/// 기본값(false)은 맵에 남기지 않고 항목을 제거해, 켠 문서만 저장되도록 한다(맵 무한 증가 방지).
@MainActor
enum DocumentPrefsStore {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let fullWidth = "documentFullWidth"   // [absolutePath: Bool]
    }

    static func fullWidth(for url: URL) -> Bool {
        let map = defaults.dictionary(forKey: Key.fullWidth) as? [String: Bool]
        return map?[url.path] ?? false
    }

    static func setFullWidth(_ on: Bool, for url: URL) {
        var map = (defaults.dictionary(forKey: Key.fullWidth) as? [String: Bool]) ?? [:]
        if on {
            map[url.path] = true
        } else {
            map.removeValue(forKey: url.path)
        }
        defaults.set(map, forKey: Key.fullWidth)
    }
}
