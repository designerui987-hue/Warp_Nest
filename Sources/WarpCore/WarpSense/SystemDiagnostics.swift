import Foundation

/// System diagnostics and hardware capability detection.
public struct SystemDiagnostics: Sendable {
    public let macModel: String
    public let cpuBrand: String
    public let physicalCores: Int
    public let totalMemoryGigabytes: Double
    public let osVersion: String
    public let isRosettaActive: Bool
    public let isAppleSilicon: Bool

    public static func inspect() -> SystemDiagnostics {
        var size: Int = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var modelChars = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &modelChars, &size, nil, 0)
        let macModel = modelChars.withUnsafeBufferPointer { ptr in
            String(cString: ptr.baseAddress!)
        }

        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var brandChars = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("machdep.cpu.brand_string", &brandChars, &size, nil, 0)
        let cpuBrand = brandChars.withUnsafeBufferPointer { ptr in
            String(cString: ptr.baseAddress!)
        }

        var ncpu: Int32 = 0
        var ncpuSize = MemoryLayout<Int32>.size
        sysctlbyname("hw.ncpu", &ncpu, &ncpuSize, nil, 0)

        var memSize: UInt64 = 0
        var memLength = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &memSize, &memLength, nil, 0)
        let memoryGB = Double(memSize) / (1024.0 * 1024.0 * 1024.0)

        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString

        // Rosetta detection
        let rosettaPath = "/Library/Apple/usr/libexec/oah/libRosettaRuntime"
        let isRosettaActive = FileManager.default.fileExists(atPath: rosettaPath)

        #if arch(arm64)
        let isAppleSilicon = true
        #else
        let isAppleSilicon = false
        #endif

        return SystemDiagnostics(
            macModel: macModel,
            cpuBrand: cpuBrand,
            physicalCores: Int(ncpu),
            totalMemoryGigabytes: (memoryGB * 10.0).rounded() / 10.0,
            osVersion: osVersion,
            isRosettaActive: isRosettaActive,
            isAppleSilicon: isAppleSilicon
        )
    }

    public func summaryReport() -> String {
        """
        === WarpSense System Telemetry ===
        Hardware Model: \(macModel)
        Processor:      \(cpuBrand) (\(physicalCores) Cores)
        Architecture:   \(isAppleSilicon ? "ARM64 (Apple Silicon)" : "x86_64")
        Unified Memory: \(totalMemoryGigabytes) GB
        Operating Sys:  \(osVersion)
        Rosetta Runtime:\(isRosettaActive ? " Active (/Library/Apple/usr/libexec/oah/libRosettaRuntime)" : " Not Found")
        Rosetta EOL:    macOS 27 is the final release for general-purpose support.
        ==================================
        """
    }
}
