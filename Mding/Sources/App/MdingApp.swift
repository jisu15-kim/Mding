import SwiftUI

@main
struct MdingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            WindowRootView()
        }
        .commands {
            UpdateCommands()
            FileCommands()
            FindCommands()
            TabCommands()
            FormatCommands()
            ViewCommands()
        }

        Settings {
            SettingsView()
        }
    }
}

/// File 메뉴: New Tab, Open, Open Recent, Save. New Window(⌘N)은 WindowGroup 기본 제공.
struct FileCommands: Commands {
    @FocusedValue(\.activeWindow) private var activeWindow
    @FocusedValue(\.activeDocument) private var activeDocument

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button {
                activeWindow?.newTab()
            } label: {
                Text("New Tab", comment: "File menu item that opens a new tab")
            }
            .keyboardShortcut("t", modifiers: .command)
            .disabled(activeWindow == nil)

            Button {
                openDocument()
            } label: {
                Text("Open…", comment: "File menu item that opens a Markdown file")
            }
            .keyboardShortcut("o", modifiers: .command)
            .disabled(activeWindow == nil)

            openRecentMenu
        }
        CommandGroup(after: .saveItem) {
            Button {
                activeDocument?.saveDocument()
            } label: {
                Text("Save", comment: "File menu item that saves the current document")
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(activeDocument == nil || activeDocument?.mode != .editor)

            exportMenu

            Button {
                activeDocument?.copyAbsolutePath()
            } label: {
                Text("Copy Path", comment: "File menu item that copies the absolute path of the current document")
            }
            .keyboardShortcut("c", modifiers: [.command, .option])
            .disabled(activeDocument?.fileURL == nil)

            Button {
                activeDocument?.copyRelativePath()
            } label: {
                Text("Copy Relative Path", comment: "File menu item that copies the path of the current document relative to the Git root or home directory")
            }
            .keyboardShortcut("c", modifiers: [.command, .option, .shift])
            .disabled(activeDocument?.fileURL == nil)
        }
    }

    private var openRecentMenu: some View {
        Menu {
            let recents = NSDocumentController.shared.recentDocumentURLs
            if recents.isEmpty {
                Button {
                } label: {
                    Text("No Recent Files", comment: "Placeholder shown when the Open Recent menu is empty")
                }
                .disabled(true)
            } else {
                ForEach(recents, id: \.self) { url in
                    Button {
                        activeWindow?.openFile(url: url)
                    } label: {
                        Text(verbatim: url.lastPathComponent)
                    }
                }
                Divider()
                Button {
                    NSDocumentController.shared.clearRecentDocuments(nil)
                } label: {
                    Text("Clear Menu", comment: "Open Recent menu item that clears the recent files list")
                }
            }
        } label: {
            Text("Open Recent", comment: "File submenu listing recently opened files")
        }
        .disabled(activeWindow == nil)
    }

    private func openDocument() {
        guard let activeWindow, let url = FileService.presentOpenPanel() else { return }
        activeWindow.openFile(url: url)
    }

    /// Export ▸ PDF / HTML — 라이트 테마 고정 렌더링 후 저장(ExportService). v1 은 단축키 없음.
    private var exportMenu: some View {
        Menu {
            Button {
                exportAsPDF()
            } label: {
                Text("Export as PDF…", comment: "Export submenu item that saves the current document as a PDF file")
            }
            .disabled(activeDocument == nil || activeDocument?.mode != .editor)

            Button {
                exportAsHTML()
            } label: {
                Text("Export as HTML…", comment: "Export submenu item that saves the current document as a standalone HTML file")
            }
            .disabled(activeDocument == nil || activeDocument?.mode != .editor)
        } label: {
            Text("Export", comment: "File menu submenu that contains PDF/HTML export actions")
        }
    }

    private func exportAsPDF() {
        guard let activeDocument else { return }
        ExportService.exportAsPDF(activeDocument)
    }

    private func exportAsHTML() {
        guard let activeDocument else { return }
        ExportService.exportAsHTML(activeDocument)
    }
}

/// Edit 메뉴 Find 서브메뉴 (§4.3) — 편집기/프리뷰 공용 통합 찾기(FindSession).
/// SwiftUI 앱은 NSTextView 용 표준 Find 메뉴를 자동 제공하지 않으므로 직접 배선한다.
struct FindCommands: Commands {
    @FocusedValue(\.activeDocument) private var activeDocument

