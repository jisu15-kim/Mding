import XCTest
@testable import Mding

/// 웹뷰 LRU 풀(§4.2)의 상한/해제 정책 자동 검증. (Activity Monitor 수동 확인의 자동화 버전.)
@MainActor
final class PreviewWebViewPoolTests: XCTestCase {
    func test_pool_capsLiveWebViewsAtFive() {
        let pool = PreviewWebViewPool.shared
        var docs: [DocumentViewModel] = []

        // 탭 7개를 열고 각각 화면에서 벗어나게(markInactive) 한다 — 탭 전환 시뮬레이션.
        for _ in 0..<7 {
            let doc = DocumentViewModel()
            docs.append(doc)
            _ = pool.acquire(for: doc)
            pool.markInactive(doc.id)
        }

        XCTAssertLessThanOrEqual(pool.liveCount, 5, "살아있는 웹뷰는 앱 전체 5개 이하여야 한다 (§4.2)")

        for doc in docs { pool.release(doc.id) }
        XCTAssertEqual(pool.liveCount, 0, "탭을 모두 닫으면 웹뷰가 전부 해제되어야 한다")
    }

    func test_pool_reusesLiveWebViewWithoutRecreating() {
        let pool = PreviewWebViewPool.shared
        let doc = DocumentViewModel()

        let first = pool.acquire(for: doc)
        XCTAssertTrue(first.isNew, "처음 확보한 웹뷰는 새로 만들어져야 한다")

        pool.markInactive(doc.id)
        let second = pool.acquire(for: doc)
        XCTAssertFalse(second.isNew, "풀에 살아있으면 재사용되어야 한다")
        XCTAssertTrue(first.webView === second.webView, "같은 웹뷰 인스턴스를 재사용해야 한다")

        pool.release(doc.id)
    }
}
