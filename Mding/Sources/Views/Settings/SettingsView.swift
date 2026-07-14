import SwiftUI

/// 설정 창(⌘,, Settings Scene 이 자동 부여) — Appearance/Editor/Paths 섹션 (§4.6/§4.8).
/// 창 자체는 표준 `Form`, 컨트롤에만 절제된 Liquid Glass 를 쓰는 것이 원칙이나 이 창은
/// Picker/Stepper/TextField 등 시스템 컨트롤로만 구성되어 별도 glass 처리가 필요 없다.
struct SettingsView: View {
    @Bindable private var settings = AppSettings.shared
    @State private var isDefaultHandler = false
    @State private var currentHandlerName: String?

    var body: some View {
        Form {
            Section {
                Picker(selection: $settings.theme) {
                    Text("System", comment: "Theme option that follows the system appearance").tag(AppTheme.system)
                    Text("Light", comment: "Theme option that is always light").tag(AppTheme.light)
                    Text("Dark", comment: "Theme option that is always dark").tag(AppTheme.dark)
                } label: {
                    Text("Theme", comment: "Settings picker label for choosing the app's appearance theme")
                }
                .pickerStyle(.segmented)
                .onChange(of: settings.theme) { _, newTheme in
                    ThemeManager.apply(newTheme)
                }
            } header: {
                Text("Appearance", comment: "Settings section header for appearance options")
            }

            Section {
                Stepper(value: $settings.editorFontSize, in: AppSettings.editorFontSizeRange, step: 1) {
                    HStack {
                        Text("Font Size", comment: "Settings label for the editor font size")
                        Spacer()
                        Text(settings.editorFontSize, format: .number.precision(.fractionLength(0)))
                            .foregroundStyle(.secondary)
                    }
                }

                Picker(selection: $settings.tabIndentWidth) {
                    Text("2", comment: "Tab width option: 2 spaces per tab").tag(2)
                    Text("4", comment: "Tab width option: 4 spaces per tab").tag(4)
                    Text("8", comment: "Tab width option: 8 spaces per tab").tag(8)
                } label: {
                    Text("Tab Width", comment: "Settings picker label for the number of spaces inserted per tab")
                }

                Picker(selection: $settings.defaultViewMode) {
                    ForEach(ViewMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                } label: {
                    Text("Default View Mode", comment: "Settings picker label for which view mode new tabs open in")
                }
            } header: {
                Text("Editor", comment: "Settings section header for editor options")
            }

            Section {
                Picker(selection: $settings.relativePathBase) {
                    Text("Git Root", comment: "Relative path base option: the nearest Git repository root").tag(RelativePathBase.gitRoot)
                    Text("Home", comment: "Relative path base option: the user's home directory").tag(RelativePathBase.home)
                    Text("Custom", comment: "Relative path base option: a user-specified directory").tag(RelativePathBase.custom)
                } label: {
                    Text("Relative Path Base", comment: "Settings picker label for the base directory used when copying a relative path")
                }

                if settings.relativePathBase == .custom {
                    TextField(
                        text: $settings.customRelativeBasePath,
                        prompt: Text(verbatim: "/path/to/base")
                    ) {
                        Text("Custom Path", comment: "Settings text field label for the custom relative path base directory")
                    }
                }
            } header: {
                Text("Paths", comment: "Settings section header for path-copying options")
            }

            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Default Markdown App", comment: "Settings label for making Mding the default app for .md files")
                        if isDefaultHandler {
                            Text("Mding is the default app for Markdown files", comment: "Settings caption shown when Mding is already the default Markdown app")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if let currentHandlerName {
                            Text("Current default: \(currentHandlerName)", comment: "Settings caption showing which app currently opens Markdown files")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Button {
                        setAsDefaultApp()
                    } label: {
                        Text("Set as Default", comment: "Settings button that makes Mding the default app for Markdown files")
                    }
                    .disabled(isDefaultHandler)
                }
            } header: {
                Text("Files", comment: "Settings section header for file handling options")
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, minHeight: 340)
        .preferredColorScheme(settings.theme.colorScheme)
        .onAppear(perform: refreshDefaultHandlerStatus)
    }

    private func refreshDefaultHandlerStatus() {
        isDefaultHandler = DefaultAppService.isCurrentHandler()
        currentHandlerName = DefaultAppService.currentHandlerName()
    }

    private func setAsDefaultApp() {
        Task {
            try? await DefaultAppService.setAsDefault()
            refreshDefaultHandlerStatus()
        }
    }
}
