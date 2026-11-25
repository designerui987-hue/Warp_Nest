import SwiftUI
import WarpCore

/// Screen 1: Welcome & Onboarding
struct OnboardingView: View {
    @Bindable var state: WarpAppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ScreenHeader(
                    title: "Welcome to WarpNest",
                    subtitle: "Native Apple Silicon Windows compatibility environment & game launcher.",
                    badge: ("APPLE SILICON", WarpTheme.violet)
                )

                WarpCard(
                    title: "Built on Verified Open Components",
                    subtitle: "Observable, reversible Windows execution without modifying host macOS Steam."
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        featureRow(icon: "cpu", title: "Apple Silicon Telemetry", detail: "\(state.systemDiagnostics.cpuBrand) · \(state.systemDiagnostics.totalMemoryGigabytes) GB Unified Memory")
                        featureRow(icon: "shippingbox", title: "Isolated Bottles", detail: "Per-environment drive_c containment with Z: root omission and path validation.")
                        featureRow(icon: "square.stack.3d.up", title: "Modular Graphics Backends", detail: "Switch cleanly between WineD3D, DXVK + MoltenVK, and DXMT with transactional rollback.")
                        featureRow(icon: "lock.shield", title: "Legitimate Ownership Only", detail: "Official Steam authentication and DRM remain untouched; credentials are never collected.")
                    }
                }

                HStack(spacing: 12) {
                    Button("Continue to Overview") {
                        state.hasCompletedOnboarding = true
                        state.savePreferences()
                        state.selectedScreen = .dashboard
                    }
                    .buttonStyle(WarpPrimaryButtonStyle())

                    Button("Inspect Hardware First") {
                        state.selectedScreen = .hardware
                    }
                    .buttonStyle(WarpSecondaryButtonStyle())

                    Button("Open Runtime Wizard") {
                        state.selectedScreen = .runtimeWizard
                    }
                    .buttonStyle(WarpSecondaryButtonStyle())
                }
            }
            .padding(24)
        }
        .background(WarpTheme.midnight)
    }

    private func featureRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(WarpTheme.electricBlue)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WarpTheme.primaryText)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(WarpTheme.mutedText)
            }
        }
    }
}

/// Screen 2: Hardware Detection
struct HardwareDetectionView: View {
    @Bindable var state: WarpAppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(
                    title: "Hardware Detection",
                    subtitle: "Live Apple Silicon, unified memory, and Rosetta 2 inspection via WarpSense.",
                    badge: (state.systemDiagnostics.isAppleSilicon ? "ARM64" : "X86_64", WarpTheme.verifiedGreen)
                )

                WarpCard(title: "Host Machine Profile") {
                    VStack(spacing: 4) {
                        MetadataRow("Hardware Model", value: state.systemDiagnostics.macModel, monospaced: true)
                        MetadataRow("Processor", value: "\(state.systemDiagnostics.cpuBrand) (\(state.systemDiagnostics.physicalCores) logical cores)")
                        MetadataRow("Architecture", value: state.systemDiagnostics.isAppleSilicon ? "ARM64 (Apple Silicon)" : "x86_64")
                        MetadataRow("Unified Memory", value: "\(state.systemDiagnostics.totalMemoryGigabytes) GB")
                        MetadataRow("macOS Version", value: state.systemDiagnostics.osVersion)
                        MetadataRow("Rosetta 2 Runtime", value: state.systemDiagnostics.isRosettaActive ? "Active (/Library/Apple/usr/libexec/oah/libRosettaRuntime)" : "Not Detected")
                    }
                }

                if let snap = state.warpSenseSnapshot {
                    WarpCard(title: "WarpSense Live Telemetry", subtitle: "Collected via Metal, Mach VM, IOKit.ps, and ProcessInfo") {
                        VStack(spacing: 4) {
                            MetadataRow("Metal GPU", value: snap.metal?.deviceName ?? "Unavailable")
                            MetadataRow("Metal Features", value: snap.metal.map { "Unified=\($0.hasUnifiedMemory), Metal3=\($0.supportsMetal3), Apple9=\($0.supportsApple9)" } ?? "N/A")
                            MetadataRow("Max Working Set", value: snap.metal.map { "\(String(format: "%.1f", $0.recommendedMaxWorkingSetGB)) GB" } ?? "N/A")
                            MetadataRow("Memory Pressure", value: "\(String(format: "%.1f", snap.memory.usedMemoryGB)) / \(String(format: "%.1f", snap.memory.totalMemoryGB)) GB (\(snap.memory.pressureLevel))")
                            MetadataRow("Available Storage", value: "\(String(format: "%.1f", snap.availableStorageGB)) GB")
                            MetadataRow("Power Source", value: "\(snap.power.powerSource)\(snap.power.batteryPercent.map { " (\($0)%)" } ?? "")")
                            MetadataRow("Thermal State", value: "\(snap.thermalState.rawValue) (Fanless Air aware)")
                        }
                    }
                }

