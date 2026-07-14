import SwiftUI

/// 탭 하나의 렌더: 제목 + dirty 점 / 닫기 버튼(hover) + 컨텍스트 메뉴.
struct TabItemView: View {
    let tab: DocumentViewModel
    let isSelected: Bool
    let select: () -> Void
    let close: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 6) {
            Text(tab.displayName)
                .lineLimit(1)
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? .primary : .secondary)

            trailingIndicator
                .frame(width: 14, height: 14)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(minWidth: 72, maxWidth: 220)
        .background {
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear))
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover { isHovering = $0 }
        .help(tab.fileURL?.path ?? tab.displayName)
        .contextMenu {
            Button {
                tab.copyAbsolutePath()
            } label: {
                Text("Copy Path", comment: "Tab context menu item that copies the file's absolute path")
            }
            .disabled(tab.fileURL == nil)

            Button {
                tab.copyRelativePath()
            } label: {
                Text("Copy Relative Path", comment: "Tab context menu item that copies the file's path relative to the Git root or home directory")
            }
            .disabled(tab.fileURL == nil)

            Button {
                tab.revealInFinder()
            } label: {
                Text("Open in Finder", comment: "Tab context menu item that reveals the file in Finder")
            }
            .disabled(tab.fileURL == nil)

            Divider()

            Button(role: .destructive, action: close) {
                Text("Close Tab", comment: "Tab context menu item that closes the tab")
            }
        }
    }

    @ViewBuilder
    private var trailingIndicator: some View {
        if isHovering {
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(Text("Close Tab", comment: "Tooltip for the tab close button"))
        } else if tab.isDirty {
            Circle()
                .fill(.secondary)
                .frame(width: 7, height: 7)
        }
    }
}
