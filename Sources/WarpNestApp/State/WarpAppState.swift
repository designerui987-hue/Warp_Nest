import Foundation
import SwiftUI
import WarpCore

/// All 13 primary navigation destinations in WarpNest.
enum WarpScreen: String, CaseIterable, Identifiable {
    case onboarding = "Welcome"
    case hardware = "Hardware Detection"
    case runtimeWizard = "Runtime Wizard"
    case dashboard = "Overview"
    case library = "Game Library"
    case gameDetails = "Game Details"
    case downloads = "Downloads & Queue"
    case engines = "Compatibility Engines"
    case environments = "Windows Environments"
    case diagnostics = "Diagnostics & Logs"
    case performance = "Performance"
    case platforms = "Connected Platforms"
    case preferences = "Preferences"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .onboarding: return "sparkles"
        case .hardware: return "cpu"
        case .runtimeWizard: return "arrow.down.circle"
        case .dashboard: return "square.grid.2x2"
        case .library: return "gamecontroller"
        case .gameDetails: return "info.circle"
        case .downloads: return "tray.and.arrow.down"
        case .engines: return "gearshape.2"
        case .environments: return "shippingbox"
        case .diagnostics: return "waveform.path.ecg"
        case .performance: return "gauge.with.dots.needle.67percent"
        case .platforms: return "link.circle"
        case .preferences: return "slider.horizontal.3"
        }
    }

    var section: String {
        switch self {
        case .dashboard, .library, .gameDetails, .downloads:
            return "PLAY"
        case .environments, .engines, .platforms, .performance:
            return "COMPATIBILITY"
        case .hardware, .runtimeWizard, .diagnostics, .onboarding, .preferences:
            return "SYSTEM"
        }
    }

    static var sidebarItems: [WarpScreen] {
        [
            .dashboard, .library, .downloads,
            .environments, .engines, .platforms, .performance,
            .hardware, .runtimeWizard, .diagnostics, .onboarding, .preferences
        ]
    }
}

/// Cancellable runtime operation tracked in the Downloads & Queue screen.
struct QueuedOperation: Identifiable, Sendable {
    enum State: String, Sendable {
        case running = "RUNNING"
        case completed = "COMPLETED"
        case failed = "FAILED"
        case cancelled = "CANCELLED"
    }

    let id: String
    let title: String
    let startedAt: Date
    var state: State
    var detail: String
}

/// Central `@MainActor` coordinator binding all 13 SwiftUI screens to `WarpCore`.
@Observable
@MainActor
final class WarpAppState {
    // Navigation
    var selectedScreen: WarpScreen = .dashboard
    var selectedGame: SteamGame?
    var selectedCanonicalGame: CanonicalGame?
    var searchQuery: String = ""

    // Paths
    var workspaceRoot: URL
    let persistence: WarpPersistenceStore

    // Live Telemetry & Data
    var systemDiagnostics: SystemDiagnostics = .inspect()
    var warpSenseSnapshot: WarpSenseSnapshot?
    var benchmarkReports: [BenchmarkRunReport] = []
    var runtimeReport: RuntimeVerifier.VerificationReport?
    var runtimeManifest: RuntimeManifest?
    var graphicsBackends: [GraphicsBackendInfo] = []
    var bottles: [Bottle] = []
    var selectedBottleName: String = "SteamBottle"
    var installedGames: [SteamGame] = []
    var canonicalGames: [CanonicalGame] = []
    var providerStatuses: [ProviderStatusSnapshot] = []
    var providerErrors: [String] = []
    var steamInstalled: Bool = false
    var steamExecutablePath: String?
    var activeSteamPID: pid_t?
    var steamDiagnosticReport: SteamDiagnosticReport?
    var verificationSteps: [SteamLadderStepResult] = []
    var recentLogContents: [(name: String, content: String)] = []
    var activeBottleGraphicsSummary: String = ""

    // Settings (persisted in SQLite)
    var hasCompletedOnboarding: Bool
    var metalFXEnabled: Bool
    var preferredBackend: GraphicsEngineType
    var preferredBoostTier: WarpBoostTier
    var preferredCEFMode: CEFRenderMode
    var debugChannels: String

    // Async Operation Queue & Error Banner
    var isRefreshing: Bool = false
    var operations: [QueuedOperation] = []
    var activeTasks: [String: Task<Void, Never>] = [:]
    var bannerError: String?
    var bannerNotice: String?

