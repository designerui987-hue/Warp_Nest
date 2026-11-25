import SwiftUI
import WarpCore

/// Reusable status pill adhering strictly to Principles #1 and #11 (accurate status labeling).
struct StatusPill: View {
    let label: String
    let color: Color

    init(_ label: String, color: Color) {
        self.label = label
        self.color = color
    }

    init(status: CompatibilityStatus) {
        self.label = status.rawValue
        self.color = status.badgeColor
    }

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(color.opacity(0.14))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(color.opacity(0.35), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

/// Consistent dark card container with hairline border.
struct WarpCard<Content: View>: View {
    let title: String?
    let subtitle: String?
    @ViewBuilder let content: () -> Content

    init(title: String? = nil, subtitle: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(WarpTheme.primaryText)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 12))
                            .foregroundStyle(WarpTheme.mutedText)
                    }
                }
            }
            content()
        }
        .padding(WarpTheme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WarpTheme.surface)
        .overlay(
            RoundedRectangle(cornerRadius: WarpTheme.cornerRadius)
                .stroke(WarpTheme.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: WarpTheme.cornerRadius))
    }
}

/// Key-value row for telemetry and metadata tables.
struct MetadataRow: View {
    let label: String
    let value: String
    let monospaced: Bool

    init(_ label: String, value: String, monospaced: Bool = false) {
        self.label = label
        self.value = value
        self.monospaced = monospaced
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(WarpTheme.mutedText)
                .frame(width: 155, alignment: .leading)
            Text(value)
                .font(monospaced ? .system(size: 12, design: .monospaced) : .system(size: 12, weight: .medium))
                .foregroundStyle(WarpTheme.primaryText)
                .textSelection(.enabled)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

/// Empty, loading, or error state view with optional action button.
struct WarpStateView: View {
    let icon: String
    let title: String
    let message: String
    let tint: Color
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        icon: String,
        title: String,
        message: String,
        tint: Color = WarpTheme.mutedText,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.tint = tint
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(tint)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(WarpTheme.primaryText)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(WarpTheme.mutedText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(WarpPrimaryButtonStyle())
                    .padding(.top, 4)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WarpPrimaryButtonStyle: ButtonStyle {
    var color: Color = WarpTheme.violet

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(color.opacity(configuration.isPressed ? 0.78 : 1.0))
            .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

struct WarpSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(WarpTheme.primaryText)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(WarpTheme.surfaceElevated.opacity(configuration.isPressed ? 0.7 : 1.0))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(WarpTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

struct ScreenHeader: View {
    let title: String
    let subtitle: String
    var badge: (String, Color)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(WarpTheme.primaryText)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(WarpTheme.mutedText)
            }
            Spacer()
            if let badge {
                StatusPill(badge.0, color: badge.1)
            }
        }
        .padding(.bottom, 4)
    }
}
