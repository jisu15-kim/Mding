import AppKit
import SwiftUI
import WebKit

/// Bear 식 두손가락 가로 스와이프로 아웃라인 사이드바를 열고 닫는다.
/// 로컬 모니터로 트랙패드 스크롤 휠 제스처를 관찰만 하고 이벤트는 손대지 않고 그대로 반환한다 —
/// 일반 스크롤(수직/수평 모두)을 절대 방해해서는 안 된다.
struct SwipeRevealMonitor: NSViewRepresentable {
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

    @MainActor
    final class Coordinator {
        /// 이 이상 가로로 누적돼야 제스처로 인정한다.
        private let triggerThreshold: CGFloat = 60
        /// 세로 누적 대비 가로 누적이 이 배수 이상이어야 "가로 스와이프"로 판단한다(수직 스크롤 오인 방지).
        private let horizontalDominance: CGFloat = 2.5

        private weak var hostView: NSView?
        private var monitor: Any?

        private var accumulatedX: CGFloat = 0
        private var accumulatedY: CGFloat = 0
        private var didTriggerThisGesture = false
        /// 가로 스크롤 가능한 콘텐츠(코드블록/표 등) 위에서 시작한 제스처는 콘텐츠 스크롤의
        /// 몫이므로 — 스크롤이 끝에 닿은 뒤 이어지는 델타까지 포함해 — 사이드바 토글에서 제외한다.
        private var eligibility: GestureEligibility = .eligible
        /// 웹뷰 DOM 질의(비동기) 응답이 늦게 도착해도 다음 제스처에 오적용되지 않게 하는 세대 번호.
        private var gestureGeneration = 0

        private enum GestureEligibility {
            case eligible
            case ineligible
            case pendingWebViewAnswer
        }

        func install(on view: NSView) {
            hostView = view
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handle(event)
                return event  // 절대 소비하지 않는다 — 스크롤은 항상 정상 동작해야 한다.
            }
        }

        func tearDown() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }

        private func handle(_ event: NSEvent) {
            // 자기 윈도우의 이벤트만 처리 — 다른 윈도우(다른 문서)의 제스처에 반응하지 않는다.
            guard let window = hostView?.window, event.window === window else { return }
            // 관성(momentum) 스크롤은 실제 손가락 움직임이 아니므로 무시.
            guard event.momentumPhase.isEmpty else { return }

            switch event.phase {
            case .began:
                accumulatedX = 0
                accumulatedY = 0
                didTriggerThisGesture = false
                beginEligibilityCheck(for: event, in: window)
            case .changed:
                guard !didTriggerThisGesture, eligibility != .ineligible else { return }
                accumulatedX += event.scrollingDeltaX
                accumulatedY += event.scrollingDeltaY
                if eligibility == .eligible {
                    evaluateTrigger(event)
                }
            case .ended, .cancelled:
                accumulatedX = 0
                accumulatedY = 0
                didTriggerThisGesture = false
            default:
                break
            }
        }

        /// 제스처 시작 지점 아래에 가로 스크롤 가능한 콘텐츠가 있는지 판정한다.
        /// AppKit 쪽(NSScrollView)은 동기 hit-test 로, 프리뷰 내부(코드블록/표)는 DOM 질의(비동기)로 —
        /// 응답이 오기 전까지는 트리거를 보류하고 델타만 누적한다(응답은 임계값 도달 전에 도착).
        private func beginEligibilityCheck(for event: NSEvent, in window: NSWindow) {
            gestureGeneration += 1
            let generation = gestureGeneration
            eligibility = .eligible

            guard let contentView = window.contentView,
                  let hit = contentView.hitTest(event.locationInWindow) else { return }

            var view: NSView? = hit
            while let current = view {
                // 소스 에디터는 소프트랩(가로 스크롤 없음)이 설계 전제 — 항상 스와이프 대상.
                // 감싸는 NSScrollView 의 지오메트리 오차로 ineligible 오판되는 것을 차단한다.
                if current is EditorTextView {
                    return  // eligibility 는 이미 .eligible
                }
                if let scrollView = current as? NSScrollView,
                   let documentView = scrollView.documentView,
                   documentView.frame.width > scrollView.contentSize.width + 1 {
                    eligibility = .ineligible
                    return
                }
                if let webView = current as? PreviewWKWebView {
                    eligibility = .pendingWebViewAnswer
                    let point = webView.convert(event.locationInWindow, from: nil)
                    webView.evaluateJavaScript(
                        "window.canScrollHorizontallyAt(\(point.x), \(point.y))"
                    ) { [weak self] result, _ in
                        MainActor.assumeIsolated {
                            guard let self, self.gestureGeneration == generation else { return }
                            self.eligibility = (result as? Bool == true) ? .ineligible : .eligible
                        }
                    }
                    return
                }
                view = current.superview
            }
        }

        private func evaluateTrigger(_ event: NSEvent) {
            let absX = abs(accumulatedX)
            let absY = abs(accumulatedY)
            guard absX > triggerThreshold, absX > horizontalDominance * absY else { return }

            // 내추럴 스크롤(isDirectionInvertedFromDevice == true)에서는 scrollingDeltaX 가
            // 이미 손가락 이동 방향을 따른다(손가락 오른쪽 = 양수). 꺼져 있으면 반대라 부호를
            // 뒤집는다 — 시스템 설정과 무관하게 항상 "손가락 오른쪽 = 열기, 왼쪽 = 닫기".
            let fingerDeltaX = event.isDirectionInvertedFromDevice ? accumulatedX : -accumulatedX
            didTriggerThisGesture = true

            let shouldOpen = fingerDeltaX > 0
            guard AppSettings.shared.showOutline != shouldOpen else { return }  // 이미 목표 상태면 no-op.
            withAnimation(.easeInOut(duration: 0.2)) {
                AppSettings.shared.showOutline = shouldOpen
            }
        }
    }
}