    init(persistence: WarpPersistenceStore = WarpPersistenceStore()) {
        self.persistence = persistence
        self.workspaceRoot = Self.resolveWorkspaceRoot(savedPath: persistence.getPreference("workspace_root"))
        self.hasCompletedOnboarding = persistence.getPreference("onboarding_done") == "true"
        self.metalFXEnabled = persistence.getPreference("metalfx_enabled") == "true"
        self.preferredBackend = GraphicsEngineType(rawValue: persistence.getPreference("preferred_backend") ?? "") ?? .dxvk
        self.preferredBoostTier = WarpBoostTier(rawValue: persistence.getPreference("preferred_boost_tier") ?? "") ?? .balanced
        self.preferredCEFMode = CEFRenderMode(rawValue: persistence.getPreference("preferred_cef_mode") ?? "") ?? .disableGPU
        self.debugChannels = persistence.getPreference("wine_debug") ?? "-all"

        if !self.hasCompletedOnboarding {
            self.selectedScreen = .onboarding
        }
    }

    static func resolveWorkspaceRoot(savedPath: String?) -> URL {
        let fm = FileManager.default
        if let envPath = ProcessInfo.processInfo.environment["WARPNEST_WORKSPACE"],
           fm.fileExists(atPath: envPath) {
            return URL(fileURLWithPath: envPath, isDirectory: true)
        }
        if let savedPath, fm.fileExists(atPath: savedPath) {
            return URL(fileURLWithPath: savedPath, isDirectory: true)
        }
        let cwd = URL(fileURLWithPath: fm.currentDirectoryPath, isDirectory: true)
        if fm.fileExists(atPath: cwd.appendingPathComponent("engines").path) {
            return cwd
        }
        let repoDefault = URL(fileURLWithPath: "/Volumes/Personal/WarpNest", isDirectory: true)
        if fm.fileExists(atPath: repoDefault.appendingPathComponent("engines").path) {
            return repoDefault
        }
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("WarpNest", isDirectory: true)
    }

    // MARK: - Computed Helpers

    var enginesRootURL: URL { workspaceRoot.appendingPathComponent("engines", isDirectory: true) }
    var wineEngineURL: URL { enginesRootURL.appendingPathComponent("wine-default", isDirectory: true) }
    var bottlesRootURL: URL { workspaceRoot.appendingPathComponent("bottles", isDirectory: true) }
    var logsRootURL: URL { workspaceRoot.appendingPathComponent("logs", isDirectory: true) }
    var manifestURL: URL { workspaceRoot.appendingPathComponent("runtimes/manifest.json") }

    var activeBottle: Bottle? {
        bottles.first { $0.name == selectedBottleName } ?? bottles.first
    }

