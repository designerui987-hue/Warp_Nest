import SwiftUI
import WarpCore

/// Screen 10: Diagnostics & Crash Logs
struct DiagnosticsLogsView: View {
    @Bindable var state: WarpAppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(
                    title: "Diagnostics & Crash Logs",
                    subtitle: "13-step SteamVerificationLadder and sanitized execution logs."
                )

                WarpCard(title: "13-Step Steam Verification Ladder") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Button("Run Automated Ladder") {
                                state.runVerificationLadder()
                            }
                            .buttonStyle(WarpPrimaryButtonStyle())

                            Button("Repair & Reset Caches") {
                                state.revertConfiguration()
                            }
                            .buttonStyle(WarpSecondaryButtonStyle())
                        }

                        if state.verificationSteps.isEmpty {
                            Text("Click 'Run Automated Ladder' to evaluate Wine, PE execution, WindowServer, and CoreGraphics pixel states.")
                                .font(.system(size: 12))
                                .foregroundStyle(WarpTheme.mutedText)
                        } else {
                            ForEach(state.verificationSteps) { step in
                                HStack(alignment: .top, spacing: 10) {
                                    StatusPill(step.status.rawValue, color: colorForStep(step.status))
                                        .frame(width: 115, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Step \(step.id): \(step.name)")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(WarpTheme.primaryText)
                                        Text(step.evidence)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(WarpTheme.mutedText)
                                    }
                                }
                                .padding(.vertical, 3)
                            }
                        }
                    }
                }

                WarpCard(title: "Recent Sanitized Execution Logs") {
                    if state.recentLogContents.isEmpty {
                        Text("No execution logs found in \(state.logsRootURL.path)")
                            .font(.system(size: 12))
                            .foregroundStyle(WarpTheme.mutedText)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(state.recentLogContents, id: \.name) { entry in
                                DisclosureGroup(entry.name) {
                                    Text(entry.content)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(WarpTheme.primaryText)
                                        .textSelection(.enabled)
                                        .padding(8)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(WarpTheme.graphite)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .foregroundStyle(WarpTheme.primaryText)
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(WarpTheme.midnight)
    }

    private func colorForStep(_ status: LadderStepStatus) -> Color {
        switch status {
        case .verified: return WarpTheme.verifiedGreen
        case .failed, .blocked: return WarpTheme.blockedRed
        case .pendingManual: return WarpTheme.warningAmber
        case .skipped: return WarpTheme.mutedText
        }
    }
}

/// Screen 11: Performance Settings
struct PerformanceSettingsView: View {
    @Bindable var state: WarpAppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(
                    title: "Performance Settings",
                    subtitle: "Configure MetalFX, CEF rendering fallback, and Wine diagnostic verbosity."
                )

                WarpCard(title: "Graphics & Upscaling") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Enable MetalFX Spatial/Temporal Upscaling Flag (WARPBOOST_METALFX)", isOn: $state.metalFXEnabled)
                            .foregroundStyle(WarpTheme.primaryText)

                        Picker("Default Game Graphics Backend", selection: $state.preferredBackend) {
                            Text("DXVK").tag(GraphicsEngineType.dxvk)
                            Text("DXMT").tag(GraphicsEngineType.dxmt)
                            Text("WineD3D").tag(GraphicsEngineType.wined3d)
                        }
                        .pickerStyle(.segmented)
                    }
                }

                WarpCard(title: "Steam CEF Rendering Profile", subtitle: state.preferredCEFMode.securityTradeOff) {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("CEF Render Mode", selection: $state.preferredCEFMode) {
                            Text("Disable GPU (Recommended)").tag(CEFRenderMode.disableGPU)
                            Text("GPU Default").tag(CEFRenderMode.gpuDefault)
                            Text("In-Process GPU").tag(CEFRenderMode.inProcessGPU)
                            Text("Single Process (Experimental)").tag(CEFRenderMode.singleProcess)
                        }
                        .pickerStyle(.segmented)

                        HStack {
                            Text("WINEDEBUG")
                                .font(.system(size: 12))
                                .foregroundStyle(WarpTheme.mutedText)
                            TextField("-all", text: $state.debugChannels)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 220)
                        }
                    }
                }

                Button("Save Performance Settings") {
                    state.savePreferences()
                }
                .buttonStyle(WarpPrimaryButtonStyle())

                WarpCard(title: "WarpBoost Reversible Profiles", subtitle: "Hardware-aware presets tailored to current power & thermal state.") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("WarpBoost Tier", selection: $state.preferredBoostTier) {
                            ForEach(WarpBoostTier.allCases, id: \.self) { tier in
                                Text(tier.rawValue).tag(tier)
                            }
                        }
                        .pickerStyle(.segmented)

                        HStack(spacing: 10) {
                            Button("Apply Profile to Active Bottle") {
                                state.applyWarpBoostProfile(state.preferredBoostTier)
                            }
                            .buttonStyle(WarpPrimaryButtonStyle(color: WarpTheme.electricBlue))

                            Button("Revert WarpBoost") {
                                state.revertWarpBoostProfile()
                            }
                            .buttonStyle(WarpSecondaryButtonStyle())

                            Button("Run Benchmark Probe") {
                                state.runBackendBenchmarkProbe()
                            }
                            .buttonStyle(WarpSecondaryButtonStyle())
                        }

                        if !state.benchmarkReports.isEmpty {
                            ForEach(state.benchmarkReports) { rep in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(rep.config.targetName) [\(rep.config.backend.rawValue)] — \(rep.durationSeconds)s")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(WarpTheme.primaryText)
                                    Text("Thermal: \(rep.thermalStateStart.rawValue) -> \(rep.thermalStateEnd.rawValue) | Peak Mem: \(String(format: "%.1f", rep.peakMemoryUsedGB)) GB | \(rep.notes)")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(WarpTheme.mutedText)
                                }
                                .padding(8)
                                .background(WarpTheme.graphite)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(WarpTheme.midnight)
    }
}

