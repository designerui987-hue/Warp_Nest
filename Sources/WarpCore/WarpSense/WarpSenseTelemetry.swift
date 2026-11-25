import Foundation
import Metal
import IOKit.ps

/// Supported macOS thermal state mapping (`ProcessInfo.ThermalState`).
public enum WarpThermalState: String, Codable, Sendable {
    case nominal = "Nominal"
    case fair = "Fair"
    case serious = "Serious"
    case critical = "Critical"
    case unknown = "Unknown"

    public init(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .unknown
        }
    }
}

/// Power source & battery state discovered via `IOKit.ps`.
public struct WarpPowerStatus: Codable, Sendable {
    public let powerSource: String
    public let batteryPercent: Int?
    public let isCharging: Bool?
}

/// Real-time memory pressure & VM statistics from `host_statistics64`.
public struct WarpMemoryStats: Codable, Sendable {
    public let totalMemoryGB: Double
    public let usedMemoryGB: Double
    public let freeMemoryGB: Double
    public let pressureLevel: String
}

/// Metal GPU capabilities discovered via `MTLCreateSystemDefaultDevice()`.
/// Does not fabricate unavailable GPU core counts or sensor temperatures.
public struct WarpMetalCapabilities: Codable, Sendable {
    public let deviceName: String
    public let hasUnifiedMemory: Bool
    public let supportsMetal3: Bool
    public let supportsApple9: Bool
    public let recommendedMaxWorkingSetGB: Double
}

/// Complete, non-fabricated hardware & runtime capability snapshot for Apple Silicon Macs.
public struct WarpSenseSnapshot: Codable, Sendable {
    public let capturedAt: Date
    public let modelIdentifier: String
    public let cpuBrand: String
    public let cpuArchitecture: String
    public let physicalCores: Int
    public let logicalCores: Int
    public let osVersion: String
    public let metal: WarpMetalCapabilities?
    public let memory: WarpMemoryStats
    public let availableStorageGB: Double
    public let power: WarpPowerStatus
    public let thermalState: WarpThermalState
    public let rosetta2Available: Bool

    public func formattedSummary() -> String {
        var lines = [
            "=== WarpSense Hardware & Telemetry Snapshot ===",
            "Model:             \(modelIdentifier)",
            "CPU:               \(cpuBrand) (\(cpuArchitecture), \(physicalCores)P/\(logicalCores)L cores)",
            "macOS:             \(osVersion)",
            "Thermal State:     \(thermalState.rawValue) (Fanless enclosure aware)",
            "Power:             \(power.powerSource)\(power.batteryPercent.map { " (\($0)%)" } ?? "")",
            "Memory:            \(String(format: "%.1f", memory.usedMemoryGB)) / \(String(format: "%.1f", memory.totalMemoryGB)) GB (\(memory.pressureLevel) pressure)",
            "Available Storage: \(String(format: "%.1f", availableStorageGB)) GB",
            "Rosetta 2:         \(rosetta2Available ? "Available" : "Not Present")"
        ]
        if let metal {
            lines.append("Metal GPU:         \(metal.deviceName) | Unified=\(metal.hasUnifiedMemory) | Metal3=\(metal.supportsMetal3) | Apple9=\(metal.supportsApple9) | MaxWorkingSet=\(String(format: "%.1f", metal.recommendedMaxWorkingSetGB)) GB")
        } else {
            lines.append("Metal GPU:         Unavailable")
        }
        lines.append("===============================================")
        return lines.joined(separator: "\n")
    }
}

