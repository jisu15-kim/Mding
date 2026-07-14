import XCTest
@testable import Mding

/// WindowViewModel.adoptTab(§4.1 확장 — 윈도우 간 탭 드래그 이동) 검증.
/// 주의: WindowViewModel.init() 이 Welcome 탭 1개를 자동 생성한다.
@MainActor
final class WindowViewModelTests: XCTestCase {
    func test_adoptTab_movesTabBetweenWindows() {
        let a = WindowViewModel()
        let moved = a.newTab()  // A: [welcome, moved]

        let b = WindowViewModel()
        b.newTab()  // B: [welcome, welcome2]

        b.adoptTab(moved, from: a, at: 1)

        XCTAssertEqual(a.tabs.count, 1, "이동한 탭은 출발 윈도우에서 제거되어야 한다")
        XCTAssertEqual(b.tabs.count, 3, "대상 윈도우에 탭이 추가되어야 한다")
        XCTAssertEqual(b.selectedTabID, moved.id, "이동한 탭이 대상 윈도우에서 선택 상태가 되어야 한다")
        XCTAssertEqual(b.tabs[1].id, moved.id, "지정한 index 위치에 삽입되어야 한다")
    }

    func test_adoptTab_fixesSourceSelection() {
        let a = WindowViewModel()
        let moved = a.newTab()  // A: [welcome, moved], selectedTabID == moved.id

        let b = WindowViewModel()

        XCTAssertEqual(a.selectedTabID, moved.id)
        b.adoptTab(moved, from: a, at: nil)

        XCTAssertEqual(a.tabs.count, 1)
        XCTAssertNotEqual(a.selectedTabID, moved.id, "출발 윈도우의 선택이 남은 탭으로 보정되어야 한다")
        XCTAssertEqual(a.selectedTabID, a.tabs[0].id)
    }

    func test_adoptTab_sameWindow_noop() {
        let a = WindowViewModel()
        let tab = a.newTab()

        let tabsBefore = a.tabs.map(\.id)
        let selectionBefore = a.selectedTabID

        a.adoptTab(tab, from: a, at: 0)

        XCTAssertEqual(a.tabs.map(\.id), tabsBefore, "자기 자신으로의 adopt 는 아무 변화도 없어야 한다")
        XCTAssertEqual(a.selectedTabID, selectionBefore)
    }

    func test_adoptTab_emptiedSource() {
        let a = WindowViewModel()
        let onlyTab = a.selectedTab!  // A: [welcome] (유일한 탭)

        let b = WindowViewModel()
        b.adoptTab(onlyTab, from: a, at: nil)

        XCTAssertTrue(a.tabs.isEmpty, "마지막 탭이 이동하면 출발 윈도우는 비어야 한다")
        // a.nsWindow 는 테스트에서 nil 이므로 close() 는 no-op — 크래시 없이 통과하면 충분하다.
    }

    func test_adoptTab_indexClamped() {
        let a = WindowViewModel()
        let moved = a.newTab()  // A: [welcome, moved]

        let b = WindowViewModel()  // B: [welcome]

        b.adoptTab(moved, from: a, at: 99)

        XCTAssertEqual(b.tabs.count, 2, "범위 밖 index 는 append 로 클램프되어야 한다")
        XCTAssertEqual(b.tabs.last?.id, moved.id)
    }

    // MARK: - openFile 중복 열기 방지 (같은 파일 = 기존 탭 포커스)

    func test_openFile_alreadyOpenInSameWindow_focusesExistingTab() throws {
        let url = try makeTempMarkdownFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let a = WindowViewModel()
        WindowRegistry.shared.register(a)
        defer { WindowRegistry.shared.unregister(a.id) }

        a.openFile(url: url)  // Welcome 탭이 에디터로 전환
        let existingID = a.selectedTabID
        a.newTab()            // 선택을 새 Welcome 탭으로 이동
        XCTAssertEqual(a.tabs.count, 2)

        a.openFile(url: url)  // 같은 파일 다시 열기

        XCTAssertEqual(a.tabs.count, 2, "중복 탭이 생기면 안 된다")
        XCTAssertEqual(a.selectedTabID, existingID, "기존 탭이 다시 선택되어야 한다")
        XCTAssertEqual(
            a.tabs.filter { $0.fileURL?.standardizedFileURL.path == url.standardizedFileURL.path }.count, 1,
            "같은 파일을 가진 탭은 하나뿐이어야 한다"
        )
    }

    func test_openFile_alreadyOpenInOtherWindow_focusesThatWindowsTab() throws {
        let url = try makeTempMarkdownFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let a = WindowViewModel()
        WindowRegistry.shared.register(a)
        defer { WindowRegistry.shared.unregister(a.id) }
        a.openFile(url: url)
        let existingID = a.selectedTabID
        a.newTab()  // A 의 선택을 다른 탭으로

        let b = WindowViewModel()
        WindowRegistry.shared.register(b)
        defer { WindowRegistry.shared.unregister(b.id) }

        b.openFile(url: url)  // B 에서 같은 파일 열기

        XCTAssertEqual(b.tabs.count, 1, "B 에 새 탭이 생기면 안 된다")
        XCTAssertEqual(b.tabs.first?.mode, .welcome, "B 의 Welcome 탭이 전환되면 안 된다")
        XCTAssertEqual(a.selectedTabID, existingID, "A 의 기존 탭이 선택되어야 한다")
    }

    private func makeTempMarkdownFile() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WindowVMTests-\(UUID().uuidString).md")
        try "# t\n".write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
