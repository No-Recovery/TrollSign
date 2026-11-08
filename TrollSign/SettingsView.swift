import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject var certs: CertStore
    @EnvironmentObject var store: AppStore
    @AppStorage("urlSchemeEnabled") private var urlSchemeEnabled = true
    @AppStorage("confirmMode") private var confirmMode = 0

    @State private var message: String?
    @State private var respringFailed = false

    private var confirmationTitle: String {
        switch confirmMode {
        case 1:  return "Only remote URL installs"
        case 2:  return "Never"
        default: return "Always"
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackground()

                ScrollView {
                    VStack(spacing: 18) {
                        header

                        GlassSection("Installation",
                                     footer: "The URL scheme allows apps and websites to start an install with trollsign://install?url=<IPA_URL>. The old trollstorelite:// scheme still works.") {
                            GlassRow("Install confirmation",
                                     icon: "checkmark.shield.fill",
                                     subtitle: confirmationTitle) {
                                Picker("Install confirmation", selection: $confirmMode) {
                                    Text("Always").tag(0)
                                    Text("Remote only").tag(1)
                                    Text("Never").tag(2)
                                }
                                .pickerStyle(.menu)
                                .labelsHidden()
                            }

                            GlassDivider()

                            GlassRow("URL scheme",
                                     icon: "link",
                                     subtitle: "trollsign://install?url=…") {
                                Toggle("URL scheme", isOn: $urlSchemeEnabled)
                                    .labelsHidden()
                            }
                        }

                        GlassSection("Hosting",
                                     footer: "Ready hosting works with no account. GitHub hosting is optional and publishes to your own repository.") {
                            NavigationLink {
                                HostingView()
                            } label: {
                                GlassRow("Hosting",
                                         icon: "icloud.and.arrow.up.fill",
                                         subtitle: HostingConfig.statusText) {
                                    GlassChevron()
                                }
                            }
                            .buttonStyle(.plain)

                            if let page = HostingConfig.installPage {
                                GlassDivider()

                                Link(destination: page) {
                                    GlassRow("Open install page",
                                             icon: "safari.fill",
                                             subtitle: page.host ?? page.absoluteString,
                                             tint: LiquidTheme.aqua) {
                                        GlassChevron()
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        GlassSection("Maintenance") {
                            Button {
                                store.rebuildIcons()
                                message = "Icon cache rebuilt."
                            } label: {
                                GlassRow("Rebuild icon cache",
                                         icon: "photo.on.rectangle.angled",
                                         tint: LiquidTheme.violet)
                            }
                            .buttonStyle(.plain)

                            GlassDivider()

                            Button {
                                store.clearSigned()
                                message = "Signed IPAs removed."
                            } label: {
                                GlassRow("Clear signed cache",
                                         icon: "trash.fill",
                                         subtitle: "Keeps your original IPA files",
                                         tint: .red)
                            }
                            .buttonStyle(.plain)

                            GlassDivider()

                            Button {
                                respring()
                            } label: {
                                GlassRow("Respring",
                                         icon: "arrow.clockwise",
                                         subtitle: "Restart SpringBoard like TrollStore",
                                         tint: LiquidTheme.pink)
                            }
                            .buttonStyle(.plain)
                        }

                        if let message {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .transition(.opacity)
                        }

                        footer
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Settings")
            .alert("Respring unavailable", isPresented: $respringFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("SpringBoard refused the restart request. Close TrollSign and reopen it, then try again. TrollStore-signed builds and TrollStore itself can always respring.")
            }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LinearGradient(colors: [LiquidTheme.accent, LiquidTheme.violet],
                                         startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
                    .frame(width: 74, height: 74)
                    .shadow(color: LiquidTheme.accent.opacity(0.45), radius: 18, x: 0, y: 10)

                Image(systemName: "signature")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: 3) {
                Text("TrollSign")
                    .font(.title2.weight(.bold))
                Text("Version 2.3 · Liquid Glass")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                statusPill(text: certs.selected?.name ?? "No certificate",
                           icon: certs.selected == nil ? "exclamationmark.triangle.fill" : "checkmark.seal.fill",
                           color: certs.selected == nil ? .orange : .green)

                statusPill(text: HostingConfig.provider == .ready ? "Hosting ready" : "GitHub",
                           icon: "antenna.radiowaves.left.and.right",
                           color: HostingConfig.provider == .ready ? LiquidTheme.aqua : LiquidTheme.violet)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 16)
        .glassPanel(corner: 30)
    }

    private func statusPill(text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10, weight: .bold))
            Text(text).font(.caption2.weight(.semibold)).lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(color.opacity(0.14), in: Capsule())
        .overlay(Capsule().strokeBorder(color.opacity(0.24), lineWidth: 1))
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text("TrollSign 2.3")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }

    private func respring() {
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        if !Respring.perform() {
            respringFailed = true
        }
    }
}
