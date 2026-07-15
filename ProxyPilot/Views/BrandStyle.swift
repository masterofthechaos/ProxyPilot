import AppKit
import SwiftUI

/// Hues sampled directly from the app icon's circuit trail (pink -> violet -> blue-violet).
/// Distinct from `vm.proxyPilotAccentColor`, which is user-customizable; these stay fixed
/// as the app's brand identity.
enum ProxyPilotBrandPalette {
    static let pink = Color(proxyPilotHex: "#F678C0")
    static let violet = Color(proxyPilotHex: "#B27DFB")
    static let blueViolet = Color(proxyPilotHex: "#7674FD")
}

/// Icon + wordmark, styled to echo the website nav brand. Text uses the system font
/// (not the website's bundled Inter) to stay native on macOS.
struct ProxyPilotBrandMark: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                .resizable()
                .interpolation(.high)
                .frame(width: 18, height: 18)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .shadow(color: ProxyPilotBrandPalette.violet.opacity(0.35), radius: 4, y: 1)

            Text(AppBuildBadge.currentAppDisplayName)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.primary)
        }
        .padding(.trailing, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(AppBuildBadge.currentAppDisplayName)
    }
}

/// Two soft radial washes anchored at opposite corners, tinted with the brand palette.
/// Opacity is tuned down sharply in light mode, where tinted color reads much more
/// readily against a white base than it does against a dark one.
private struct ProxyPilotAmbientBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    private var washOpacity: Double {
        colorScheme == .dark ? 0.14 : 0.05
    }

    func body(content: Content) -> some View {
        content.background {
            ZStack {
                Color(nsColor: .windowBackgroundColor)

                RadialGradient(
                    colors: [ProxyPilotBrandPalette.pink.opacity(washOpacity), .clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: 480
                )

                RadialGradient(
                    colors: [ProxyPilotBrandPalette.blueViolet.opacity(washOpacity), .clear],
                    center: .bottomLeading,
                    startRadius: 0,
                    endRadius: 480
                )
            }
            .ignoresSafeArea()
        }
    }
}

extension View {
    func proxyPilotAmbientBackground() -> some View {
        modifier(ProxyPilotAmbientBackground())
    }
}