/// Screen 12: Connected Gaming Platforms
struct PlatformsView: View {
    @Bindable var state: WarpAppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(
                    title: "Connected Gaming Platforms",
                    subtitle: "Official storefront integrations preserving native authentication and DRM."
                )

                WarpCard(title: "Valve Steam (Windows Client)", subtitle: "Environment: \(state.activeBottle?.name ?? "None")") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            StatusPill(state.steamInstalled ? "INSTALLED" : "NOT INSTALLED", color: state.steamInstalled ? WarpTheme.verifiedGreen : WarpTheme.warningAmber)
                            StatusPill(state.activeSteamPID != nil ? "RUNNING (PID \(state.activeSteamPID!))" : "STOPPED", color: state.activeSteamPID != nil ? WarpTheme.electricBlue : WarpTheme.mutedText)
                            Spacer()
                        }
                        MetadataRow("Executable", value: state.steamExecutablePath ?? "Not installed", monospaced: true)
                        MetadataRow("Auth Policy", value: "Manual login & Steam Guard inside official Steam window only.")

                        HStack(spacing: 10) {
                            if !state.steamInstalled {
                                Button("Install Official Steam") {
                                    state.installSteam()
                                }
                                .buttonStyle(WarpPrimaryButtonStyle())
                            } else {
                                Button("Launch Steam") {
                                    state.launchSteam()
                                }
                                .buttonStyle(WarpPrimaryButtonStyle())

                                if state.activeSteamPID != nil {
                                    Button("Stop Steam") {
                                        state.stopActiveSession()
                                    }
                                    .buttonStyle(WarpPrimaryButtonStyle(color: WarpTheme.blockedRed))
                                }
                            }
                        }
                    }
                }

                WarpCard(title: "Epic Games Store (Legendary CLI)", subtitle: "Planned for future integration — not yet active in WarpCore.") {
                    HStack {
                        StatusPill("UNSUPPORTED", color: WarpTheme.mutedText)
                        Text("OAuth & Keychain token integration is scheduled for a future milestone.")
                            .font(.system(size: 12))
                            .foregroundStyle(WarpTheme.mutedText)
                    }
                }

                WarpCard(title: "GOG Galaxy (heroic-gogdl)", subtitle: "Planned for future integration — not yet active in WarpCore.") {
                    HStack {
                        StatusPill("UNSUPPORTED", color: WarpTheme.mutedText)
                        Text("GOG storefront integration is not yet implemented.")
                            .font(.system(size: 12))
                            .foregroundStyle(WarpTheme.mutedText)
                    }
                }
            }
            .padding(24)
        }
        .background(WarpTheme.midnight)
    }
}
