import SwiftUI

/// 문서 아웃라인(TOC) 사이드바 — NavigationSplitView 의 사이드바 칼럼(창 전체 높이,
/// 시스템 머티리얼 배경, 폭은 칼럼이 관리). 헤딩 계층 목록만 담는다(파일명은 detail 툴바에 있음).
/// 항목 클릭 시 `OutlineNavigator` 가 프리뷰/에디터를 동시에 해당 헤딩으로 스크롤한다.
struct OutlineSidebarView: View {
    @Bindable var document: DocumentViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                if document.outline.isEmpty {
                    Text("No Headings", comment: "Placeholder shown in the outline sidebar when the document has no headings")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                } else {
                    ForEach(document.outline) { item in
                        row(for: item)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(for item: OutlineItem) -> some View {
        Button {
            OutlineNavigator.jump(to: item, in: document)
        } label: {
            Text(item.title)
                .font(.callout)
                .fontWeight(item.level == 1 ? .semibold : .regular)
                .foregroundStyle(item.level == 1 ? .primary : .secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, CGFloat(item.level - 1) * 12)
                .padding(.vertical, 3)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
