import Testing
import Foundation
@testable import WarpCore

@Suite("WarpSense & WarpBoost Telemetry Tests")
struct WarpSenseBoostTests {

    @Test("WarpSenseTelemetry captures real Apple Silicon, Metal, memory, storage, power, and thermal state")
    func testWarpSenseCapture() {
        let snap = WarpSenseTelemetry.capture()
        #expect(!snap.modelIdentifier.isEmpty)
        #expect(!snap.cpuBrand.isEmpty)
        #expect(snap.physicalCores > 0)
        #expect(snap.logicalCores >= snap.physicalCores)
        #expect(snap.memory.totalMemoryGB > 0)
        #expect(snap.availableStorageGB >= 0)
        #expect(snap.metal != nil)
        if let metal = snap.metal {
            #expect(!metal.deviceName.isEmpty)
            #expect(metal.hasUnifiedMemory == true)
        }
    }

    @Test("WarpBoostManager applies and reverts reversible performance profiles")
    func testWarpBoostApplyAndRevert() async throws {
        let fm = FileManager.default
        let tempRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("WarpBoost_\(UUID().uuidString)")
        try fm.createDirectory(at: tempRoot.appendingPathComponent("drive_c"), withIntermediateDirectories: true)
        let bottle = Bottle(id: "wb", name: "BoostBottle", rootURL: tempRoot)

        let snap = WarpSenseTelemetry.capture()
        let battery = WarpBoostProfile.preset(.batteryEfficiency, telemetry: snap, targetAppId: "220")
        let perf = WarpBoostProfile.preset(.performance, telemetry: snap, targetAppId: "220")

        #expect(battery.frameRateLimit == 30)
        #expect(perf.shaderCacheEnabled == true)

        let mgr = WarpBoostManager()
        _ = try await mgr.apply(battery, in: bottle)
        _ = try await mgr.apply(perf, in: bottle)

        let configURL = tempRoot.appendingPathComponent("warpboost_profile.json")
        let activeData = try Data(contentsOf: configURL)
        let activeDecoded = try JSONDecoder().decode(WarpBoostProfile.self, from: activeData)
        #expect(activeDecoded.tier == .performance)

        let reverted = try await mgr.revert(in: bottle)
        #expect(reverted == true)
        let revertedData = try Data(contentsOf: configURL)
        let revertedDecoded = try JSONDecoder().decode(WarpBoostProfile.self, from: revertedData)
        #expect(revertedDecoded.tier == .batteryEfficiency)

        try? fm.removeItem(at: tempRoot)
    }

    @Test("BenchmarkLaboratory computes accurate frame-time percentiles and returns nil without instrumentation")
    func testBenchmarkFrameTimePercentiles() async throws {
        // 1. No instrumentation -> nil (never fabricates FPS)
        #expect(BenchmarkLaboratory.computeFrameMetrics(frameTimesMs: []) == nil)

        // 2. Real frame-time samples -> exact average FPS & p50/p95/p99
        let samples = Array(repeating: 16.66, count: 95) + [25.0, 28.0, 30.0, 33.3, 40.0]
        let metrics = BenchmarkLaboratory.computeFrameMetrics(frameTimesMs: samples)
        #expect(metrics != nil)
        if let m = metrics {
            #expect(m.sampleCount == 100)
            #expect(m.p50Ms == 16.66)
            #expect(m.p99Ms >= 33.3)
            #expect(m.averageFPS > 50.0 && m.averageFPS < 61.0)
        }

        let lab = BenchmarkLaboratory()
        let cfg = BenchmarkConfig(targetName: "UnitTestScene", backend: .dxvk, warmUpSeconds: 0.0, repetitions: 1)
        let report = try await lab.runBenchmark(config: cfg) { [] }
        #expect(report.instrumentationAvailable == false)
        #expect(report.frameMetrics == nil)
    }
}
