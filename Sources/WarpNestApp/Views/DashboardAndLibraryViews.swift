import SwiftUI
import WarpCore

/// Screen 4: Overview Dashboard
struct DashboardView: View {
    @Bindable var state: WarpAppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(
                    title: "Overview Dashboard",
                    subtitle: "Live runtime, Windows environment, and SteamBridge status.",
                    badge: (state.runtimeReport?.isHealthy == true ? "RUNTIME READY" : "CHECK RUNTIME", state.runtimeReport?.isHealthy == true ? WarpTheme.verifiedGreen : WarpTheme.warningAmber)
                )

                // Summary KPI Row (100% real counts, no invented metrics)
                HStack(spacing: 14) {
                    kpiCard(title: "Hardware", value: state.systemDiagnostics.isAppleSilicon ? "Apple Silicon" : "x86_64", detail: "\(state.systemDiagnostics.totalMemoryGigabytes) GB RAM", accent: WarpTheme.violet)
                    kpiCard(title: "Environments", value: "\(state.bottles.count)", detail: "Active: \(state.activeBottle?.name ?? "None")", accent: WarpTheme.electricBlue)
                    kpiCard(title: "Steam Client", value: state.steamInstalled ? "Installed" : "Not Installed", detail: state.activeSteamPID.map { "PID \($0)" } ?? "Idle", accent: state.steamInstalled ? WarpTheme.verifiedGreen : WarpTheme.warningAmber)
                    kpiCard(title: "Installed Games", value: "\(state.installedGames.count)", detail: "Discovered via ACF", accent: WarpTheme.violet)
                }

                // Quick Actions
                WarpCard(title: "Quick Actions", subtitle: "Connected directly to WarpEngine & SteamSessionController") {
                    HStack(spacing: 10) {
                        Button(state.steamInstalled ? "Launch Steam" : "Install Steam") {
                            if state.steamInstalled {
                                state.launchSteam()
                            } else {
                                state.installSteam()
                            }
                        }
                        .buttonStyle(WarpPrimaryButtonStyle())

                        if state.activeSteamPID != nil {
                            Button("Stop Active Session") {
                                state.stopActiveSession()
                            }
                            .buttonStyle(WarpPrimaryButtonStyle(color: WarpTheme.blockedRed))
                        }

                        Button("Run 13-Step Verify") {
                            state.runVerificationLadder()
                            state.selectedScreen = .diagnostics
                        }
                        .buttonStyle(WarpSecondaryButtonStyle())

                        Button("Refresh State") {
                            Task { await state.refreshAll() }
                        }
                        .buttonStyle(WarpSecondaryButtonStyle())
                    }
                }

                // SteamBridge Diagnostic Snapshot
                if let diag = state.steamDiagnosticReport {
                    WarpCard(title: "SteamBridge Telemetry [\(diag.bottleName)]", subtitle: diag.networkReport.summary) {
                        VStack(spacing: 4) {
                            MetadataRow("DNS64 / NAT64", value: diag.networkReport.isDNS64Detected ? "Detected (64:ff9b::)" : "Not Detected")
                            MetadataRow("CEF GPU Crashes", value: "\(diag.healthSnapshot.gpuCrashCount)")
                            MetadataRow("CEF Flag Forwarding", value: diag.forwardingReport.allExpectedForwarded ? "OK" : "Missing: \(diag.forwardingReport.missingFlags.joined(separator: ", "))")
                            MetadataRow("UI DLL Overrides", value: diag.recommendedProfile.wineDLLOverridesString, monospaced: true)
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(WarpTheme.midnight)
    }

    private func kpiCard(title: String, value: String, detail: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(WarpTheme.mutedText)
            Text(value)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(WarpTheme.primaryText)
                .lineLimit(1)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(accent)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WarpTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: WarpTheme.cornerRadius)
                .stroke(WarpTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: WarpTheme.cornerRadius))
    }
}

/// Screen 5: Unified Game Library
struct GameLibraryView: View {
    @Bindable var state: WarpAppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                ScreenHeader(
                    title: "Unified Game Library",
                    subtitle: "Discovered read-only from Steam appmanifest_*.acf in \(state.activeBottle?.name ?? "selected bottle")."
                )
                TextField("Search games or AppID...", text: $state.searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)

            if state.activeBottle == nil {
                WarpStateView(
                    icon: "shippingbox",
                    title: "No Windows Environment Selected",
                    message: "Create or select a Windows environment in Windows Environments before inspecting installed games.",
                    actionTitle: "Go to Environments"
                ) {
                    state.selectedScreen = .environments
                }
            } else if !state.steamInstalled {
                WarpStateView(
                    icon: "tray.and.arrow.down",
                    title: "Windows Steam Not Installed",
                    message: "Install the official Windows Steam client in '\(state.activeBottle?.name ?? "")' to download and discover your Steam library.",
                    tint: WarpTheme.warningAmber,
                    actionTitle: "Go to Connected Platforms"
                ) {
                    state.selectedScreen = .platforms
                }
            } else if state.filteredGames.isEmpty {
                WarpStateView(
                    icon: "gamecontroller",
                    title: state.installedGames.isEmpty ? "No Installed Games Found" : "No Matching Games",
                    message: state.installedGames.isEmpty
                        ? "Launch Windows Steam to sign in manually and install a legitimately owned game."
                        : "Try clearing your search filter.",
                    actionTitle: state.installedGames.isEmpty ? "Launch Steam" : "Clear Search"
                ) {
                    if state.installedGames.isEmpty {
                        state.launchSteam()
                    } else {
                        state.searchQuery = ""
                    }
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                        ForEach(state.filteredGames) { game in
                            Button {
                                state.selectedGame = game
                                state.selectedScreen = .gameDetails
                            } label: {
                                gameCard(game)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
        }
        .background(WarpTheme.midnight)
    }

    private func gameCard(_ game: SteamGame) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("STEAM APP \(game.appId)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(WarpTheme.electricBlue)
                Spacer()
                if game.isFullyInstalled {
                    StatusPill("INSTALLED", color: WarpTheme.verifiedGreen)
                } else if game.isDownloading {
                    StatusPill("\(Int(game.downloadProgress * 100))%", color: WarpTheme.warningAmber)
                } else {
                    StatusPill("INCOMPLETE", color: WarpTheme.blockedRed)
                }
            }

            Text(game.name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WarpTheme.primaryText)
                .lineLimit(2)

            let sizeGB = Double(game.sizeOnDisk) / (1024 * 1024 * 1024)
            Text(String(format: "%.2f GB · Build %@", sizeGB, game.buildId.isEmpty ? "Unknown" : game.buildId))
                .font(.system(size: 11))
                .foregroundStyle(WarpTheme.mutedText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WarpTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: WarpTheme.cornerRadius)
                .stroke(WarpTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: WarpTheme.cornerRadius))
    }
}