                HStack {
                    Button("Re-scan Hardware") {
                        Task { await state.refreshAll() }
                    }
                    .buttonStyle(WarpSecondaryButtonStyle())
                }
            }
            .padding(24)
        }
        .background(WarpTheme.midnight)
    }
}

/// Screen 3: Runtime Installation Wizard
struct RuntimeWizardView: View {
    @Bindable var state: WarpAppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                let healthy = state.runtimeReport?.isHealthy ?? false
                ScreenHeader(
                    title: "Runtime Installation Wizard",
                    subtitle: "Inspect and install verified open-source Wine WoW64 runtimes.",
                    badge: (healthy ? "VERIFIED" : "ACTION NEEDED", healthy ? WarpTheme.verifiedGreen : WarpTheme.warningAmber)
                )

                if let report = state.runtimeReport {
                    WarpCard(title: "Installed Engine Verification", subtitle: report.enginePath) {
                        VStack(spacing: 4) {
                            MetadataRow("Wine Version", value: report.wineVersion.isEmpty ? "Not Found" : report.wineVersion, monospaced: true)
                            MetadataRow("Core Binaries", value: "wine=\(report.hasWineBinary ? "OK" : "MISSING"), wineserver=\(report.hasWineServer ? "OK" : "MISSING")")
                            MetadataRow("Cocoa Display Driver", value: report.hasWineMacDriver ? "winemac.so FOUND" : "MISSING")
                            MetadataRow("Vulkan Bridge", value: report.hasWineVulkan ? "winevulkan.so FOUND" : "MISSING")
                            MetadataRow("DXMT Metal Bridge", value: report.hasWineMetalBridge ? "winemetal.so FOUND" : "Not Present")
                            MetadataRow("MoltenVK ICD", value: report.hasMoltenVK ? "FOUND" : "MISSING")
                        }
                    }
                }

                if let manifest = state.runtimeManifest {
                    WarpCard(title: "Registered Upstream Manifest (v\(manifest.schemaVersion))") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(manifest.runtimes) { entry in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(entry.name)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(WarpTheme.primaryText)
                                        Spacer()
                                        StatusPill(entry.license, color: WarpTheme.electricBlue)
                                    }
                                    Text(entry.upstreamUrl)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(WarpTheme.mutedText)
                                        .lineLimit(1)
                                }
                                .padding(10)
                                .background(WarpTheme.graphite)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }
                }

                HStack(spacing: 12) {
                    Button("Install / Verify Wine 11.21") {
                        state.installRuntimeScripted()
                    }
                    .buttonStyle(WarpPrimaryButtonStyle())

                    Button("Refresh Verification") {
                        Task { await state.refreshAll() }
                    }
                    .buttonStyle(WarpSecondaryButtonStyle())
                }
            }
            .padding(24)
        }
        .background(WarpTheme.midnight)
    }
}

/// Screen 13: Application Preferences
struct PreferencesView: View {
    @Bindable var state: WarpAppState
    @State private var workspaceInput: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(
                    title: "Application Preferences",
                    subtitle: "Workspace location, SQLite persistence, and UI defaults."
                )

                WarpCard(title: "Workspace & Storage") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("WarpNest Workspace Root")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(WarpTheme.mutedText)
                        HStack {
                            TextField("/Volumes/Personal/WarpNest", text: $workspaceInput)
                                .textFieldStyle(.roundedBorder)
                            Button("Apply & Save") {
                                if !workspaceInput.isEmpty {
                                    state.workspaceRoot = URL(fileURLWithPath: workspaceInput, isDirectory: true)
                                }
                                state.savePreferences()
                                Task { await state.refreshAll() }
                            }
                            .buttonStyle(WarpPrimaryButtonStyle())
                        }
                        MetadataRow("SQLite Store", value: state.persistence.databaseURL.path, monospaced: true)
                        MetadataRow("Engines Directory", value: state.enginesRootURL.path, monospaced: true)
                        MetadataRow("Bottles Directory", value: state.bottlesRootURL.path, monospaced: true)
                    }
                }

                WarpCard(title: "Onboarding") {
                    Toggle("Show Welcome & Onboarding on next launch", isOn: Binding(
                        get: { !state.hasCompletedOnboarding },
                        set: { newVal in
                            state.hasCompletedOnboarding = !newVal
                            state.savePreferences()
                        }
                    ))
                    .foregroundStyle(WarpTheme.primaryText)
                }
            }
            .padding(24)
        }
        .background(WarpTheme.midnight)
        .onAppear {
            workspaceInput = state.workspaceRoot.path
        }
    }
}
