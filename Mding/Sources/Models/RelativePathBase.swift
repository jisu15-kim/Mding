import Foundation

/// 상대 경로 복사 시 기준 디렉터리 (§4.5/§4.6). 사용자 노출 라벨은 View 쪽에서 로컬라이즈한다.
enum RelativePathBase: String, CaseIterable, Identifiable {
    case gitRoot
    case home
    case custom

    var id: String { rawValue }
}
