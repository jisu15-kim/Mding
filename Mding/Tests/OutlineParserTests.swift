import XCTest
@testable import Mding

/// OutlineParser 검증: 레벨 1~6, 코드 펜스 제외, 후행 해시 제거, line 인덱스 정확성 (§ 아웃라인 사이드바).
final class OutlineParserTests: XCTestCase {
    func test_emptyDocument_returnsEmptyArray() {
        XCTAssertEqual(OutlineParser.parse(""), [])
    }

    func test_parsesAllHeadingLevels() {
        let markdown = """
        # H1
        ## H2
        ### H3
        #### H4
        ##### H5
        ###### H6
        """
        let outline = OutlineParser.parse(markdown)
        XCTAssertEqual(outline.map(\.level), [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(outline.map(\.title), ["H1", "H2", "H3", "H4", "H5", "H6"])
        XCTAssertEqual(outline.map(\.line), [0, 1, 2, 3, 4, 5])
    }

    func test_sevenHashes_isNotAHeading() {
        XCTAssertEqual(OutlineParser.parse("####### Not A Heading"), [])
    }

    func test_hashWithoutSpace_isNotAHeading() {
        // "#5" 같은 형태는 헤딩 마커가 아니다 (`^#{1,6} ` 요구).
        XCTAssertEqual(OutlineParser.parse("#5 not-a-heading"), [])
    }

    func test_stripsTrailingClosingHashes() {
        let outline = OutlineParser.parse("## Section ##")
        XCTAssertEqual(outline.map(\.title), ["Section"])
    }

    func test_excludesHeadingsInsideBacktickFence() {
        let markdown = """
        # Before
        ```
        # Not A Heading
        ```
        # After
        """
        let outline = OutlineParser.parse(markdown)
        XCTAssertEqual(outline.map(\.title), ["Before", "After"])
        XCTAssertEqual(outline.map(\.line), [0, 4])
    }

    func test_excludesHeadingsInsideTildeFence() {
        let markdown = """
        # Before
        ~~~
        # Not A Heading
        ~~~
        # After
        """
        let outline = OutlineParser.parse(markdown)
        XCTAssertEqual(outline.map(\.title), ["Before", "After"])
        XCTAssertEqual(outline.map(\.line), [0, 4])
    }

    func test_unclosedFence_isSafeAndExcludesRemainingHeadings() {
        let markdown = """
        # Before
        ```
        # Still Inside Fence
        # Also Inside
        """
        // 크래시/무한루프 없이 안전하게 끝나야 하며, 미닫힌 펜스 이후 헤딩은 제외된다.
        let outline = OutlineParser.parse(markdown)
        XCTAssertEqual(outline.map(\.title), ["Before"])
    }

    func test_lineIndex_isAccurateAcrossBlankLines() {
        let markdown = """
        Intro text.

        # First

        Some body text.
        More body text.

        ## Second
        """
        // 0:"Intro text." 1:"" 2:"# First" 3:"" 4:"Some body text." 5:"More body text." 6:"" 7:"## Second"
        let outline = OutlineParser.parse(markdown)
        XCTAssertEqual(outline.map(\.title), ["First", "Second"])
        XCTAssertEqual(outline.map(\.line), [2, 7])
    }
}