/// Screen 6: Game Details
/// Enforces: Never display a Play button for a nonexistent installation; never display invented FPS or compatibility scores.
struct GameDetailsView: View {
    @Bindable var state: WarpAppState
    @State private var selectedGameBackend: GraphicsEngineType = .dxvk

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let game = state.selectedGame {
                    let dirExists = FileManager.default.fileExists(atPath: game.gameDirectoryURL.path)
                    let canPlay = game.isFullyInstalled && dirExists && state.steamInstalled

                    ScreenHeader(
                        title: game.name,
                        subtitle: "Steam AppID \(game.appId) · Build \(game.buildId.isEmpty ? "Unknown" : game.buildId)",
                        badge: (canPlay ? "READY TO LAUNCH" : (game.isDownloading ? "DOWNLOADING" : "UNAVAILABLE"), canPlay ? WarpTheme.verifiedGreen : WarpTheme.warningAmber)
                    )

                    // Action Bar — Play button ONLY shown when installation is genuinely verified on disk
                    WarpCard {
                        HStack(spacing: 12) {
                            if canPlay {
                                Button("Play via Steam") {
                                    state.launchSteam(appId: game.appId)
                                }
                                .buttonStyle(WarpPrimaryButtonStyle())
                            } else {
                                StatusPill("PLAY UNAVAILABLE — INSTALLATION INCOMPLETE", color: WarpTheme.blockedRed)
                            }

                            if state.activeSteamPID != nil {
                                Button("Stop Session") {
                                    state.stopActiveSession()
                                }
                                .buttonStyle(WarpPrimaryButtonStyle(color: WarpTheme.blockedRed))
                            }

                            Spacer()

                            Button("Back to Library") {
                                state.selectedScreen = .library
                            }
                            .buttonStyle(WarpSecondaryButtonStyle())
                        }
                    }

                    WarpCard(title: "Verified Game Metadata", subtitle: "Read directly from appmanifest_\(game.appId).acf") {
                        VStack(spacing: 4) {
                            MetadataRow("Platform", value: "Windows (Steam Client)")
                            MetadataRow("Installation Status", value: game.isFullyInstalled ? (dirExists ? "Fully Installed" : "Manifest Present (Directory Missing)") : "Incomplete / Downloading")
                            MetadataRow("Runtime Version", value: state.runtimeReport?.wineVersion ?? "Unknown", monospaced: true)
                            MetadataRow("Graphics Backend", value: selectedGameBackend.rawValue)
                            MetadataRow("Compatibility Evidence", value: "No invented FPS/scores; verify live via Diagnostics after launch.")
                            let mb = Double(game.sizeOnDisk) / (1024 * 1024)
                            MetadataRow("Storage Requirement", value: String(format: "%.1f MB on disk", mb))
                            MetadataRow("Install Directory", value: game.gameDirectoryURL.path, monospaced: true)
                            MetadataRow("Manifest File", value: game.manifestURL.path, monospaced: true)
                        }
                    }

                    WarpCard(title: "Per-Game Graphics Backend", subtitle: "Applies transactional x64+x32 DLL deployment while keeping Steam UI isolated on WineD3D.") {
                        HStack(spacing: 12) {
                            Picker("Backend", selection: $selectedGameBackend) {
                                Text("DXVK (Vulkan -> MoltenVK)").tag(GraphicsEngineType.dxvk)
                                Text("DXMT (Direct Metal)").tag(GraphicsEngineType.dxmt)
                                Text("WineD3D (Builtin)").tag(GraphicsEngineType.wined3d)
                            }
                            .pickerStyle(.segmented)

                            Button("Apply Backend") {
                                state.changeGraphicsBackend(selectedGameBackend, forAppId: game.appId)
                            }
                            .buttonStyle(WarpPrimaryButtonStyle(color: WarpTheme.electricBlue))
                        }
                    }
                    .onAppear {
                        if let saved = state.persistence.getGameBackendOverride(appId: game.appId),
                           let parsed = GraphicsEngineType(rawValue: saved) {
                            selectedGameBackend = parsed
                        }
                    }
                } else {
                    WarpStateView(
                        icon: "info.circle",
                        title: "No Game Selected",
                        message: "Select an installed game from the Unified Game Library to inspect its metadata and launch controls.",
                        actionTitle: "Open Game Library"
                    ) {
                        state.selectedScreen = .library
                    }
                }
            }
            .padding(24)
        }
        .background(WarpTheme.midnight)
    }
}
