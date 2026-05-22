import SwiftUI

// MARK: - Traces visual system
// Centralizes app styling so the UI looks consistent and individual feature
// views do not hard-code random backgrounds, borders, shadows, or badges.

enum TracesTheme {
    static let appBackground = Color(nsColor: .windowBackgroundColor)
    static let panelBackground = Color(nsColor: .controlBackgroundColor)
    static let elevatedBackground = Color(nsColor: .textBackgroundColor)
    static let softBorder = Color.primary.opacity(0.08)
    static let strongerBorder = Color.primary.opacity(0.14)
    static let mutedText = Color.secondary
    static let warning = Color.orange
    static let success = Color.green
    static let info = Color.accentColor

    static let panelCornerRadius: CGFloat = 18
    static let cardCornerRadius: CGFloat = 14
}

struct TracesPanel<Content: View>: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let trailing: AnyView?
    @ViewBuilder let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        trailing: AnyView? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(Color.accentColor.opacity(0.14))
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer(minLength: 10)

                if let trailing {
                    trailing
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()
                .opacity(0.55)

            content
        }
        .background(
            RoundedRectangle(cornerRadius: TracesTheme.panelCornerRadius)
                .fill(TracesTheme.panelBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: TracesTheme.panelCornerRadius)
                .stroke(TracesTheme.softBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.055), radius: 14, x: 0, y: 8)
        .clipShape(RoundedRectangle(cornerRadius: TracesTheme.panelCornerRadius))
    }
}

struct TracesBadge: View {
    let text: String
    let systemImage: String?
    let tint: Color

    init(_ text: String, systemImage: String? = nil, tint: Color = .accentColor) {
        self.text = text
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
            }
            Text(text)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(tint)
        .background(tint.opacity(0.13), in: Capsule())
        .overlay(Capsule().stroke(tint.opacity(0.18), lineWidth: 1))
    }
}

struct TracesIconButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(prominent ? Color.accentColor : Color.primary.opacity(configuration.isPressed ? 0.10 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(prominent ? Color.clear : TracesTheme.strongerBorder, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct TracesStatusBanner: View {
    let status: String
    let isLoading: Bool

    var body: some View {
        if !status.isEmpty || isLoading {
            HStack(alignment: .top, spacing: 8) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: status.lowercased().contains("failed") ? "exclamationmark.triangle.fill" : "info.circle.fill")
                        .foregroundStyle(status.lowercased().contains("failed") ? TracesTheme.warning : Color.accentColor)
                }

                Text(isLoading ? status : status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)

                Spacer(minLength: 0)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor.opacity(isLoading ? 0.10 : 0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor.opacity(0.13), lineWidth: 1)
            )
        }
    }
}
