import SwiftUI

@main
struct TrollSignApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var certs = CertStore()
    @AppStorage("urlSchemeEnabled") private var urlSchemeEnabled = true

    init() {
        // Ready hosting is the zero-setup default. GitHub hosting can be
        // selected later in Settings → Hosting after adding a token.
        if UserDefaults.standard.string(forKey: "hostingProvider") == nil {
            UserDefaults.standard.set(HostingProvider.ready.rawValue, forKey: "hostingProvider")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(certs)
                .tint(LiquidTheme.accent)
                .onOpenURL { url in
                    if url.isFileURL {                       // "Open in…" for .ipa
                        store.request(.local(url))
                    } else if urlSchemeEnabled,
                              url.scheme == "trollsign" || url.scheme == "trollstorelite",
                              url.host == "install",
                              let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                                .queryItems?.first(where: { $0.name == "url" })?.value,
                              let remote = URL(string: q) {
                        store.request(.remote(remote))
                    }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var certs: CertStore
    @EnvironmentObject var store: AppStore
    @State private var selection = 0
    @State private var showCertificates = false

    var body: some View {
        Group {
            switch selection {
            case 1: SettingsView()
            default: AppsView()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            GlassTabBar(selection: $selection) {
                showCertificates = true
            }
        }
        .sheet(isPresented: $showCertificates) {
            NavigationStack {
                CertificatesView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showCertificates = false }
                        }
                    }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .onAppear { store.certs = certs }
    }
}
