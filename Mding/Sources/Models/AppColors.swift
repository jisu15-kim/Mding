import AppKit

/// Bear 스타일 창 배경 통합(§4.8 확장) — 프리뷰 문서 배경과 정확히 일치시켜 툴바/탭바/콘텐츠 경계를 지운다.
/// 단일 출처: `preview.html` 의 `body[data-theme]` 배경(light **#F7F7F5**(종이 톤) / dark #0d1117)과
/// 반드시 같은 값이어야 한다. github-markdown CSS 의 `.markdown-body` 자체 배경은 preview.html 에서
/// 투명 처리되어 body 색이 문서 배경을 결정한다.
enum AppColors {
    /// 창의 appearance 는 `WindowRootView.preferredColorScheme` 가 이미 테마 설정을 강제하므로
    /// 이 dynamic color 도 aqua/darkAqua 분기로 자동 추종한다.
    static let contentBackground = NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark
            ? NSColor(srgbRed: 0x0d / 255.0, green: 0x11 / 255.0, blue: 0x17 / 255.0, alpha: 1.0)
            : NSColor(srgbRed: 0xf7 / 255.0, green: 0xf7 / 255.0, blue: 0xf5 / 255.0, alpha: 1.0)
    }
}
