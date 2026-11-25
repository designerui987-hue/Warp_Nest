import Foundation

/// Configuration for a repeatable WarpNest Benchmark Laboratory run.
public struct BenchmarkConfig: Codable, Sendable {
    public let targetName: String
    public let backend: GraphicsEngineType
    public let resolution: String
    public let warmUpSeconds: Double
    public let measurementSeconds: Double
    public let repetitions: Int
    public let sustainedTest: Bool

    public init(
        targetName: String,
        backend: GraphicsEngineType,
        resolution: String = "1280x720",
        warmUpSeconds: Double = 3.0,
        measurementSeconds: Double = 10.0,
        repetitions: Int = 3,
        sustainedTest: Bool = false
    ) {
        self.targetName = targetName
        self.backend = backend
        self.resolution = resolution
        self.warmUpSeconds = warmUpSeconds
        self.measurementSeconds = measurementSeconds
        self.repetitions = max(1, repetitions)
        self.sustainedTest = sustainedTest
    }
}

/// Real frame-time statistics. Nil whenever reliable instrumentation is not available (never fabricated).
public struct FrameTimeMetrics: Codable, Sendable {
    public let sampleCount: Int
    public let averageFPS: Double
    public let p50Ms: Double
    public let p95Ms: Double
    public let p99Ms: Double
}

/// Result of a single repeatable benchmark run.
public struct BenchmarkRunReport: Codable, Sendable, Identifiable {
    public let id: String
    public let timestamp: Date
    public let config: BenchmarkConfig
    public let instrumentationAvailable: Bool
    public let frameMetrics: FrameTimeMetrics?
    public let peakMemoryUsedGB: Double
    public let thermalStateStart: WarpThermalState
    public let thermalStateEnd: WarpThermalState
    public let thermalThrottlingSuspected: Bool
    public let durationSeconds: Double
    public let notes: String
}

/// Repeatable benchmark runner & frame-time percentile analyzer.
/// Never invents FPS values or compatibility scores when instrumentation is absent.
public actor BenchmarkLaboratory {
    public init() {}

    /// Computes average FPS and p50/p95/p99 frame-time percentiles from genuine measured frame-time samples (in ms).
    /// Returns `nil` if `frameTimesMs` is empty.
    public nonisolated static func computeFrameMetrics(frameTimesMs: [Double]) -> FrameTimeMetrics? {
        let valid = frameTimesMs.filter { $0 > 0 && $0.isFinite }.sorted()
        guard !valid.isEmpty else { return nil }

        let avgMs = valid.reduce(0, +) / Double(valid.count)
        let avgFPS = avgMs > 0 ? (1000.0 / avgMs) : 0

        func percentile(_ p: Double) -> Double {
            let idx = min(valid.count - 1, max(0, Int((p * Double(valid.count - 1)).rounded())))
            return valid[idx]
        }

        return FrameTimeMetrics(
            sampleCount: valid.count,
            averageFPS: (avgFPS * 10.0).rounded() / 10.0,
            p50Ms: (percentile(0.50) * 100.0).rounded() / 100.0,
            p95Ms: (percentile(0.95) * 100.0).rounded() / 100.0,
            p99Ms: (percentile(0.99) * 100.0).rounded() / 100.0
        )
    }

    /// Executes a repeatable benchmark probe (or custom workload closure returning measured frame times in ms).
    public func runBenchmark(
        config: BenchmarkConfig,
        workload: @Sendable () async throws -> [Double]
    ) async throws -> BenchmarkRunReport {
        let startTelemetry = WarpSenseTelemetry.capture()
        let startTime = Date()

        // Warm-up phase
        if config.warmUpSeconds > 0 {
            try await Task.sleep(nanoseconds: UInt64(config.warmUpSeconds * 1_000_000_000))
        }

        var allFrameTimes: [Double] = []
        var peakMemGB = startTelemetry.memory.usedMemoryGB

        for _ in 0..<config.repetitions {
            let samples = try await workload()
            allFrameTimes.append(contentsOf: samples)
            let mid = WarpSenseTelemetry.capture()
            peakMemGB = max(peakMemGB, mid.memory.usedMemoryGB)
        }

        let endTelemetry = WarpSenseTelemetry.capture()
        let elapsed = Date().timeIntervalSince(startTime)
        let metrics = Self.computeFrameMetrics(frameTimesMs: allFrameTimes)
        let throttled = endTelemetry.thermalState == .serious || endTelemetry.thermalState == .critical

        return BenchmarkRunReport(
            id: UUID().uuidString,
            timestamp: Date(),
            config: config,
            instrumentationAvailable: metrics != nil,
            frameMetrics: metrics,
            peakMemoryUsedGB: peakMemGB,
            thermalStateStart: startTelemetry.thermalState,
            thermalStateEnd: endTelemetry.thermalState,
            thermalThrottlingSuspected: throttled,
            durationSeconds: (elapsed * 100.0).rounded() / 100.0,
            notes: metrics == nil
                ? "No frame-time instrumentation samples were produced; FPS not fabricated."
                : "Measured \(metrics!.sampleCount) frame-time samples across \(config.repetitions) repetition(s)."
        )
    }
}
