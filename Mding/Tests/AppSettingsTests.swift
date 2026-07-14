import XCTest
@testable import Mding

/// AppSettings 영속화 검증: 기본값, 저장/재로드, 잘못된 rawValue 폴백 (§4.6).
final class AppSettingsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "AppSettingsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    @MainActor
    func test_defaults_matchSpec() {
        let settings = AppSettings(defaults: defaults)

        XCTAssertEqual(settings.theme, .system)
        XCTAssertEqual(settings.editorFontSize, 13)
        XCTAssertEqual(settings.tabIndentWidth, 4)
        XCTAssertEqual(settings.defaultViewMode, .preview)
        XCTAssertEqual(settings.relativePathBase, .gitRoot)
        XCTAssertEqual(settings.customRelativeBasePath, "")
        XCTAssertEqual(settings.showOutline, false)
    }

    @MainActor
    func test_valuesPersist_acrossInstances() {
        let first = AppSettings(defaults: defaults)
        first.theme = .dark
        first.editorFontSize = 18
        first.tabIndentWidth = 2
        first.defaultViewMode = .editor
        first.relativePathBase = .custom
        first.customRelativeBasePath = "/tmp/base"
        first.showOutline = true

        // 새 인스턴스로 다시 읽어 UserDefaults 에 실제로 persist 되었는지 확인.
        let second = AppSettings(defaults: defaults)
        XCTAssertEqual(second.theme, .dark)
        XCTAssertEqual(second.editorFontSize, 18)
        XCTAssertEqual(second.tabIndentWidth, 2)
        XCTAssertEqual(second.defaultViewMode, .editor)
        XCTAssertEqual(second.relativePathBase, .custom)
        XCTAssertEqual(second.customRelativeBasePath, "/tmp/base")
        XCTAssertEqual(second.showOutline, true)
    }

    @MainActor
    func test_invalidRawValue_fallsBackToDefault() {
        // 저장된 값이 현재 enum 케이스와 맞지 않는 경우(구버전 잔존 값 등) 기본값으로 폴백해야 한다.
        defaults.set("not-a-theme", forKey: "selectedTheme")
        defaults.set("not-a-base", forKey: "relativePathBase")
        defaults.set("not-a-view-mode", forKey: "defaultViewMode")

        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.theme, .system)
        XCTAssertEqual(settings.relativePathBase, .gitRoot)
        XCTAssertEqual(settings.defaultViewMode, .preview)
    }
}
