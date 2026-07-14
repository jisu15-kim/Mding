import SwiftUI
import UniformTypeIdentifiers

/// 커스텀 탭 바 (§4.1). 앱 크롬이므로 Liquid Glass 를 적용한다 (§4.8 — 콘텐츠엔 금지).
struct TabBarView: View {
    @Bindable var window: WindowViewModel

    var body: some View {
        GlassContainer(spacing: 6) {
            HStack(spacing: 6) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(window.tabs) { tab in
                            TabItemView(
                                tab: tab,
                                isSelected: tab.id == window.selectedTabID,
                                select: { window.selectTab(tab.id) },
                                close: { window.closeTab(tab.id) }
                            )
                            .onDrag {
                                TabDragContext.shared.begin(tab: tab, source: window)
                                return NSItemProvider(object: tab.id.uuidString as NSString)
                            }
                            .onDrop(
                                of: [.text],
                                delegate: TabDropDelegate(item: tab, window: window)
                            )
                        }
                    }
                }

                Button {
                    window.newTab()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 20, height: 20)
                }
                .glassButtonStyle()
                .help(Text("New Tab", comment: "Tooltip for the button that opens a new tab"))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            // 탭바 빈 영역(스크롤뷰 여백/plus 버튼 주변) 드롭 — 탭 아이템 위는 위의 onDrop 이 우선 처리한다.
            .onDrop(of: [.text], delegate: TabBarBackgroundDropDelegate(window: window))
        }
    }
}

/// 같은 윈도우 내 재정렬(hover 즉시) + 다른 윈도우 탭의 이동(drop 확정 시점)을 처리한다 (§4.1, 윈도우 간 탭 드래그 확장).
private struct TabDropDelegate: DropDelegate {
    let item: DocumentViewModel
    let window: WindowViewModel

    func validateDrop(info: DropInfo) -> Bool {
        TabDragContext.shared.dragging != nil
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func dropEntered(info: DropInfo) {
        guard let dragging = TabDragContext.shared.dragging, dragging.source === window,
              dragging.tab.id != item.id,
              let from = window.tabs.firstIndex(where: { $0.id == dragging.tab.id }),
              let to = window.tabs.firstIndex(where: { $0.id == item.id })
        else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            window.moveTab(from: IndexSet(integer: from), to: to > from ? to + 1 : to)
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        defer { TabDragContext.shared.end() }
        guard let dragging = TabDragContext.shared.dragging else { return false }

        if dragging.source === window {
            // 같은 윈도우: dropEntered 에서 이미 재정렬이 적용됐다.
            return true
        }

        let insertIdx = window.tabs.firstIndex(where: { $0.id == item.id })
        window.adoptTab(dragging.tab, from: dragging.source, at: insertIdx)
        return true
    }
}

/// 탭바 빈 영역 드롭 — 같은 윈도우면 맨 뒤로 재정렬, 다른 윈도우면 맨 뒤에 append (§4.1 확장).
private struct TabBarBackgroundDropDelegate: DropDelegate {
    let window: WindowViewModel

    func validateDrop(info: DropInfo) -> Bool {
        TabDragContext.shared.dragging != nil
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        defer { TabDragContext.shared.end() }
        guard let dragging = TabDragContext.shared.dragging else { return false }

        if dragging.source === window {
            guard let from = window.tabs.firstIndex(where: { $0.id == dragging.tab.id }) else { return false }
            withAnimation(.easeInOut(duration: 0.15)) {
                window.moveTab(from: IndexSet(integer: from), to: window.tabs.count)
            }
        } else {
            window.adoptTab(dragging.tab, from: dragging.source, at: nil)
        }
        return true
    }
}
