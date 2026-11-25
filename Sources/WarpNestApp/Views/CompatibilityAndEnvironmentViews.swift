import SwiftUI
import WarpCore

/// Screen 7: Downloads & Installation Queue
struct DownloadsQueueView: View {
    @Bindable var state: WarpAppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(
                    title: "Downloads & Installation Queue",
                    subtitle: "Asynchronous, cancellable runtime tasks and active Steam download manifests."
                )

                let downloadingGames = state.installedGames.filter { $0.isDownloading }
                if !downloadingGames.isEmpty {
                    WarpCard(title: "Active Steam Downloads") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(downloadingGames) { game in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(game.name)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(WarpTheme.primaryText)
                                        Spacer()
                                        Text("\(Int(game.downloadProgress * 100))%")
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundStyle(WarpTheme.electricBlue)
                                    }
                                    ProgressView(value: game.downloadProgress)
                                }
                            }
                        }
                    }
                }

                if state.operations.isEmpty && downloadingGames.isEmpty {
                    WarpStateView(
                        icon: "tray",
                        title: "Queue Is Empty",
                        message: "Runtime installs, Steam setup, backend deployments, and verification runs appear here with live cancellation."
                    )
                } else if !state.operations.isEmpty {
                    WarpCard(title: "Runtime Operation Queue") {
                        VStack(spacing: 10) {
                            ForEach(state.operations) { op in
                                HStack(alignment: .center, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(op.title)
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(WarpTheme.primaryText)
                                        Text(op.detail)
                                            .font(.system(size: 11))
                                            .foregroundStyle(WarpTheme.mutedText)
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                    StatusPill(op.state.rawValue, color: colorForOp(op.state))
                                    if op.state == .running {
                                        Button("Cancel") {
                                            state.cancelOperation(id: op.id)
                                        }
                                        .buttonStyle(WarpSecondaryButtonStyle())
                                    }
                                }
                                .padding(10)
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

    private func colorForOp(_ state: QueuedOperation.State) -> Color {
        switch state {
        case .running: return WarpTheme.electricBlue
        case .completed: return WarpTheme.verifiedGreen
        case .failed: return WarpTheme.blockedRed
        case .cancelled: return WarpTheme.warningAmber
        }
    }
}

/// Screen 8: Compatibility Engine Manager
struct CompatibilityEngineView: View {
    @Bindable var state: WarpAppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(
                    title: "Compatibility Engine Manager",
                    subtitle: "Inspect MetalStorm graphics backends, SteamBridge profiles, and transactional rollback."
                )

                WarpCard(title: "Discovered Graphics Backends") {
                    VStack(spacing: 10) {
                        ForEach(state.graphicsBackends) { backend in
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        Text("\(backend.type.rawValue) v\(backend.version)")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(WarpTheme.primaryText)
                                        StatusPill(backend.isInstalled ? "INSTALLED" : "MISSING", color: backend.isInstalled ? WarpTheme.verifiedGreen : WarpTheme.mutedText)
                                        StatusPill(backend.hasUnixBridge ? "BRIDGE OK" : "NO BRIDGE", color: backend.hasUnixBridge ? WarpTheme.electricBlue : WarpTheme.warningAmber)
                                    }
                                    Text(backend.description)
                                        .font(.system(size: 12))
                                        .foregroundStyle(WarpTheme.mutedText)
                                    Text("License: \(backend.license) · DirectX: \(backend.supportedDirectXVersions.joined(separator: ", "))")
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(WarpTheme.mutedText)
                                }
                                Spacer()
                                if backend.type != .d3dmetal && backend.isInstalled {
                                    Button("Deploy") {
                                        state.changeGraphicsBackend(backend.type)
                                    }
                                    .buttonStyle(WarpSecondaryButtonStyle())
                                }
                            }
                            .padding(12)
                            .background(WarpTheme.graphite)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }

                WarpCard(title: "Active Environment Graphics State", subtitle: "Steam UI processes remain isolated on WineD3D builtin via AppDefaults.") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(state.activeBottleGraphicsSummary)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(WarpTheme.primaryText)
                        HStack(spacing: 10) {
                            Button("Apply Verified SteamBridge Profile") {
                                state.launchSteam()
                            }
                            .buttonStyle(WarpPrimaryButtonStyle())

                            Button("Revert to WineD3D & Repair") {
                                state.revertConfiguration()
                            }
                            .buttonStyle(WarpSecondaryButtonStyle())
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(WarpTheme.midnight)
    }
}

/// Screen 9: Windows Environment Manager
struct EnvironmentsView: View {
    @Bindable var state: WarpAppState
    @State private var newName: String = ""
    @State private var winVersion: String = "win10"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScreenHeader(
                    title: "Windows Environment Manager",
                    subtitle: "Manage isolated Wine bottles with Z: root containment."
                )

                WarpCard(title: "Create New Isolated Environment") {
                    HStack(spacing: 10) {
                        TextField("Environment name (e.g. GameBottle)", text: $newName)
                            .textFieldStyle(.roundedBorder)
                        Picker("Windows", selection: $winVersion) {
                            Text("Windows 10").tag("win10")
                            Text("Windows 11").tag("win11")
                            Text("Windows 7").tag("win7")
                        }
                        .frame(width: 150)
                        Button("Create Environment") {
                            let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            state.createEnvironment(name: trimmed, windowsVersion: winVersion)
                            newName = ""
                        }
                        .buttonStyle(WarpPrimaryButtonStyle())
                    }
                }

                if state.bottles.isEmpty {
                    WarpStateView(
                        icon: "shippingbox",
                        title: "No Environments Found",
                        message: "Create an isolated Windows environment above to begin."
                    )
                } else {
                    WarpCard(title: "Managed Bottles (\(state.bottles.count))") {
                        VStack(spacing: 10) {
                            ForEach(state.bottles) { bottle in
                                let isSelected = bottle.name == state.activeBottle?.name
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 8) {
                                            Text(bottle.name)
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(WarpTheme.primaryText)
                                            if isSelected {
                                                StatusPill("ACTIVE", color: WarpTheme.violet)
                                            }
                                            StatusPill(bottle.architecture.rawValue.uppercased(), color: WarpTheme.electricBlue)
                                        }
                                        Text(bottle.rootURL.path)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(WarpTheme.mutedText)
                                    }
                                    Spacer()
                                    Button(isSelected ? "Selected" : "Select") {
                                        state.selectedBottleName = bottle.name
                                        Task { await state.refreshAll() }
                                    }
                                    .buttonStyle(WarpSecondaryButtonStyle())
                                    .disabled(isSelected)
                                }
                                .padding(12)
                                .background(WarpTheme.graphite)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
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
