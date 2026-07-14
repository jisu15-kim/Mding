import Combine
import Sparkle
import SwiftUI

/// Sparkle 업데이터 싱글턴. 최초 접근 시 자동 업데이트 체크 스케줄러가 함께 시작된다.
@MainActor
enum UpdaterService {
    static let controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
}

/// 앱 메뉴: Check for Updates… (체크 진행 중에는 비활성화).
struct UpdateCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .appInfo) {
            CheckForUpdatesButton()
        }
    }
}

private struct CheckForUpdatesButton: View {
    @State private var canCheckForUpdates = false

    var body: some View {
        Button {
            UpdaterService.controller.checkForUpdates(nil)
        } label: {
            Text("Check for Updates…", comment: "App menu item that checks for a new app version")
        }
        .disabled(!canCheckForUpdates)
        .onReceive(UpdaterService.controller.updater.publisher(for: \.canCheckForUpdates)) {
            canCheckForUpdates = $0
        }
    }
}
