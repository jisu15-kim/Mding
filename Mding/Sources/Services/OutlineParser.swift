import Foundation

/// 마크다운 원문에서 ATX 헤딩(`^#{1,6} `)만 추출해 아웃라인을 만든다.
/// 코드 펜스(``` / ~~~) 내부는 헤딩으로 인식하지 않는다.
/// `line` 은 0-based 소스 라인 인덱스로 `preview.html` 의 `token.map[0]`(markdown-it 헤딩 토큰)과
/// 반드시 일치해야 한다 — 아웃라인 클릭 점프의 `data-line` 매칭 정확성이 여기에 달려 있다.
/// v1 범위 외: setext 헤딩(밑줄식 `===`/`---`), 블록쿼트 내부 헤딩은 파싱하지 않는다.
/// 아웃라인에는 안 보이지만, 점프는 항상 소스 라인 번호 그대로 매칭하므로 정합성은 깨지지 않는다.
enum OutlineParser {
    static func parse(_ markdown: String) -> [OutlineItem] {
        guard !markdown.isEmpty else { return [] }

        var items: [OutlineItem] = []
        var inFence = false
        var openMarker: Character?

        let lines = markdown.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)

        for (index, substring) in lines.enumerated() {
            let line = String(substring)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let marker = fenceMarker(of: trimmed) {
                if inFence {
                    if marker == openMarker { inFence = false; openMarker = nil }
                } else {
                    inFence = true
                    openMarker = marker
                }
                continue
            }
            if inFence { continue }

            guard let (level, title) = parseATXHeading(line) else { continue }
            items.append(OutlineItem(level: level, title: title, line: index))
        }

        return items
    }

    /// 펜스 여닫는 줄인지 판별: ``` 또는 ~~~(3개 이상)로 시작. 마커 문자를 반환한다.
    private static func fenceMarker(of trimmedLine: String) -> Character? {
        if trimmedLine.hasPrefix("```") { return "`" }
        if trimmedLine.hasPrefix("~~~") { return "~" }
        return nil
    }

    /// `^#{1,6} ` 만 헤딩으로 인정한다. 마커 뒤에 공백이 없으면(`#5` 등) 헤딩이 아니다.
    private static func parseATXHeading(_ line: String) -> (level: Int, title: String)? {
        guard line.hasPrefix("#") else { return nil }

        var hashCount = 0
        for char in line {
            if char == "#" { hashCount += 1 } else { break }
        }
        guard hashCount >= 1, hashCount <= 6 else { return nil }

        let afterHashes = line.dropFirst(hashCount)
        guard afterHashes.first == " " else { return nil }

        let rest = afterHashes.dropFirst().trimmingCharacters(in: .whitespaces)
        let title = stripTrailingHashes(rest)
        return (hashCount, title)
    }

    /// 후행 닫는 해시 시퀀스 제거: `"Section ##"` → `"Section"`. 최소 1개 공백이 앞에 있어야
    /// 유효한 닫힘으로 인정한다(공백 없이 붙은 `#` 은 제목의 일부로 남긴다).
    private static func stripTrailingHashes(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\s+#+\s*$"#) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }
}
