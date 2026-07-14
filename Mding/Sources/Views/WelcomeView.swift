import SwiftUI

/// VSCode 식 빈 탭 화면 (§4.1). New File / Open File 액션 + 최근 파일.
/// 파일을 열거나 드롭하면 **같은 탭**이 에디터로 전환된다(새 탭 생성 금지).
/// 버튼/컨트롤에만 Liquid Glass 적용, 배경·최근 목록(콘텐츠)에는 미적용 (§4.8).
struct WelcomeView: View {
    @Bindable var document: DocumentViewModel
    /// 최근 파일은 onAppear 에서 1회 조회해 캐시한다 (body 렌더마다 XPC 호출 방지).
    @State private var recents: [URL] = []

    var body: some View {
        VStack(spacing: 28) {
            header
            actions
            recentFiles
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 자체 배경 없음 — 크롬 통합 배경(WindowRootView.containerBackground)이 그대로 비친다.
        .onAppear {
            recents = Array(NSDocumentController.shared.recentDocumentURLs.prefix(6))
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: FileService.isMarkdownFile) else { return false }
            return openFocusingExisting(url)
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            // 실제 앱 아이콘(Assets 의 AppIcon)을 그대로 보여준다 — 심벌 플레이스홀더 대체.
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text(verbatim: "Mding")  // 앱 이름 — 번역 대상 아님
                .font(.largeTitle.weight(.semibold))
            Text("Just you and your Markdown.", comment: "Subtitle on the welcome screen")
                .foregroundStyle(.secondary)
        }
    }

    private var actions: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    document.startBlankDocument()
                } label: {
                    Label {
                        Text("New File", comment: "Welcome screen button that starts a blank untitled document")
                    } icon: {
                        Image(systemName: "square.and.pencil")
                    }
                }
                .buttonStyle(.glassProminent)

                Button(action: openFile) {
                    Label {
                        Text("Open File…", comment: "Welcome screen button that opens a file picker")
                    } icon: {
                        Image(systemName: "folder")
                    }
                }
                .buttonStyle(.glass)
            }
        }
    }

    @ViewBuilder
    private var recentFiles: some View {
        if !recents.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Recent", comment: "Header of the recent files list on the welcome screen")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                ForEach(recents, id: \.self) { url in
                    Button {
                        _ = openFocusingExisting(url)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.text")
                                .foregroundStyle(.secondary)
                            Text(url.lastPathComponent)
                            Text(url.deletingLastPathComponent().path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 380, alignment: .leading)
        }
    }

    private func openFile() {
        guard let url = FileService.presentOpenPanel() else { return }
        _ = openFocusingExisting(url)
    }

    /// 이미 열린 파일이면 기존 탭 포커스(중복 열기 방지), 아니면 이 Welcome 탭을 에디터로 전환.
    private func openFocusingExisting(_ url: URL) -> Bool {
        if WindowRegistry.shared.focusTab(for: url) { return true }
        return document.loadPresentingError(url: url)
    }
}
