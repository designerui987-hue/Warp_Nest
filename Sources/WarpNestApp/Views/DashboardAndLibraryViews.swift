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
                    subtitle: "Multi-platform catalog across Steam, Epic, GOG, Local Windows, and Native macOS."
                )
                TextField("Search title, store, or ID...", text: $state.searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)

            if state.filteredCanonicalGames.isEmpty {
                WarpStateView(
                    icon: "gamecontroller",
                    title: state.canonicalGames.isEmpty ? "No Installed Games Discovered" : "No Matching Games",
                    message: state.canonicalGames.isEmpty
                        ? "Connect a storefront in Connected Platforms or install a native macOS / Windows game."
                        : "Try clearing your search filter.",
                    actionTitle: state.canonicalGames.isEmpty ? "Open Connected Platforms" : "Clear Search"
                ) {
                    if state.canonicalGames.isEmpty {
                        state.selectedScreen = .platforms
                    } else {
                        state.searchQuery = ""
                    }
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 14)], spacing: 14) {
                        ForEach(state.filteredCanonicalGames) { game in
                            Button {
                                state.selectedCanonicalGame = game
                                state.selectedScreen = .gameDetails
                            } label: {
                                canonicalCard(game)
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

    private func canonicalCard(_ game: CanonicalGame) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(game.provider.rawValue.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(WarpTheme.electricBlue)
                Spacer()
                StatusPill(game.ownershipState.rawValue, color: game.ownershipState == .verifiedPlayable || game.ownershipState == .installed ? WarpTheme.verifiedGreen : WarpTheme.warningAmber)
            }

            Text(game.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WarpTheme.primaryText)
                .lineLimit(2)

            HStack {
                Text(game.edition)
                    .font(.system(size: 11))
                    .foregroundStyle(WarpTheme.mutedText)
                Spacer()
                StatusPill(status: game.compatibilityStatus)
            }
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
                if let game = state.selectedCanonicalGame {
                    let existsOnDisk = game.installURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
                    let canPlay = (game.ownershipState == .installed || game.ownershipState == .verifiedPlayable) && existsOnDisk

                    ScreenHeader(
                        title: game.title,
                        subtitle: "\(game.provider.rawValue) · \(game.edition) · ID \(game.storeAppId)",
                        badge: (canPlay ? "READY TO LAUNCH" : "UNAVAILABLE", canPlay ? WarpTheme.verifiedGreen : WarpTheme.warningAmber)
                    )

                    WarpCard {
                        HStack(spacing: 12) {
                            if canPlay {
                                Button("Play (\(game.provider.rawValue))") {
                                    state.launchCanonicalGame(game)
                                }
                                .buttonStyle(WarpPrimaryButtonStyle())
                            } else {
                                StatusPill("PLAY UNAVAILABLE — NOT INSTALLED ON DISK", color: WarpTheme.blockedRed)
                            }

                            if game.provider == .steam && state.activeSteamPID != nil {
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

                    WarpCard(title: "Canonical Game Metadata", subtitle: "Ownership and compatibility are tracked independently.") {
                        VStack(spacing: 4) {
                            MetadataRow("Storefront", value: game.provider.rawValue)
                            MetadataRow("Ownership State", value: game.ownershipState.rawValue)
                            MetadataRow("Compatibility Status", value: game.compatibilityStatus.rawValue)
                            MetadataRow("Runtime Requirement", value: game.runtimeRequirement)
                            MetadataRow("Version / Build", value: game.version ?? "Unknown", monospaced: true)
                            MetadataRow("Artwork Provenance", value: game.artworkProvenance)
                            MetadataRow("Install Location", value: game.installURL?.path ?? "Not installed locally", monospaced: true)
                            MetadataRow("Compatibility Evidence", value: "No invented FPS or scores; run Benchmark Laboratory or Diagnostics for live telemetry.")
                        }
                    }

                    if game.provider != .nativeMacOS {
                        WarpCard(title: "Per-Game Graphics Backend", subtitle: "Applies transactional x64+x32 DLL deployment while keeping Steam UI isolated on WineD3D.") {
                            HStack(spacing: 12) {
                                Picker("Backend", selection: $selectedGameBackend) {
                                    Text("DXVK (Vulkan -> MoltenVK)").tag(GraphicsEngineType.dxvk)
                                    Text("DXMT (Direct Metal)").tag(GraphicsEngineType.dxmt)
                                    Text("WineD3D (Builtin)").tag(GraphicsEngineType.wined3d)
                                }
                                .pickerStyle(.segmented)

                                Button("Apply Backend") {
                                    state.changeGraphicsBackend(selectedGameBackend, forAppId: game.storeAppId)
                                }
                                .buttonStyle(WarpPrimaryButtonStyle(color: WarpTheme.electricBlue))
                            }
                        }
                        .onAppear {
                            if let saved = state.persistence.getGameBackendOverride(appId: game.storeAppId),
                               let parsed = GraphicsEngineType(rawValue: saved) {
                                selectedGameBackend = parsed
                            }
                        }
                    }
                } else {
                    WarpStateView(
                        icon: "info.circle",
                        title: "No Game Selected",
                        message: "Select a game from the Unified Game Library to inspect its canonical metadata and launch controls.",
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
