import SwiftUI

@main
struct TrollSignApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var certs = CertStore()
    @AppStorage("urlSchemeEnabled") private var urlSchemeEnabled = true

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(certs)
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

    var body: some View {
        TabView(selection: $selection) {
            AppsView()
                .tabItem { Label("Apps", systemImage: "square.stack.3d.up.fill") }
                .tag(0)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(1)
        }
        .onAppear { store.certs = certs }
    }
}