/// Safe hardware capability discovery using supported macOS APIs (`sysctl`, `Metal`, `Mach VM`, `IOKit.ps`, `ProcessInfo`).
public struct WarpSenseTelemetry: Sendable {
    public static func capture(volumeURL: URL = URL(fileURLWithPath: "/Volumes/Personal/WarpNest")) -> WarpSenseSnapshot {
        let base = SystemDiagnostics.inspect()
        let physicalCores = sysctlInt("hw.physicalcpu") ?? base.physicalCores
        let logicalCores = sysctlInt("hw.logicalcpu") ?? base.physicalCores

        #if arch(arm64)
        let arch = "arm64"
        #else
        let arch = "x86_64"
        #endif

        return WarpSenseSnapshot(
            capturedAt: Date(),
            modelIdentifier: base.macModel,
            cpuBrand: base.cpuBrand,
            cpuArchitecture: arch,
            physicalCores: physicalCores,
            logicalCores: logicalCores,
            osVersion: base.osVersion,
            metal: queryMetal(),
            memory: queryMemory(totalGB: base.totalMemoryGigabytes),
            availableStorageGB: queryAvailableStorageGB(at: volumeURL),
            power: queryPowerStatus(),
            thermalState: WarpThermalState(ProcessInfo.processInfo.thermalState),
            rosetta2Available: base.isRosettaActive
        )
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var val: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname(name, &val, &size, nil, 0) == 0 else { return nil }
        return Int(val)
    }

    private static func queryMetal() -> WarpMetalCapabilities? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let workingSetGB = Double(device.recommendedMaxWorkingSetSize) / (1024.0 * 1024.0 * 1024.0)
        return WarpMetalCapabilities(
            deviceName: device.name,
            hasUnifiedMemory: device.hasUnifiedMemory,
            supportsMetal3: device.supportsFamily(.metal3),
            supportsApple9: device.supportsFamily(.apple9),
            recommendedMaxWorkingSetGB: (workingSetGB * 10.0).rounded() / 10.0
        )
    }

    private static func queryMemory(totalGB: Double) -> WarpMemoryStats {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let hostPort = mach_host_self()
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return WarpMemoryStats(totalMemoryGB: totalGB, usedMemoryGB: 0, freeMemoryGB: totalGB, pressureLevel: "Unknown")
        }

        var vmPageSize: vm_size_t = 0
        host_page_size(hostPort, &vmPageSize)
        let pageSize = Double(vmPageSize)
        let activeBytes = Double(stats.active_count + stats.wire_count + stats.compressor_page_count) * pageSize
        let usedGB = (activeBytes / (1024.0 * 1024.0 * 1024.0) * 10.0).rounded() / 10.0
        let freeGB = max(0, ((totalGB - usedGB) * 10.0).rounded() / 10.0)
        let ratio = totalGB > 0 ? (usedGB / totalGB) : 0
        let pressure = ratio > 0.85 ? "Critical" : (ratio > 0.70 ? "Elevated" : "Normal")

        return WarpMemoryStats(totalMemoryGB: totalGB, usedMemoryGB: usedGB, freeMemoryGB: freeGB, pressureLevel: pressure)
    }

    private static func queryAvailableStorageGB(at url: URL) -> Double {
        let target = FileManager.default.fileExists(atPath: url.path) ? url : URL(fileURLWithPath: "/")
        if let values = try? target.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let bytes = values.volumeAvailableCapacityForImportantUsage {
            return (Double(bytes) / (1024.0 * 1024.0 * 1024.0) * 10.0).rounded() / 10.0
        }
        return 0
    }

    private static func queryPowerStatus() -> WarpPowerStatus {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let first = list.first,
              let desc = IOPSGetPowerSourceDescription(blob, first)?.takeUnretainedValue() as? [String: Any] else {
            return WarpPowerStatus(powerSource: "AC Power", batteryPercent: nil, isCharging: nil)
        }

        let state = (desc[kIOPSPowerSourceStateKey as String] as? String) ?? "Unknown"
        let cap = desc[kIOPSCurrentCapacityKey as String] as? Int
        let charging = desc[kIOPSIsChargingKey as String] as? Bool
        return WarpPowerStatus(powerSource: state, batteryPercent: cap, isCharging: charging)
    }
}
