import SwiftUI
import AppKit
import WarpCore

final class WarpAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct WarpNestApp: App {
    @NSApplicationDelegateAdaptor(WarpAppDelegate.self) var appDelegate
    @State private var appState = WarpAppState()

    var body: some Scene {
        WindowGroup("WarpNest") {
            WarpMainContentView(state: appState)
                .frame(minWidth: 1040, minHeight: 680)
                .preferredColorScheme(.dark)
                .task {
                    await appState.refreshAll()
                }
        }
        .defaultSize(width: 1260, height: 800)
        .commands {
            CommandMenu("WarpNest") {
                Button("Refresh State") {
                    Task { await appState.refreshAll() }
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Stop Active Session") {
                    appState.stopActiveSession()
                }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(appState.activeSteamPID == nil)

                Divider()

                Button("Overview Dashboard") { appState.selectedScreen = .dashboard }
                    .keyboardShortcut("1", modifiers: .command)
                Button("Game Library") { appState.selectedScreen = .library }
                    .keyboardShortcut("2", modifiers: .command)
                Button("Downloads & Queue") { appState.selectedScreen = .downloads }
                    .keyboardShortcut("3", modifiers: .command)
                Button("Windows Environments") { appState.selectedScreen = .environments }
                    .keyboardShortcut("4", modifiers: .command)
                Button("Compatibility Engines") { appState.selectedScreen = .engines }
                    .keyboardShortcut("5", modifiers: .command)
                Button("Diagnostics & Logs") { appState.selectedScreen = .diagnostics }
                    .keyboardShortcut("6", modifiers: .command)
            }
        }
    }
}

struct WarpMainContentView: View {
    @Bindable var state: WarpAppState

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(LinearGradient(colors: [WarpTheme.violet, WarpTheme.electricBlue], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 28, height: 28)
                        .overlay(
                            Image(systemName: "bolt.shield.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.white)
                        )
                    VStack(alignment: .leading, spacing: 1) {
                        Text("WarpNest")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(WarpTheme.primaryText)
                        Text("Apple Silicon Runtime")
                            .font(.system(size: 10))
                            .foregroundStyle(WarpTheme.mutedText)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)

                List(selection: $state.selectedScreen) {
                    Section("PLAY") {
                        sidebarRow(.dashboard)
                        sidebarRow(.library)
                        sidebarRow(.gameDetails)
                        sidebarRow(.downloads)
                    }
                    Section("COMPATIBILITY") {
                        sidebarRow(.environments)
                        sidebarRow(.engines)
                        sidebarRow(.platforms)
                        sidebarRow(.performance)
                    }
                    Section("SYSTEM") {
                        sidebarRow(.hardware)
                        sidebarRow(.runtimeWizard)
                        sidebarRow(.diagnostics)
                        sidebarRow(.onboarding)
                        sidebarRow(.preferences)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .background(WarpTheme.graphite)
            }
            .background(WarpTheme.graphite)
            .navigationSplitViewColumnWidth(min: 215, ideal: 235, max: 270)
        } detail: {
            VStack(spacing: 0) {
                if let err = state.bannerError {
                    bannerBar(text: err, color: WarpTheme.blockedRed) { state.bannerError = nil }
                } else if let notice = state.bannerNotice {
                    bannerBar(text: notice, color: WarpTheme.electricBlue) { state.bannerNotice = nil }
                }

                detailView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(WarpTheme.midnight)
        }
    }

    private func sidebarRow(_ screen: WarpScreen) -> some View {
        Label(screen.rawValue, systemImage: screen.icon)
            .font(.system(size: 12, weight: .medium))
            .tag(screen)
    }

    private func bannerBar(text: String, color: Color, dismiss: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(WarpTheme.primaryText)
                .lineLimit(2)
            Spacer()
            Button("Dismiss", action: dismiss)
                .buttonStyle(WarpSecondaryButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(color.opacity(0.16))
    }

    @ViewBuilder
    private var detailView: some View {
        switch state.selectedScreen {
        case .onboarding: OnboardingView(state: state)
        case .hardware: HardwareDetectionView(state: state)
        case .runtimeWizard: RuntimeWizardView(state: state)
        case .dashboard: DashboardView(state: state)
        case .library: GameLibraryView(state: state)
        case .gameDetails: GameDetailsView(state: state)
        case .downloads: DownloadsQueueView(state: state)
        case .engines: CompatibilityEngineView(state: state)
        case .environments: EnvironmentsView(state: state)
        case .diagnostics: DiagnosticsLogsView(state: state)
        case .performance: PerformanceSettingsView(state: state)
        case .platforms: PlatformsView(state: state)
        case .preferences: PreferencesView(state: state)
        }
    }
}
