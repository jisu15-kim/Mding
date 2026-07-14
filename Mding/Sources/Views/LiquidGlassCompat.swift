import SwiftUI

/// Liquid Glass(macOS 26+) 호환 레이어 (§4.5). 최소 타깃이 macOS 15 이므로
/// glass API 는 반드시 이 파일의 래퍼를 통해서만 사용한다 — 15 에서는 표준 스타일로 폴백.

/// `GlassEffectContainer` 래퍼 — macOS 15 에서는 내용을 그대로 렌더링한다.
struct GlassContainer<Content: View>: View {
    private let spacing: CGFloat
    private let content: () -> Content

    init(spacing: CGFloat, @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.content = content
    }

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing, content: content)
        } else {
            content()
        }
    }
}

extension View {
    /// `.buttonStyle(.glass)` 래퍼 — macOS 15 에서는 `.bordered` 로 폴백.
    @ViewBuilder
    func glassButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }
}
