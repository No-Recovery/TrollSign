import SwiftUI
import UIKit

struct CertificatesView: View {
    @EnvironmentObject var certs: CertStore
    @State private var showAdd = false
    @AppStorage("serverHost") private var serverHost = ""
    @AppStorage("serverPort") private var serverPort = 8443
    @State private var showServerPicker = false
    @State private var pickedServerP12: URL?
    @State private var serverPassword = ""
    @State private var askPassword = false
    @State private var serverStatus: String?
    @State private var hasServerCert = ServerConfig.hasCert

    var body: some View {
        List {
            if certs.certs.isEmpty {
                Text("No certificates. Tap + to add a .p12 and a .mobileprovision.")
                    .foregroundStyle(.secondary)
            }
            ForEach(certs.certs) { c in
                Button { certs.selectedID = c.id } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.name).foregroundStyle(.primary)
                            Text(c.teamName).font(.footnote).foregroundStyle(.secondary)
                            if let e = c.expiration {
                                Text("Expires \(e.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.footnote).foregroundStyle(c.isExpired ? .red : .secondary)
                            }
                        }
                        Spacer()
                        if certs.selected?.id == c.id { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                }
                .swipeActions { Button("Delete", role: .destructive) { certs.remove(c) } }
            }

            Section {
                TextField("Host (default: localhost.direct)", text: $serverHost)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                HStack { Text("Port"); Spacer()
                    TextField("8443", value: $serverPort, format: .number.grouping(.never))
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 90) }
                Button { showServerPicker = true } label: {
                    HStack { Text("Server certificate (.p12)").foregroundStyle(.primary); Spacer()
                        Text(hasServerCert ? (ServerConfig.hasImportedCert ? "Imported" : "Built-in") : "Choose…").foregroundStyle(.secondary) }
                }
                Button("Test Server") {
                    serverStatus = "Testing…"
                    Task { serverStatus = await LocalServer.shared.selfTest() }
                }
            } header: { Text("Local Installation Server") } footer: {
                Text("Only used when GitHub Hosting is off. Installation goes through itms-services, which needs HTTPS. By default it uses localhost.direct with the server.p12 built into the app; you can override both here. \(serverStatus ?? "")")
            }
        }
        .listStyle(.insetGrouped)
        .sheet(isPresented: $showServerPicker) {
            DocumentPicker(onPick: { url in
                showServerPicker = false
                let ext = url.pathExtension.lowercased()
                if ["p12", "pfx"].contains(ext) { pickedServerP12 = url; askPassword = true }
                else { serverStatus = "Choose a .p12 file (got .\(ext))" }
            }, onCancel: { showServerPicker = false })
        }
        .alert("Server certificate password", isPresented: $askPassword) {
            SecureField("Password", text: $serverPassword)
            Button("Import") {
                do { if let u = pickedServerP12 { try ServerConfig.importP12(from: u, password: serverPassword) }
                     hasServerCert = ServerConfig.hasCert; serverStatus = "Certificate imported." }
                catch { serverStatus = error.localizedDescription }
                serverPassword = ""
            }
            Button("Cancel", role: .cancel) { serverPassword = "" }
        }
        .navigationTitle("Certificates")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showAdd) { AddCertView() }
    }
}

struct AddCertView: View {
    @EnvironmentObject var certs: CertStore
    @Environment(\.dismiss) private var dismiss

    enum Kind: String, Identifiable { case p12, prov; var id: String { rawValue } }

    @State private var p12: URL?
    @State private var prov: URL?
    @State private var password = ""
    @State private var picking: Kind?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    pickRow(".p12 certificate", p12) { picking = .p12 }
                    pickRow(".mobileprovision", prov) { picking = .prov }
                    SecureField("Password", text: $password)
                } footer: { Text("The password is stored in the Keychain. Files stay inside the app.") }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Add Certificate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard let p12, let prov else { return }
                        do { try certs.add(p12: p12, prov: prov, password: password); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }.disabled(p12 == nil || prov == nil)
                }
            }
            // sheet(item:) — вид файла передаётся в замыкание, а не читается из @State (это и ломало выбор)
            .sheet(item: $picking) { kind in
                DocumentPicker(onPick: { url in
                    picking = nil
                    let ext = url.pathExtension.lowercased()
                    switch kind {
                    case .p12:
                        if ["p12", "pfx"].contains(ext) { p12 = url; error = nil }
                        else { error = "Choose a .p12 file (got .\(ext))" }
                    case .prov:
                        if ext == "mobileprovision" { prov = url; error = nil }
                        else { error = "Choose a .mobileprovision file (got .\(ext))" }
                    }
                }, onCancel: { picking = nil })
            }
        }
    }

    private func pickRow(_ title: String, _ url: URL?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(.primary); Spacer()
                Text(url?.lastPathComponent ?? "Choose…").foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}
