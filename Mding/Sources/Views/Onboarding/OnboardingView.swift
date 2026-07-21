import SwiftUI

/// 최초 실행 온보딩 투어 (§온보딩) — Welcome → .md 기본 앱 지정 → 완료 3단계.
/// `AppSettings.hasCompletedOnboarding` 로 딱 한 번만 노출된다(끝까지 진행/도중 닫기 모두 완료 처리).
/// 기본 앱 지정은 Settings ▸ Files 섹션과 동일하게 `DefaultAppService` 를 재사용하고,
/// 노출·지정·완료·이탈을 `AnalyticsService` 로 계측한다.
struct OnboardingView: View {
    private enum Page: Int, CaseIterable {
        case welcome, defaultApp, done
    }

    @Environment(\.dismiss) private var dismiss
    @State private var page: Page = .welcome
    @State private var isDefaultHandler = false
    @State private var currentHandlerName: String?
    @State private var isSettingDefault = false
    /// 완료/이탈 계측·플래그 세팅을 한 번만 하기 위한 가드(dismiss → onDisappear 중복 방지).
    @State private var finishLogged = false

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 40)
                .padding(.top, 44)

            footer
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
        }
        .frame(width: 460, height: 470)
        .onAppear {
            refreshDefaultHandlerStatus()
            AnalyticsService.log(AnalyticsService.Event.onboardingShown)
        }
        // 버튼 없이(Esc·인터랙티브) 닫혀도 완료 처리 + 이탈 계측. finish 내부 가드로 이중 실행을 막는다.
        .onDisappear { finish(completed: false) }
    }

    // MARK: - Pages

    @ViewBuilder
    private var content: some View {
        switch page {
        case .welcome: welcomePage
        case .defaultApp: defaultAppPage
        case .done: donePage
        }
    }

    private var welcomePage: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 84, height: 84)
            VStack(spacing: 6) {
                Text("Welcome to Mding", comment: "Onboarding first page title")
                    .font(.system(size: 24, weight: .semibold))
                Text("Just you and your Markdown.", comment: "Onboarding first page tagline (matches the welcome screen subtitle)")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Text("A fast, focused Markdown editor with live preview.", comment: "Onboarding first page one-line description of what the app is")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var defaultAppPage: some View {
        VStack(spacing: 18) {
            Image(systemName: "doc.text")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
            VStack(spacing: 6) {
                Text("Open Markdown files in Mding", comment: "Onboarding default-app page title")
                    .font(.system(size: 20, weight: .semibold))
                    .multilineTextAlignment(.center)
                Text("Make Mding the default app for .md files so they open here every time.", comment: "Onboarding default-app page explanation of what setting the default does")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            defaultAppControl
                .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var defaultAppControl: some View {
        if isDefaultHandler {
            Label {
                Text("Mding is your default Markdown app", comment: "Onboarding caption shown when Mding is already the default Markdown app")
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
            .font(.system(size: 13))
        } else {
            VStack(spacing: 8) {
                Button {
                    setAsDefault()
                } label: {
                    Text("Set as Default", comment: "Onboarding button that makes Mding the default app for Markdown files")
                        .frame(maxWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isSettingDefault)

                if let currentHandlerName {
                    Text("Currently opens in \(currentHandlerName)", comment: "Onboarding caption showing which app currently opens Markdown files")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var donePage: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)
            VStack(spacing: 6) {
                Text("You're all set", comment: "Onboarding final page title")
                    .font(.system(size: 22, weight: .semibold))
                Text("Create a new file, open an existing one, or fine-tune things anytime in Settings (⌘,).", comment: "Onboarding final page hint about how to start using the app")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Footer (page dots + navigation)

    private var footer: some View {
        HStack {
            backButton
            Spacer()
            pageDots
            Spacer()
            nextButton
        }
    }

    @ViewBuilder
    private var backButton: some View {
        if page == .welcome {
            // 첫 페이지에는 Back 이 없지만, 도트·Next 위치가 흔들리지 않게 자리만 유지한다.
            Text("Back", comment: "Onboarding button that returns to the previous page").hidden()
        } else {
            Button {
                goTo(Page(rawValue: page.rawValue - 1) ?? .welcome)
            } label: {
                Text("Back", comment: "Onboarding button that returns to the previous page")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private var pageDots: some View {
        HStack(spacing: 7) {
            ForEach(Page.allCases, id: \.rawValue) { dot in
                Circle()
                    .fill(dot == page ? Color.primary.opacity(0.7) : Color.secondary.opacity(0.25))
                    .frame(width: 7, height: 7)
            }
        }
    }

    private var nextButton: some View {
        Button {
            if page == .done {
                finish(completed: true)
            } else {
                goTo(Page(rawValue: page.rawValue + 1) ?? .done)
            }
        } label: {
            if page == .done {
                Text("Get Started", comment: "Onboarding button on the final page that closes onboarding and starts using the app")
            } else {
                Text("Next", comment: "Onboarding button that advances to the next page")
            }
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
    }

    // MARK: - Actions

    private func goTo(_ target: Page) {
        withAnimation(.easeInOut(duration: 0.18)) { page = target }
    }

    private func refreshDefaultHandlerStatus() {
        isDefaultHandler = DefaultAppService.isCurrentHandler()
        currentHandlerName = DefaultAppService.currentHandlerName()
    }

    private func setAsDefault() {
        isSettingDefault = true
        Task {
            try? await DefaultAppService.setAsDefault()
            refreshDefaultHandlerStatus()
            isSettingDefault = false
            if isDefaultHandler {
                AnalyticsService.log(AnalyticsService.Event.onboardingSetDefault)
            }
        }
    }

    /// 완료 플래그를 세우고 시트를 닫는다. `completed` 로 완료/이탈을 구분해 계측한다.
    /// dismiss() 가 onDisappear 를 다시 부르므로 finishLogged 가드로 한 번만 실행한다.
    private func finish(completed: Bool) {
        guard !finishLogged else { return }
        finishLogged = true
        // 완료 상태(다시 안 뜸)는 외부 애널리틱스의 성공 여부와 무관해야 한다 — 플래그를 먼저 확정한다.
        AppSettings.shared.hasCompletedOnboarding = true
        AnalyticsService.log(completed
            ? AnalyticsService.Event.onboardingCompleted
            : AnalyticsService.Event.onboardingSkipped)
        dismiss()
    }
}
