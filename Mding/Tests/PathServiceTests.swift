import XCTest
@testable import Mding

/// PathService 순수 경로 연산(relativePath) 및 파일시스템 조회(gitRoot) 검증.
final class PathServiceTests: XCTestCase {
    private var tempRoot: URL!

    override func setUp() {
        super.setUp()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PathServiceTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempRoot)
        tempRoot = nil
        super.tearDown()
    }

    // MARK: - relativePath

    func test_relativePath_sameDirectory() {
        let file = URL(fileURLWithPath: "/p/c.md")
        let base = URL(fileURLWithPath: "/p")
        XCTAssertEqual(PathService.relativePath(of: file, from: base), "c.md")
    }

    func test_relativePath_nestedSubdirectory() {
        let file = URL(fileURLWithPath: "/p/b/c.md")
        let base = URL(fileURLWithPath: "/p")
        XCTAssertEqual(PathService.relativePath(of: file, from: base), "b/c.md")
    }

    func test_relativePath_requiresGoingUp() {
        let file = URL(fileURLWithPath: "/p/x.md")
        let base = URL(fileURLWithPath: "/p/a/b")
        XCTAssertEqual(PathService.relativePath(of: file, from: base), "../../x.md")
    }

    func test_relativePath_sameDirectoryAsFile() {
        let file = URL(fileURLWithPath: "/p")
        let base = URL(fileURLWithPath: "/p")
        XCTAssertEqual(PathService.relativePath(of: file, from: base), ".")
    }

    func test_relativePath_deeperSubdirectory() {
        let file = URL(fileURLWithPath: "/p/a/b/d.md")
        let base = URL(fileURLWithPath: "/p")
        XCTAssertEqual(PathService.relativePath(of: file, from: base), "a/b/d.md")
    }

    // MARK: - gitRoot

    func test_gitRoot_findsDirectoryGitEntry() throws {
        let repoDir = tempRoot.appendingPathComponent("repoDir", isDirectory: true)
        let gitDir = repoDir.appendingPathComponent(".git", isDirectory: true)
        let nestedDir = repoDir.appendingPathComponent("src/nested", isDirectory: true)
        let nestedFile = nestedDir.appendingPathComponent("file.md")

        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)
        try "content".write(to: nestedFile, atomically: true, encoding: .utf8)

        let found = PathService.gitRoot(for: nestedFile)
        XCTAssertEqual(
            found?.resolvingSymlinksInPath().standardizedFileURL.path,
            repoDir.resolvingSymlinksInPath().standardizedFileURL.path
        )
    }

    func test_gitRoot_findsFileGitEntry_worktree() throws {
        let repoDir = tempRoot.appendingPathComponent("repoFile", isDirectory: true)
        let gitFile = repoDir.appendingPathComponent(".git")
        let srcDir = repoDir.appendingPathComponent("src", isDirectory: true)
        let nestedFile = srcDir.appendingPathComponent("file.md")

        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        try "gitdir: /somewhere/.git/worktrees/repoFile\n".write(to: gitFile, atomically: true, encoding: .utf8)
        try "content".write(to: nestedFile, atomically: true, encoding: .utf8)

        let found = PathService.gitRoot(for: nestedFile)
        XCTAssertEqual(
            found?.resolvingSymlinksInPath().standardizedFileURL.path,
            repoDir.resolvingSymlinksInPath().standardizedFileURL.path
        )
    }

    func test_gitRoot_noGitEntry_returnsNilOrAncestorOfTempTree() throws {
        let noGitDir = tempRoot.appendingPathComponent("noGit/src", isDirectory: true)
        let noGitFile = noGitDir.appendingPathComponent("file.md")

        try FileManager.default.createDirectory(at: noGitDir, withIntermediateDirectories: true)
        try "content".write(to: noGitFile, atomically: true, encoding: .utf8)

        // 이 임시 하위 트리에는 어디에도 .git 을 두지 않았다. 테스트 머신의 임시 디렉터리가
        // 우연히 다른 저장소 안에 있을 수 있으므로 nil 을 강제하지 않는다. 대신 결과가 있다면
        // 반드시 임시 트리의 "바깥(조상)" 이어야 하며, 우리가 만든 .git 없는 하위 디렉터리일 수 없다.
        if let found = PathService.gitRoot(for: noGitFile) {
            let foundPath = found.resolvingSymlinksInPath().standardizedFileURL.path
            let tempRootPath = tempRoot.resolvingSymlinksInPath().standardizedFileURL.path
            XCTAssertFalse(
                foundPath.hasPrefix(tempRootPath),
                "no .git exists under the temp tree, so any found root must be an ancestor of it, not within it"
            )
        }
    }
}
