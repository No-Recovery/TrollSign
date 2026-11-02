import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject var certs: CertStore
    @AppStorage("urlSchemeEnabled") private var urlSchemeEnabled = true
    @AppStorage("confirmMode") private var confirmMode = 0
    @State private var hint = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Show Install Confirmation Alert", selection: $confirmMode) {
                        Text("Always (Recommended)").tag(0)
                        Text("Only on Remote URL Installs").tag(1)
                        Text("Never (Not Recommended)").tag(2)
                    }
                    .pickerStyle(.navigationLink)
                }

                Section {
                    Toggle("URL Scheme Enabled", isOn: $urlSchemeEnabled)
                } footer: {
                    Text("The URL scheme allows apps and websites to trigger installations through trollsign://install?url=<IPA_URL> (the old trollstorelite:// scheme still works).")
                }

                Section {
                    NavigationLink {
                        GitHubHostingView()
                    } label: {
                        Label("GitHub Hosting", systemImage: "icloud.and.arrow.up")
                    }
                } footer: {
                    Text("Publish signed IPAs to GitHub Releases and install them through GitHub Pages over HTTPS — no local server or localhost.direct certificate needed.")
                }

                // Certificates used to be a separate hidden tab. It now lives here:
                // unlock it with a 1.5 s long press on the version row below.
                if certs.hiddenTabUnlocked {
                    Section {
                        NavigationLink {
                            CertificatesView()
                        } label: {
                            Label("Certificates", systemImage: "key.fill")
                        }
                    } header: {
                        Text("Advanced")
                    } footer: {
                        Text("Signing certificates, the local installation server and the server certificate are configured here.")
                    }
                }

                Section {
                    NavigationLink("Advanced") { AdvancedView() }
                }

                Section {
                    Text("TrollSign 2.2")
                        .font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .contentShape(Rectangle())
                        .onLongPressGesture(minimumDuration: 1.5) {
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            certs.hiddenTabUnlocked.toggle()
                            hint = true
                        }
                        .listRowBackground(Color.clear)
                } footer: {
                    if hint {
                        Text(certs.hiddenTabUnlocked
                             ? "Certificates unlocked — see Settings → Advanced → Certificates."
                             : "Certificates hidden again.")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
        }
    }
}

struct AdvancedView: View {
    @EnvironmentObject var store: AppStore
    @State private var message: String?

    var body: some View {
        List {
            Section {
                Button("Rebuild Icon Cache") { store.rebuildIcons(); message = "Icons reloaded." }
                Button("Clear Signed Cache", role: .destructive) { store.clearSigned(); message = "Signed IPAs removed." }
            } footer: { if let message { Text(message) } }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Advanced")
        .navigationBarTitleDisplayMode(.inline)
    }
}
