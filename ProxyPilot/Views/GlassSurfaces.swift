import SwiftUI

private struct ProxyPilotLiquidGlassEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var proxypilotLiquidGlassEnabled: Bool {
        get { self[ProxyPilotLiquidGlassEnabledKey.self] }
        set { self[ProxyPilotLiquidGlassEnabledKey.self] = newValue }
    }
}

enum GlassNavigationSurfacePolicy {
    static func usesLiquidGlass(
        platformAvailable: Bool,
        liquidGlassEnabled: Bool,
        reduceTransparency: Bool
    ) -> Bool {
        platformAvailable && liquidGlassEnabled && !reduceTransparency
    }
}

struct GlassNavigationSurface<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.proxypilotLiquidGlassEnabled) private var liquidGlassEnabled

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    private var platformAvailable: Bool {
        if #available(macOS 26.0, *) {
            return true
        }
        return false
    }

    private var usesLiquidGlass: Bool {
        GlassNavigationSurfacePolicy.usesLiquidGlass(
            platformAvailable: platformAvailable,
            liquidGlassEnabled: liquidGlassEnabled,
            reduceTransparency: reduceTransparency
        )
    }

    @ViewBuilder
    var body: some View {
        if #available(macOS 26.0, *), usesLiquidGlass {
            content
                .glassEffect(.regular, in: Rectangle())
                .overlay(alignment: .trailing) {
                    navigationSeparator
                }
        } else {
            content
                .background(Color(nsColor: .windowBackgroundColor))
                .overlay(alignment: .trailing) {
                    navigationSeparator
                }
        }
    }

    private var navigationSeparator: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.65))
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .accessibilityHidden(true)
    }
}

struct GlassControlGroup<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.proxypilotLiquidGlassEnabled) private var liquidGlassEnabled

    private let cornerRadius: CGFloat
    private let padding: CGFloat
    private let content: Content

    init(
        cornerRadius: CGFloat = 18,
        padding: CGFloat = 4,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        if #available(macOS 26.0, *), liquidGlassEnabled, !reduceTransparency {
            GlassEffectContainer(spacing: 8) {
                content
                    .padding(padding)
                    .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        } else {
            content
                .padding(padding)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.secondary.opacity(0.16))
                }
        }
    }
}

struct DashboardCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
