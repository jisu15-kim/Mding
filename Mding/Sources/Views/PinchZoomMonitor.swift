import AppKit
import SwiftUI

/// 트랙패드 핀치(두손가락 오므리기/벌리기)로 글자 크기를 조절한다. ⌘=/⌘- 와 같은
/// `AppSettings.editorFontSize` 를 움직이므로 에디터 폰트와 프리뷰 zoom 이 함께 따라온다.
/// SwipeRevealMonitor 와 같은 로컬 모니터 방식 — 창 안 어디서 핀치해도 동작하고 이벤트는
/// 소비하지 않는다(창 안에 magnify 를 처리하는 뷰는 없다: NSTextView 는 기본 무처리,
/// WKWebView 는 allowsMagnification=false 라 상위 responder 로 넘긴다).
struct PinchZoomMonitor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.install(on: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.tearDown()
    }

    /// 제스처 시작 시점 폰트 크기에 누적 배율(1 + magnification)을 곱해 목표 크기를 구한다.
    /// 정수로 반올림해 ⌘=/⌘- 및 설정 스테퍼와 같은 1pt 눈금을 쓰고, 허용 범위로 클램프한다.
    /// 반올림이 곧 스로틀 — 핀치 한 번에 최대 범위 폭만큼만 갱신되어 NSTextView 전체
    /// 재레이아웃이 이벤트마다 일어나지 않는다.
    @MainActor
    static func targetFontSize(start: Double, magnification: Double) -> Double {
        let range = AppSettings.editorFontSizeRange
        let scaled = (start * (1 + magnification)).rounded()
        return min(max(scaled, range.lowerBound), range.upperBound)
    }

    @MainActor
    final class Coordinator {
        private weak var hostView: NSView?
        private var magnifyMonitor: Any?
        private var smartMagnifyMonitor: Any?

        /// 제스처 시작 시 폰트 크기. nil 이면 진행 중인 제스처가 없다.
        private var startFontSize: Double?
        /// `NSEvent.magnification` 은 직전 이벤트 대비 증분이라 제스처 동안 누적한다.
        private var accumulatedMagnification: Double = 0

        func install(on view: NSView) {
            hostView = view
            magnifyMonitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { [weak self] event in
                self?.handleMagnify(event)
                return event
            }
            // 두손가락 더블탭(스마트 줌)은 ⌘0 과 같은 기본 크기 복원.
            smartMagnifyMonitor = NSEvent.addLocalMonitorForEvents(matching: .smartMagnify) { [weak self] event in
                self?.handleSmartMagnify(event)
                return event
            }
        }

        func tearDown() {
            if let magnifyMonitor {
                NSEvent.removeMonitor(magnifyMonitor)
            }
            if let smartMagnifyMonitor {
                NSEvent.removeMonitor(smartMagnifyMonitor)
            }
            magnifyMonitor = nil
            smartMagnifyMonitor = nil
        }

        deinit {
            if let magnifyMonitor {
                NSEvent.removeMonitor(magnifyMonitor)
            }
            if let smartMagnifyMonitor {
                NSEvent.removeMonitor(smartMagnifyMonitor)
            }
        }

        /// 자기 윈도우의 이벤트만 처리 — 다른 윈도우의 제스처에 반응하지 않는다.
        private func isOwnWindow(_ event: NSEvent) -> Bool {
            guard let window = hostView?.window else { return false }
            return event.window === window
        }

        private func handleMagnify(_ event: NSEvent) {
            guard isOwnWindow(event) else { return }

            switch event.phase {
            case .began:
                startFontSize = AppSettings.shared.editorFontSize
                accumulatedMagnification = 0
            case .changed:
                // .began 을 놓친 경우(모니터가 제스처 도중 설치된 때)도 현재 크기 기준으로 이어간다.
                let start = startFontSize ?? AppSettings.shared.editorFontSize
                startFontSize = start
                accumulatedMagnification += event.magnification
                let target = PinchZoomMonitor.targetFontSize(start: start, magnification: accumulatedMagnification)
                if AppSettings.shared.editorFontSize != target {
                    AppSettings.shared.editorFontSize = target
                }
            case .ended, .cancelled:
                startFontSize = nil
                accumulatedMagnification = 0
            default:
                break
            }
        }

        private func handleSmartMagnify(_ event: NSEvent) {
            guard isOwnWindow(event) else { return }
            guard AppSettings.shared.editorFontSize != AppSettings.defaultEditorFontSize else { return }
            AppSettings.shared.editorFontSize = AppSettings.defaultEditorFontSize
        }
    }
}