    var filteredCanonicalGames: [CanonicalGame] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return canonicalGames }
        return canonicalGames.filter {
            $0.title.localizedCaseInsensitiveContains(q)
            || $0.provider.rawValue.localizedCaseInsensitiveContains(q)
            || $0.storeAppId.localizedCaseInsensitiveContains(q)
        }
    }

    var filteredGames: [SteamGame] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return installedGames }
        return installedGames.filter {
            $0.name.localizedCaseInsensitiveContains(q) || $0.appId.localizedCaseInsensitiveContains(q)
        }
    }

    // MARK: - Refresh All Real State

    func refreshAll() async {
        isRefreshing = true
        defer { isRefreshing = false }

        systemDiagnostics = SystemDiagnostics.inspect()
        warpSenseSnapshot = WarpSenseTelemetry.capture(volumeURL: workspaceRoot)
        runtimeManifest = try? RuntimeManifest.load(from: manifestURL)
        runtimeReport = await RuntimeVerifier.verify(engineURL: wineEngineURL)

        let gm = GraphicsBackendManager(
            backendsRootURL: enginesRootURL.appendingPathComponent("backends"),
            engineRootURL: wineEngineURL
        )
        graphicsBackends = await gm.discoverBackends()

        let bm = BottleManager(baseStorageURL: bottlesRootURL)
        bottles = (try? await bm.listBottles()) ?? []
        if let first = bottles.first, !bottles.contains(where: { $0.name == selectedBottleName }) {
            selectedBottleName = first.name
        }

        if let bottle = activeBottle {
            activeBottleGraphicsSummary = await gm.inspectPrefixGraphics(in: bottle)
            let engine = WineEngine(rootURL: wineEngineURL)
            let controller = SteamSessionController(bottle: bottle, engine: engine, logsDirectory: logsRootURL)
            let steamExe = await controller.integration.detectedSteamExecutableURL
            steamInstalled = steamExe != nil
            steamExecutablePath = steamExe?.path
            activeSteamPID = await controller.supervisor.activeSessionPID(for: bottle)
            installedGames = await controller.integration.discoverInstalledGames()
            if let selected = selectedGame {
                selectedGame = installedGames.first(where: { $0.appId == selected.appId }) ?? selected
            }
            steamDiagnosticReport = try? await controller.diagnose()
        } else {
            steamInstalled = false
            steamExecutablePath = nil
            activeSteamPID = nil
            installedGames = []
            steamDiagnosticReport = nil
            activeBottleGraphicsSummary = "No Windows environment selected."
        }

        let supervisor = ProcessSupervisor(logsDirectory: logsRootURL)
        let logURLs = await supervisor.listLogs(limit: 8)
        recentLogContents = logURLs.compactMap { url in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return (url.lastPathComponent, BottlePathValidator.sanitizeLog(text))
        }

        // Unified multi-platform provider discovery
        let providers = makeProviders()
        let coordinator = UnifiedLibraryCoordinator(providers: providers)
        providerStatuses = await coordinator.fetchProviderStatuses()
        let discovery = await coordinator.discoverAllInstalledGames()
        canonicalGames = discovery.games
        providerErrors = discovery.errors
        if let sel = selectedCanonicalGame {
            selectedCanonicalGame = canonicalGames.first(where: { $0.id == sel.id }) ?? sel
        }
    }

    private func makeProviders() -> [any GameProviderProtocol] {
        let engine = WineEngine(rootURL: wineEngineURL)
        var list: [any GameProviderProtocol] = []
        if let bottle = activeBottle {
            list.append(SteamLibraryProvider(bottle: bottle, engine: engine, logsDirectory: logsRootURL))
        }
        list.append(EpicLegendaryProvider(bottle: activeBottle))
        list.append(GOGLibraryProvider())
        list.append(LocalWindowsProvider(bottlesRootURL: bottlesRootURL, engine: engine))
        list.append(NativeMacOSProvider())
        return list
    }

    func launchCanonicalGame(_ game: CanonicalGame) {
        let providers = makeProviders()
        runCancellableOperation(title: "Launch \(game.title) (\(game.provider.rawValue))") {
            guard let provider = providers.first(where: { $0.providerType == game.provider }) else {
                throw ProviderError.apiUnavailable(provider: game.provider, reason: "Provider not initialized.")
            }
            try await provider.launch(game: game)
            return "Launched \(game.title)."
        }
    }

    // MARK: - Cancellable Runtime Actions

    func runCancellableOperation(title: String, work: @escaping @Sendable () async throws -> String) {
        let id = UUID().uuidString
        let op = QueuedOperation(id: id, title: title, startedAt: Date(), state: .running, detail: "Starting...")
        operations.insert(op, at: 0)

        let task = Task { [weak self] in
            do {
                let detail = try await work()
                await MainActor.run {
                    self?.updateOperation(id: id, state: .completed, detail: detail)
                    self?.bannerNotice = "\(title): \(detail)"
                    self?.persistence.recordOperation(id: id, title: title, status: "COMPLETED", detail: detail)
                }
                await self?.refreshAll()
            } catch is CancellationError {
                await MainActor.run {
                    self?.updateOperation(id: id, state: .cancelled, detail: "Cancelled by user.")
                    self?.persistence.recordOperation(id: id, title: title, status: "CANCELLED", detail: "Cancelled by user.")
                }
            } catch {
                await MainActor.run {
                    self?.updateOperation(id: id, state: .failed, detail: error.localizedDescription)
                    self?.bannerError = "\(title) failed: \(error.localizedDescription)"
                    self?.persistence.recordOperation(id: id, title: title, status: "FAILED", detail: error.localizedDescription)
                }
            }
            await MainActor.run {
                self?.activeTasks[id] = nil
            }
        }
        activeTasks[id] = task
    }

    func cancelOperation(id: String) {
        activeTasks[id]?.cancel()
        activeTasks[id] = nil
        updateOperation(id: id, state: .cancelled, detail: "Cancellation requested.")
    }

    private func updateOperation(id: String, state: QueuedOperation.State, detail: String) {
        if let idx = operations.firstIndex(where: { $0.id == id }) {
            operations[idx].state = state
            operations[idx].detail = detail
        }
    }

    // MARK: - Domain Actions Connected to WarpCore

    func createEnvironment(name: String, windowsVersion: String) {
        let root = bottlesRootURL
        runCancellableOperation(title: "Create Environment '\(name)'") {
            let bm = BottleManager(baseStorageURL: root)
            let bottle = try await bm.createBottle(name: name, architecture: .win64, windowsVersion: windowsVersion)
            return "Created at \(bottle.rootURL.path)"
        }
    }

    func installRuntimeScripted() {
        let scriptURL = workspaceRoot.appendingPathComponent("scripts/fetch_runtime.sh")
        let ws = workspaceRoot
        runCancellableOperation(title: "Install Wine Staging Runtime") {
            guard FileManager.default.isExecutableFile(atPath: scriptURL.path) else {
                throw BottleError.executionFailed("Runtime fetch script not found at \(scriptURL.path)")
            }
            let sup = SteamProcessSupervisor()
            let out = try await sup.runAsync(
                executableURL: scriptURL,
                arguments: ["--version", "11.21"],
                environment: ProcessInfo.processInfo.environment,
                workingDirectory: ws,
                timeoutSeconds: 600.0
            )
            if out.exitCode != 0 {
                throw BottleError.executionFailed(out.standardError.isEmpty ? "Exit code \(out.exitCode)" : out.standardError)
            }
            return "Wine Staging 11.21 verified."
        }
    }

    func installSteam(installerPath: URL? = nil) {
        guard let bottle = activeBottle else {
            bannerError = "Select or create a Windows environment first."
            return
        }
        let engine = WineEngine(rootURL: wineEngineURL)
        let installer = installerPath ?? workspaceRoot.appendingPathComponent("installers/SteamSetup.exe")
        runCancellableOperation(title: "Install Windows Steam in \(bottle.name)") {
            let steam = SteamIntegration(bottle: bottle, engine: engine)
            try await steam.install(from: installer)
            return "Steam client installed."
        }
    }

    func launchSteam(appId: String? = nil) {
        guard let bottle = activeBottle else {
            bannerError = "No active Windows environment selected."
            return
        }
        let engine = WineEngine(rootURL: wineEngineURL)
        let logsDir = logsRootURL
        let cefMode = preferredCEFMode
        let title = appId.map { "Launch Steam App \($0)" } ?? "Launch Windows Steam"

        runCancellableOperation(title: title) {
            let controller = SteamSessionController(bottle: bottle, engine: engine, logsDirectory: logsDir)
            let net = await controller.networkDiagnostics.diagnose(bottle: bottle)
            var profiles: [SteamCompatibilityProfileID] = [.wineD3DOpenGL]
            if cefMode != .gpuDefault { profiles.append(.cefSoftwareRender) }
            if net.requiresResolverOverride { profiles.append(.localhostDNSOverride) }

            let profile = SteamCompatibilityProfile.compose(
                profiles: profiles,
                cefRenderMode: cefMode,
                disableCEFSandbox: true,
                dns64Detected: net.requiresResolverOverride
            )
            let handle = try await controller.start(profile: profile, appId: appId)
            return "Started PID \(handle.pid) (\(handle.profile.activeProfiles.map(\.rawValue).joined(separator: ", ")))"
        }
    }

    func stopActiveSession() {
        guard let bottle = activeBottle else { return }
        let engine = WineEngine(rootURL: wineEngineURL)
        let logsDir = logsRootURL
        runCancellableOperation(title: "Stop Session in \(bottle.name)") {
            let controller = SteamSessionController(bottle: bottle, engine: engine, logsDirectory: logsDir)
            await controller.stop()
            return "Stopped bottle-scoped wineserver and Steam PIDs."
        }
    }

    func changeGraphicsBackend(_ backend: GraphicsEngineType, forAppId appId: String? = nil) {
        guard let bottle = activeBottle else {
            bannerError = "Select a Windows environment first."
            return
        }
        let engines = enginesRootURL
        let wine = wineEngineURL
        runCancellableOperation(title: "Set Graphics Backend (\(backend.rawValue))") {
            let gm = GraphicsBackendManager(
                backendsRootURL: engines.appendingPathComponent("backends"),
                engineRootURL: wine
            )
            let res = try await gm.configureBackend(backend: backend, in: bottle)
            return res.notes
        }
        if let appId {
            persistence.setGameBackendOverride(appId: appId, backend: backend.rawValue, cefMode: preferredCEFMode.rawValue)
        } else {
            preferredBackend = backend
            persistence.setPreference("preferred_backend", value: backend.rawValue)
        }
    }

    func revertConfiguration() {
        guard let bottle = activeBottle else { return }
        let engine = WineEngine(rootURL: wineEngineURL)
        let logsDir = logsRootURL
        let engines = enginesRootURL
        let wine = wineEngineURL

        runCancellableOperation(title: "Revert & Repair \(bottle.name)") {
            let controller = SteamSessionController(bottle: bottle, engine: engine, logsDirectory: logsDir)
            let report = try await controller.repair()
            let gm = GraphicsBackendManager(
                backendsRootURL: engines.appendingPathComponent("backends"),
                engineRootURL: wine
            )
            _ = try await gm.configureBackend(backend: .wined3d, in: bottle)
            return "Restored WineD3D & repaired bottle (\(report.actionsPerformed.count) actions)."
        }
    }

    func runVerificationLadder() {
        guard let bottle = activeBottle else { return }
        let engine = WineEngine(rootURL: wineEngineURL)
        let logsDir = logsRootURL
        let scratch = workspaceRoot.appendingPathComponent("scratch", isDirectory: true)

        runCancellableOperation(title: "Run 13-Step Verification Ladder") {
            let controller = SteamSessionController(bottle: bottle, engine: engine, logsDirectory: logsDir)
            let ladder = SteamVerificationLadder()
            let steps = await ladder.runAutomatedChecks(controller: controller, scratchDirectory: scratch)
            await MainActor.run {
                self.verificationSteps = steps
            }
            let verifiedCount = steps.filter { $0.status == .verified }.count
            return "\(verifiedCount)/\(steps.count) steps verified."
        }
    }

    func savePreferences() {
        persistence.setPreference("workspace_root", value: workspaceRoot.path)
        persistence.setPreference("onboarding_done", value: hasCompletedOnboarding ? "true" : "false")
        persistence.setPreference("metalfx_enabled", value: metalFXEnabled ? "true" : "false")
        persistence.setPreference("preferred_backend", value: preferredBackend.rawValue)
        persistence.setPreference("preferred_boost_tier", value: preferredBoostTier.rawValue)
        persistence.setPreference("preferred_cef_mode", value: preferredCEFMode.rawValue)
        persistence.setPreference("wine_debug", value: debugChannels)
        bannerNotice = "Preferences saved to SQLite."
    }

    func applyWarpBoostProfile(_ tier: WarpBoostTier) {
        guard let bottle = activeBottle else {
            bannerError = "Select a Windows environment first."
            return
        }
        let snap = warpSenseSnapshot ?? WarpSenseTelemetry.capture(volumeURL: workspaceRoot)
        let profile = WarpBoostProfile.preset(tier, telemetry: snap)
        preferredBoostTier = tier
        persistence.setPreference("preferred_boost_tier", value: tier.rawValue)

        runCancellableOperation(title: "Apply WarpBoost (\(tier.rawValue))") {
            let mgr = WarpBoostManager()
            let url = try await mgr.apply(profile, in: bottle)
            return "Saved reversible profile at \(url.lastPathComponent): \(profile.notes)"
        }
    }

    func revertWarpBoostProfile() {
        guard let bottle = activeBottle else { return }
        runCancellableOperation(title: "Revert WarpBoost Profile") {
            let mgr = WarpBoostManager()
            let reverted = try await mgr.revert(in: bottle)
            return reverted ? "Restored previous WarpBoost configuration." : "No WarpBoost backup to revert."
        }
    }

    func runBackendBenchmarkProbe() {
        let ws = workspaceRoot
        let backend = preferredBackend
        runCancellableOperation(title: "Benchmark Laboratory (\(backend.rawValue))") {
            let lab = BenchmarkLaboratory()
            let cfg = BenchmarkConfig(
                targetName: "D3D11 Hardware Probe",
                backend: backend,
                resolution: "Headless",
                warmUpSeconds: 0.5,
                measurementSeconds: 1.0,
                repetitions: 2,
                sustainedTest: false
            )
            let report = try await lab.runBenchmark(config: cfg) {
                // Probe produces no swapchain frame-times; BenchmarkLaboratory accurately reports instrumentationAvailable=false
                let _ = ws
                return []
            }
            await MainActor.run {
                self.benchmarkReports.insert(report, at: 0)
            }
            return "Recorded thermal=\(report.thermalStateEnd.rawValue), peakMem=\(String(format: "%.1f", report.peakMemoryUsedGB))GB."
        }
    }
}
