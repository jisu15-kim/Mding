import Foundation

/// 문서 아웃라인(TOC) 사이드바의 헤딩 항목 하나 (ATX 헤딩 레벨 1~6).
/// `line` 은 0-based 소스 라인 인덱스로, `preview.html` 이 markdown-it 헤딩 토큰에서 뽑아내는
/// `token.map[0]` 과 정확히 일치해야 한다 — 클릭 시 프리뷰/에디터 점프(OutlineNavigator)가
/// 이 값으로 `data-line` 매칭 및 에디터 라인 오프셋 계산을 하기 때문. 헤딩은 항상 한 줄이라
/// `line` 은 항목 간 고유하므로 그대로 `id` 로 쓴다.
struct OutlineItem: Identifiable, Equatable {
    let level: Int
    let title: String
    let line: Int

    var id: Int { line }
}
