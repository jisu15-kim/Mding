import SwiftUI

/// 좌 에디터 / 우 프리뷰. (뷰 모드 토글/경로 메뉴 툴바는 크롬 높이 통일을 위해 WindowRootView 소유.)
struct SplitEditorView: View {
    @Bindable var document: DocumentViewModel
    @State private var editorFocused = false

    var body: some View {
        VStack(spacing: 0) {
            if document.find.isPresented {
                FindBarView(find: document.find)
                Divider()
            }
            HSplitView {
                if document.viewMode != .preview {
                    SourceEditorView(document: document, onFocusChange: { editorFocused = $0 })
                        .frame(minWidth: 200, maxWidth: .infinity, maxHeight: .infinity)
                }
                if document.viewMode != .editor {
                    PreviewWebView(document: document)
                        .frame(minWidth: 200, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            // 모드 전환마다 HSplitView 를 새로 만들어 Split 복귀 시 항상 50:50 으로 시작한다.
            // 에디터/웹뷰 인스턴스는 EditorViewCache/PreviewWebViewPool 이 문서 id 로 보존하므로
            // 재생성 비용은 재호스팅뿐이다.
            .id(document.viewMode)
        }
        // 소스 에디터 first-responder 여부를 Format 메뉴로 전달 (§4.3).
        .focusedSceneValue(\.editorHasFocus, editorFocused)
        .onChange(of: document.viewMode) { _, newMode in
            if newMode == .preview { editorFocused = false }
            // 대상(편집기/프리뷰)이 바뀌었을 수 있으니 새 대상에서 다시 하이라이트한다.
            document.find.modeDidChange()
        }
        .alert(
            Text("File Changed on Disk", comment: "Title of the conflict alert when the open file was modified externally"),
            isPresented: $document.hasExternalChangeConflict
        ) {
            Button {
                document.resolveConflictKeepingMine()
            } label: {
                Text("Keep My Changes", comment: "Conflict alert action: keep local edits")
            }
            Button {
                document.resolveConflictOverwriting()
            } label: {
                Text("Overwrite", comment: "Conflict alert action: overwrite the file on disk with local edits")
            }
            Button(role: .destructive) {
                document.resolveConflictReloading()
            } label: {
                Text("Reload From Disk", comment: "Conflict alert action: discard local edits and reload the file")
            }
        } message: {
            Text("The file was modified by another application.", comment: "Message of the external change conflict alert")
        }
    }
}
