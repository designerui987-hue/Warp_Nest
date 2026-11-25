import SwiftUI
import WarpCore

/// WarpNest native dark gaming design tokens: graphite & midnight surfaces with restrained violet & electric-blue accents.
enum WarpTheme {
    // Surfaces
    static let midnight = Color(red: 0.043, green: 0.051, blue: 0.071)       // #0B0D12
    static let graphite = Color(red: 0.067, green: 0.075, blue: 0.094)       // #111318
    static let surface = Color(red: 0.094, green: 0.106, blue: 0.133)        // #181B22
    static let surfaceElevated = Color(red: 0.122, green: 0.137, blue: 0.173) // #1F232C
    static let border = Color(red: 0.176, green: 0.196, blue: 0.247)         // #2D323F

    // Accents
    static let violet = Color(red: 0.486, green: 0.361, blue: 1.000)         // #7C5CFF
    static let electricBlue = Color(red: 0.231, green: 0.510, blue: 0.965)   // #3B82F6

    // Semantic Status
    static let verifiedGreen = Color(red: 0.133, green: 0.773, blue: 0.369)  // #22C55E
    static let warningAmber = Color(red: 0.961, green: 0.620, blue: 0.043)   // #F59E0B
    static let blockedRed = Color(red: 0.937, green: 0.267, blue: 0.267)     // #EF4444
    static let mutedText = Color(red: 0.580, green: 0.639, blue: 0.722)      // #94A3B8
    static let primaryText = Color(red: 0.945, green: 0.961, blue: 0.976)    // #F1F5F9

    static let cornerRadius: CGFloat = 10
    static let cardPadding: CGFloat = 16
}

extension CompatibilityStatus {
    var badgeColor: Color {
        switch self {
        case .verified: return WarpTheme.verifiedGreen
        case .experimental: return WarpTheme.warningAmber
        case .blocked: return WarpTheme.blockedRed
        case .unsupported: return WarpTheme.mutedText
        }
    }
}
