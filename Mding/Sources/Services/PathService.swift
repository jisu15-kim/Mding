import Foundation

/// 경로 계산 유틸. 무상태. `relativePath` 는 순수 경로 연산(디스크 접근 없음), `gitRoot` 만 파일시스템을 조회한다.
enum PathService {
    /// `url` 로부터 상위 디렉터리를 순회하며 `.git` 항목을 찾는다.
    /// `.git` 디렉터리와 `.git` 파일(worktree) 을 모두 인식한다. 루트에 도달할 때까지 못 찾으면 `nil`.
    static func gitRoot(for url: URL) -> URL? {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL

        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory)
        var current = (exists && isDirectory.boolValue) ? resolved : resolved.deletingLastPathComponent()
        current = current.standardizedFileURL

        while true {
            let gitEntryPath = current.appendingPathComponent(".git").path
            if FileManager.default.fileExists(atPath: gitEntryPath) {
                return current
            }

            // 루트에서 멈춘다. 루트의 deletingLastPathComponent() 는 "/" 가 아니라 "/.." 를
            // 반환하므로 parent == current 비교만으로는 종료되지 않고 경로가 무한히 자란다.
            if current.path == "/" {
                return nil
            }
            let parent = current.deletingLastPathComponent().standardizedFileURL
            if parent.path == current.path {
                return nil
            }
            current = parent
        }
    }

    /// `file` 의 경로를 디렉터리 `base` 기준 상대 경로 문자열로 계산한다. 디스크에 접근하지 않는 순수 경로 연산.
    static func relativePath(of file: URL, from base: URL) -> String {
        let fileComponents = file.standardizedFileURL.pathComponents
        let baseComponents = base.standardizedFileURL.pathComponents

        var commonLength = 0
        while commonLength < fileComponents.count,
              commonLength < baseComponents.count,
              fileComponents[commonLength] == baseComponents[commonLength] {
            commonLength += 1
        }

        let upCount = baseComponents.count - commonLength
        let downComponents = fileComponents[commonLength...]
        let parts = Array(repeating: "..", count: upCount) + downComponents

        let result = parts.joined(separator: "/")
        return result.isEmpty ? "." : result
    }
}
