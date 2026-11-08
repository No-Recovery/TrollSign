import SwiftUI
import UIKit

// MARK: - Liquid Glass theme

enum LiquidTheme {
    static let accent = Color(red: 0.42, green: 0.56, blue: 1.00)
    static let violet = Color(red: 0.68, green: 0.44, blue: 1.00)
    static let aqua   = Color(red: 0.28, green: 0.90, blue: 0.84)
    static let pink   = Color(red: 1.00, green: 0.43, blue: 0.72)
}

/// Soft, animated-looking backdrop. It is intentionally static (no timers) so
/// scrolling and signing stay at 120 Hz on ProMotion devices.
struct LiquidBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            (scheme == .dark
             ? Color(red: 0.030, green: 0.035, blue: 0.065)
             : Color(red: 0.945, green: 0.955, blue: 1.000))

            LinearGradient(
                colors: scheme == .dark
                    ? [Color(red: 0.08, green: 0.10, blue: 0.21), Color(red: 0.03, green: 0.04, blue: 0.08)]
                    : [Color.white, Color(red: 0.90, green: 0.93, blue: 1.00)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(LiquidTheme.accent.opacity(scheme == .dark ? 0.30 : 0.20))
                .frame(width: 360, height: 360)
                .blur(radius: 95)
                .offset(x: -150, y: -300)

            Circle()
                .fill(LiquidTheme.violet.opacity(scheme == .dark ? 0.24 : 0.16))
                .frame(width: 320, height: 320)
                .blur(radius: 105)
                .offset(x: 165, y: -90)

            Circle()
                .fill(LiquidTheme.aqua.opacity(scheme == .dark ? 0.15 : 0.13))
                .frame(width: 280, height: 280)
                .blur(radius: 95)
                .offset(x: 110, y: 340)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Glass panel

private struct GlassPanelModifier: ViewModifier {
    let corner: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [
                                        .white.opacity(scheme == .dark ? 0.34 : 0.78),
                                        .white.opacity(0.05)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }
                    .shadow(color: .black.opacity(scheme == .dark ? 0.34 : 0.11),
                            radius: 22, x: 0, y: 12)
            }
    }
}

extension View {
    /// Native Liquid Glass on iOS 26+, a very close material fallback below it.
    @ViewBuilder
    func glassPanel(corner: CGFloat = 24) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
        } else {
            self.modifier(GlassPanelModifier(corner: corner))
        }
        #else
        self.modifier(GlassPanelModifier(corner: corner))
        #endif
    }

    /// Transparent scroll view over the liquid background.
    func liquidScreen() -> some View {
        self
            .background(LiquidBackground())
            .scrollContentBackground(.hidden)
    }
}

// MARK: - Reusable glass rows

struct GlassSection<Content: View>: View {
    let title: String?
    let footer: String?
    let content: Content

    init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 18)
            }

            VStack(spacing: 0) { content }
                .glassPanel(corner: 26)

            if let footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 18)
            }
        }
    }
}

struct GlassRow<Trailing: View>: View {
    let title: String
    let icon: String?
    let subtitle: String?
    let tint: Color
    let trailing: Trailing

    init(_ title: String,
         icon: String? = nil,
         subtitle: String? = nil,
         tint: Color = LiquidTheme.accent,
         @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.icon = icon
        self.subtitle = subtitle
        self.tint = tint
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 31, height: 31)
                    .background {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(LinearGradient(colors: [tint, tint.opacity(0.62)],
                                                 startPoint: .topLeading,
                                                 endPoint: .bottomTrailing))
                            .shadow(color: tint.opacity(0.35), radius: 8, x: 0, y: 4)
                    }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

extension GlassRow where Trailing == EmptyView {
    init(_ title: String,
         icon: String? = nil,
         subtitle: String? = nil,
         tint: Color = LiquidTheme.accent) {
        self.init(title, icon: icon, subtitle: subtitle, tint: tint) { EmptyView() }
    }
}

struct GlassDivider: View {
    var body: some View {
        Divider().padding(.leading, 57).opacity(0.55)
    }
}

struct GlassChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.tertiary)
    }
}

// MARK: - Floating tab bar

struct GlassTabBar: View {
    @Binding var selection: Int
    var onLongPressSettings: () -> Void
    @Namespace private var animation

    var body: some View {
        HStack(spacing: 4) {
            tab(index: 0, title: "Apps", icon: "square.stack.3d.up.fill")
            tab(index: 1, title: "Settings", icon: "gearshape.fill")
                .onLongPressGesture(minimumDuration: 0.55) {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onLongPressSettings()
                }
        }
        .padding(5)
        .glassPanel(corner: 32)
        .padding(.horizontal, 52)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private func tab(index: Int, title: String, icon: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
            if selection == index {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }
        }
        .foregroundStyle(selection == index ? .primary : .secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background {
            if selection == index {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().strokeBorder(.white.opacity(0.24), lineWidth: 1))
                    .matchedGeometryEffect(id: "selectedTab", in: animation)
            }
        }
        .contentShape(Capsule())
        .onTapGesture {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                selection = index
            }
        }
        .accessibilityAddTraits(.isButton)
    }
}
