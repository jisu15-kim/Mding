import XCTest
@testable import Mding

/// 자동저장(§8.1)과 외부 변경 처리의 자동화 가능한 검증.
@MainActor
final class DocumentViewModelTests: XCTestCase {
    private var tempURL: URL!

    override func setUp() async throws {
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MdingTests-\(UUID().uuidString).md")
        try "# original\n".write(to: tempURL, atomically: true, encoding: .utf8)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempURL)
    }

    func test_updateText_debouncesPreviewText() throws {
        let vm = DocumentViewModel()
        try vm.load(url: tempURL)
        vm.updateText("# edited")
        XCTAssertEqual(vm.previewText, "# original\n", "preview must not update synchronously")
        XCTAssertTrue(vm.isDirty)

        try waitUntil(timeout: 2, description: "preview debounce") { vm.previewText == "# edited" }
    }

    func test_autosave_writesToDiskAfterIdleDebounce() throws {
        let vm = DocumentViewModel()
        try vm.load(url: tempURL)
        vm.updateText("# autosaved")

        try waitUntil(timeout: 4, description: "autosave flush") {
            (try? String(contentsOf: self.tempURL, encoding: .utf8)) == "# autosaved"
        }
        try waitUntil(timeout: 1, description: "dirty cleared") { vm.isDirty == false }
    }

    func test_flush_writesImmediately() throws {
        let vm = DocumentViewModel()
        try vm.load(url: tempURL)
        vm.updateText("# flushed")
        XCTAssertTrue(vm.flush())
        XCTAssertEqual(try String(contentsOf: tempURL, encoding: .utf8), "# flushed")
        XCTAssertFalse(vm.isDirty)
    }

    func test_externalChange_whenClean_reloadsSilently() throws {
        let vm = DocumentViewModel()
        try vm.load(url: tempURL)

        try "# external\n".write(to: tempURL, atomically: true, encoding: .utf8)

        try waitUntil(timeout: 3, description: "silent reload") { vm.text == "# external\n" }
        XCTAssertFalse(vm.hasExternalChangeConflict)
        XCTAssertFalse(vm.isDirty)
    }

    func test_externalChange_whenDirty_flagsConflict() throws {
        let vm = DocumentViewModel()
        try vm.load(url: tempURL)
        vm.updateText("# local edit")

        try "# external\n".write(to: tempURL, atomically: true, encoding: .utf8)

        try waitUntil(timeout: 3, description: "conflict flagged") { vm.hasExternalChangeConflict }
        XCTAssertEqual(vm.text, "# local edit", "local edits must be kept until the user decides")
    }

    func test_conflictResolution_reload_discardsLocalEdits() throws {
        let vm = DocumentViewModel()
        try vm.load(url: tempURL)
        vm.updateText("# local edit")
        try "# external\n".write(to: tempURL, atomically: true, encoding: .utf8)
        try waitUntil(timeout: 3, description: "conflict flagged") { vm.hasExternalChangeConflict }

        vm.resolveConflictReloading()
        XCTAssertEqual(vm.text, "# external\n")
        XCTAssertFalse(vm.isDirty)
        XCTAssertFalse(vm.hasExternalChangeConflict)
    }

    // MARK: - Helpers

    private func waitUntil(
        timeout: TimeInterval,
        description: String,
        condition: @escaping @MainActor () -> Bool
    ) throws {
        let expectation = expectation(description: description)
        let task = Task { @MainActor in
            while !Task.isCancelled {
                if condition() {
                    expectation.fulfill()
                    return
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        wait(for: [expectation], timeout: timeout)
        task.cancel()
    }
}