    /// Welcome 탭에는 찾을 대상이 없다 — 문서가 에디터 상태일 때만 활성.
    private var enabled: Bool { activeDocument?.mode == .editor }

    var body: some Commands {
        // 표준 관례대로 Edit 메뉴에 Find 서브메뉴를 둔다. 항목을 직접 배치해 문서 유무와 무관하게
        // 항상 노출되도록 한다(문서가 없을 때는 비활성).
        CommandGroup(after: .pasteboard) {
            Divider()
            Menu {
                Button {
                    activeDocument?.find.activate()
                } label: {
                    Text("Find…", comment: "Edit menu item that opens the find bar")
                }
                .keyboardShortcut("f", modifiers: .command)

                Button {
                    activeDocument?.find.next()
                } label: {
                    Text("Find Next", comment: "Edit menu item that jumps to the next search match")
                }
                .keyboardShortcut("g", modifiers: .command)

                Button {
                    activeDocument?.find.previous()
                } label: {
                    Text("Find Previous", comment: "Edit menu item that jumps to the previous search match")
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])

                Button {
                    activeDocument?.find.useSelection()
                } label: {
                    Text("Use Selection for Find", comment: "Edit menu item that searches for the currently selected text")
                }
                .keyboardShortcut("e", modifiers: .command)
            } label: {
                Text("Find", comment: "Edit menu submenu that groups the find commands")
            }
            .disabled(!enabled)
        }
    }
}

/// 표준 Window 메뉴에 탭 네비게이션을 추가 (§4.1). ⌃Tab / ⌃⇧Tab / ⌘1…⌘9.
struct TabCommands: Commands {
    @FocusedValue(\.activeWindow) private var activeWindow

    private var hasMultipleTabs: Bool { (activeWindow?.tabs.count ?? 0) > 1 }

    var body: some Commands {
        CommandGroup(after: .windowArrangement) {
            Button {
                activeWindow?.selectNextTab()
            } label: {
                Text("Show Next Tab", comment: "Window menu item that selects the next tab")
            }
            .keyboardShortcut(.tab, modifiers: .control)
            .disabled(!hasMultipleTabs)

            Button {
                activeWindow?.selectPreviousTab()
            } label: {
                Text("Show Previous Tab", comment: "Window menu item that selects the previous tab")
            }
            .keyboardShortcut(.tab, modifiers: [.control, .shift])
            .disabled(!hasMultipleTabs)

            Divider()

            // ⌘1~9 는 뷰 모드 전환(ViewCommands)이 차지 — 탭 점프는 ⌘⌥1~9 (⌘⌥←/→ 와 일관).
            ForEach(1...9, id: \.self) { number in
                Button {
                    activeWindow?.selectTab(at: number - 1)
                } label: {
                    Text("Tab \(number)", comment: "Window menu item that jumps to the Nth tab")
                }
                .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: [.command, .option])
                .disabled(number > (activeWindow?.tabs.count ?? 0))
            }
        }
    }
}

/// View 메뉴: 뷰 모드 전환(⌘1/2/3) + 아웃라인(TOC) 사이드바 토글(⌃⌘S, macOS 표준).
struct ViewCommands: Commands {
    @FocusedValue(\.activeDocument) private var activeDocument

    /// Welcome 탭에서는 뷰 모드가 없다 — 문서가 에디터 상태일 때만 활성.
    private var canSwitchViewMode: Bool { activeDocument?.mode == .editor }

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            // 라벨은 뷰 모드 토글과 같은 문자열(ViewMode.label) 재사용. 순서도 토글 노출 순서와 동일.
            Button {
                activeDocument?.viewMode = .preview
            } label: {
                Text(ViewMode.preview.label)
            }
            .keyboardShortcut("1", modifiers: .command)
            .disabled(!canSwitchViewMode)

            Button {
                activeDocument?.viewMode = .editor
            } label: {
                Text(ViewMode.editor.label)
            }
            .keyboardShortcut("2", modifiers: .command)
            .disabled(!canSwitchViewMode)

