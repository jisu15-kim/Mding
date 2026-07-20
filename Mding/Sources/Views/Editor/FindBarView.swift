import SwiftUI

/// 통합 찾기 바(⌘F) — 편집기/프리뷰 공용. 콘텐츠 상단(탭바 아래)에 나타난다.
/// 실제 검색은 `FindSession` 이 대상 뷰(NSTextView / WKWebView)로 구동한다.
struct FindBarView: View {
    @Bindable var find: FindSession
    @FocusState private var fieldFocused: Bool

    private var countLabel: String {
        if find.query.isEmpty { return "" }
        if find.matchCount == 0 {
            return String(localized: "No results", comment: "Find bar label shown when the search has no matches")
        }
        return "\(find.currentIndex)/\(find.matchCount)"
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 12, weight: .medium))

            TextField(
                text: $find.query,
                prompt: Text("Find", comment: "Placeholder of the find bar search field")
            ) {
                Text("Find", comment: "Accessibility label of the find bar search field")
            }
            .textFieldStyle(.plain)
            .focused($fieldFocused)
            .onSubmit { find.next() }
            .onChange(of: find.query) { find.queryDidChange() }
            .frame(minWidth: 160, maxWidth: 260)

            Text(countLabel)
                .foregroundStyle(.secondary)
                .font(.system(size: 11))
                .monospacedDigit()
                .frame(minWidth: 52, alignment: .trailing)

            Divider().frame(height: 14)

            Toggle(isOn: $find.caseSensitive) {
                Text(verbatim: "Aa")
                    .font(.system(size: 12, weight: .semibold))
            }
            .toggleStyle(.button)
            .buttonStyle(.borderless)
            .help(Text("Match Case", comment: "Tooltip of the find bar case-sensitivity toggle"))
            .onChange(of: find.caseSensitive) { find.caseSensitiveDidChange() }

            Button {
                find.previous()
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(find.matchCount == 0)
            .help(Text("Find Previous", comment: "Tooltip of the find bar previous-match button"))

            Button {
                find.next()
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(find.matchCount == 0)
            .help(Text("Find Next", comment: "Tooltip of the find bar next-match button"))

            Button {
                find.deactivate()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help(Text("Close Find Bar", comment: "Tooltip of the find bar close button"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial)
        .onAppear { fieldFocused = true }
        .onChange(of: find.focusRequest) { fieldFocused = true }
        .onExitCommand { find.deactivate() }
    }
}
