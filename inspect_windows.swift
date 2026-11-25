import Cocoa
import CoreGraphics

let options: CGWindowListOption = [.optionAll]
if let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] {
    print("Total windows found: \(list.count)")
    for win in list {
        let owner = win[kCGWindowOwnerName as String] as? String ?? ""
        let name = win[kCGWindowName as String] as? String ?? ""
        let bounds = win[kCGWindowBounds as String] as? [String: Any] ?? [:]
        let wid = win[kCGWindowNumber as String] as? Int ?? 0
        let layer = win[kCGWindowLayer as String] as? Int ?? 0
        let isOnscreen = win[kCGWindowIsOnscreen as String] as? Bool ?? false
        let mem = win[kCGWindowMemoryUsage as String] as? Int ?? 0
        let pid = win[kCGWindowOwnerPID as String] as? Int32 ?? 0
        
        if owner.lowercased().contains("wine") || owner.lowercased().contains("steam") || name.lowercased().contains("steam") || name.lowercased().contains("sign in") {
            print("[WINE/STEAM] PID: \(pid) | Owner: \(owner) | Name: '\(name)' | ID: \(wid) | Layer: \(layer) | OnScreen: \(isOnscreen) | Mem: \(mem) | Bounds: \(bounds)")
        }
    }
}
