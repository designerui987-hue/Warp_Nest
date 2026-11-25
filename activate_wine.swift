import Cocoa

let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "org.winehq.wine") + NSRunningApplication.runningApplications(withBundleIdentifier: "com.valvesoftware.steam")

print("Found matching bundle apps: \(apps.count)")

// Also look for apps with 'wine' in localizedName or executableURL
let allApps = NSWorkspace.shared.runningApplications
for app in allApps {
    let name = app.localizedName ?? ""
    let exec = app.executableURL?.lastPathComponent ?? ""
    if name.lowercased().contains("wine") || exec.lowercased().contains("wine") || name.lowercased().contains("steam") || exec.lowercased().contains("steam") {
        print("Found app: name='\(name)', exec='\(exec)', pid=\(app.processIdentifier), isHidden=\(app.isHidden), isActive=\(app.isActive)")
        let success = app.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        print("Activation result: \(success)")
    }
}
