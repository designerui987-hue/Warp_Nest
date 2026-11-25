import Foundation
import CoreGraphics
import ImageIO

struct WindowInfo {
    let id: CGWindowID
    let pid: pid_t
    let owner: String
    let name: String
    let bounds: CGRect
    let isOnscreen: Bool
    let layer: Int
}

func listWindows() -> [WindowInfo] {
    guard let windowListInfo = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
        return []
    }
    
    var results: [WindowInfo] = []
    for info in windowListInfo {
        let owner = info[kCGWindowOwnerName as String] as? String ?? ""
        let name = info[kCGWindowName as String] as? String ?? ""
        let pid = info[kCGWindowOwnerPID as String] as? pid_t ?? 0
        let id = info[kCGWindowNumber as String] as? CGWindowID ?? 0
        let layer = info[kCGWindowLayer as String] as? Int ?? 0
        let isOnscreen = info[kCGWindowIsOnscreen as String] as? Bool ?? false
        
        var bounds = CGRect.zero
        if let boundsDict = info[kCGWindowBounds as String] as? [String: Any] {
            bounds = CGRect(
                x: boundsDict["X"] as? CGFloat ?? 0,
                y: boundsDict["Y"] as? CGFloat ?? 0,
                width: boundsDict["Width"] as? CGFloat ?? 0,
                height: boundsDict["Height"] as? CGFloat ?? 0
            )
        }
        
        results.append(WindowInfo(id: id, pid: pid, owner: owner, name: name, bounds: bounds, isOnscreen: isOnscreen, layer: layer))
    }
    return results
}

func analyzePNG(path: String) -> (nonDarkPercent: Double, meanBrightness: Double, verdict: String)? {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let source = CGImageSourceCreateWithURL(url, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        return nil
    }
    
    let width = cgImage.width
    let height = cgImage.height
    guard width > 0, height > 0 else { return (0, 0, "EMPTY_IMAGE") }
    
    guard let dataProvider = cgImage.dataProvider,
          let data = dataProvider.data,
          let ptr = CFDataGetBytePtr(data) else {
        return (0, 0, "NO_DATA")
    }
    
    let bytesPerPixel = cgImage.bitsPerPixel / 8
    let bytesPerRow = cgImage.bytesPerRow
    let totalPixels = width * height
    
    var nonDarkCount = 0
    var totalBrightness: Double = 0
    
    for y in 0..<height {
        let rowStart = ptr + y * bytesPerRow
        for x in 0..<width {
            let pixel = rowStart + x * bytesPerPixel
            let b1 = Double(pixel[0])
            let b2 = Double(pixel[1])
            let b3 = Double(pixel[2])
            
            let brightness = (b1 + b2 + b3) / 3.0
            totalBrightness += brightness
            
            if brightness > 25.0 {
                nonDarkCount += 1
            }
        }
    }
    
    let nonDarkPercent = (Double(nonDarkCount) / Double(totalPixels)) * 100.0
    let meanBrightness = totalBrightness / Double(totalPixels)
    
    let verdict: String
    if nonDarkPercent < 5.0 {
        verdict = "BLACK_SCREEN"
    } else if meanBrightness > 250.0 && nonDarkPercent > 98.0 {
        verdict = "BLANK_WHITE_SCREEN"
    } else {
        verdict = "RENDERED_UI"
    }
    
    return (nonDarkPercent, meanBrightness, verdict)
}

func runScreencapture(args: [String]) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = args
    try? process.run()
    process.waitUntilExit()
}

// Main execution
let windows = listWindows().filter { w in
    let o = w.owner.lowercased()
    let n = w.name.lowercased()
    
    // Ignore unrelated apps or system windows
    if o.contains("antigravity") || o.contains("xcode") || o.contains("terminal") {
        return false
    }
    // Ignore crash debuggers and error dialogs
    if n.contains("debugger") || n.contains("program error") || n.contains("crash") {
        return false
    }
    
    return o.contains("wine") || o.contains("steam") || n.contains("steam")
}

print("=== WarpNest UI Scanner ===")
print("Found \(windows.count) candidate Wine/Steam windows.")

var anyVisibleRendered = false

for w in windows {
    print("\nWindow ID: \(w.id) | PID: \(w.pid) | Owner: '\(w.owner)' | Title: '\(w.name)'")
    print("  Bounds: \(w.bounds) | Layer: \(w.layer) | OnScreen: \(w.isOnscreen)")
    
    // Only capture windows with meaningful dimensions (> 100x100)
    if w.bounds.width >= 100 && w.bounds.height >= 100 {
        let winSavePath = "/Volumes/Personal/WarpNest/scratch/win_\(w.id).png"
        runScreencapture(args: ["-l", "\(w.id)", "-o", winSavePath])
        
        if FileManager.default.fileExists(atPath: winSavePath),
           let analysis = analyzePNG(path: winSavePath) {
            print("  Capture Saved: \(winSavePath)")
            print("  Analysis: Non-Dark: \(String(format: "%.1f", analysis.nonDarkPercent))% | Mean Brightness: \(String(format: "%.1f", analysis.meanBrightness)) | Verdict: \(analysis.verdict)")
            
            let isSteamTitle = w.name.lowercased().contains("steam") || w.name.lowercased().contains("sign in")
            if analysis.verdict == "RENDERED_UI" && isSteamTitle {
                anyVisibleRendered = true
                print("  ==> SUCCESS: Visible rendered Steam UI confirmed for window \(w.id) ('\(w.name)')!")
            }
        } else {
            print("  Failed to capture or analyze image for window \(w.id)")
        }
    }
}

// Also capture full display to verify overall screen state
let screenSavePath = "/Volumes/Personal/WarpNest/scratch/full_screen_scan.png"
runScreencapture(args: ["-x", screenSavePath])
if let screenAnalysis = analyzePNG(path: screenSavePath) {
    print("\nFull Display Scan: Non-Dark: \(String(format: "%.1f", screenAnalysis.nonDarkPercent))% | Brightness: \(String(format: "%.1f", screenAnalysis.meanBrightness))")
}

if anyVisibleRendered {
    exit(0)
} else {
    exit(1)
}