            Button {
                activeDocument?.viewMode = .split
            } label: {
                Text(ViewMode.split.label)
            }
            .keyboardShortcut("3", modifiers: .command)
            .disabled(!canSwitchViewMode)

            Divider()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    AppSettings.shared.showOutline.toggle()
                }
            } label: {
                if AppSettings.shared.showOutline {
                    Text("Hide Outline", comment: "View menu item that hides the document outline sidebar")
                } else {
                    Text("Show Outline", comment: "View menu item that shows the document outline sidebar")
                }
            }
            .keyboardShortcut("s", modifiers: [.control, .command])

            // 전체 너비(§전체너비): 프리뷰 본문 칼럼 상한(980px)을 풀어 창 폭을 쓴다. 문서별 설정.
            Button {
                activeDocument?.togglePreviewFullWidth()
            } label: {
                if activeDocument?.previewFullWidth == true {
                    Text("Standard Width", comment: "View menu item that restores the fixed-width preview column")
                } else {
                    Text("Full Width", comment: "View menu item that expands the preview to the full window width")
                }
            }
            .keyboardShortcut("l", modifiers: [.control, .command])
            .disabled(!canSwitchViewMode)

            Divider()

            // 글자 크기: 에디터 폰트 + 프리뷰 zoom(pageZoom = fontSize/기본값)이 함께 움직인다.
            // "+" 는 US 배열에서 ⇧⌘= 가 되므로 관례대로 ⌘= 에 바인딩한다.
            Button {
                AppSettings.shared.adjustEditorFontSize(by: 1)
            } label: {
                Text("Increase Font Size", comment: "View menu item that makes the editor and preview text larger")
            }
            .keyboardShortcut("=", modifiers: .command)

            Button {
                AppSettings.shared.adjustEditorFontSize(by: -1)
            } label: {
                Text("Decrease Font Size", comment: "View menu item that makes the editor and preview text smaller")
            }
            .keyboardShortcut("-", modifiers: .command)

            Button {
                AppSettings.shared.editorFontSize = AppSettings.defaultEditorFontSize
            } label: {
                Text("Reset Font Size", comment: "View menu item that restores the default text size")
            }
            .keyboardShortcut("0", modifiers: .command)
        }
    }
}

/// Format 메뉴 — first responder 라우팅(NSApp.sendAction). 에디터 미포커스 시 비활성 (§4.3).
struct FormatCommands: Commands {
    @FocusedValue(\.editorHasFocus) private var editorHasFocus

    private var enabled: Bool { editorHasFocus ?? false }

    var body: some Commands {
        CommandMenu(Text("Format", comment: "Format menu title")) {
            Button {
                NSApp.sendAction(#selector(EditorTextView.toggleBold(_:)), to: nil, from: nil)
            } label: {
                Text("Bold", comment: "Format menu item that toggles **bold**")
            }
            .keyboardShortcut("b", modifiers: .command)
            .disabled(!enabled)

            Button {
                NSApp.sendAction(#selector(EditorTextView.toggleItalic(_:)), to: nil, from: nil)
            } label: {
                Text("Italic", comment: "Format menu item that toggles _italic_")
            }
            .keyboardShortcut("i", modifiers: .command)
            .disabled(!enabled)

            Button {
                NSApp.sendAction(#selector(EditorTextView.toggleStrikethrough(_:)), to: nil, from: nil)
            } label: {
                Text("Strikethrough", comment: "Format menu item that toggles ~~strikethrough~~")
            }
            .keyboardShortcut("x", modifiers: [.command, .shift])
            .disabled(!enabled)

            Button {
                // ⌘⇧E — ⌘E 는 macOS 표준 "Use Selection for Find" 라 침범 금지 (§4.3).
                NSApp.sendAction(#selector(EditorTextView.toggleInlineCode(_:)), to: nil, from: nil)
            } label: {
                Text("Inline Code", comment: "Format menu item that toggles `inline code`")
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(!enabled)

            Divider()

            Button {
                NSApp.sendAction(#selector(EditorTextView.insertLink(_:)), to: nil, from: nil)
            } label: {
                Text("Add Link…", comment: "Format menu item that inserts a Markdown link with a URL prompt")
            }
            .keyboardShortcut("k", modifiers: .command)
            .disabled(!enabled)
        }
    }
}
