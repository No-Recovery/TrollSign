import SwiftUI
import UIKit

struct AppsView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var certs: CertStore

    @State private var search = ""
    @State private var showPicker = false
    @State private var showURLAlert = false
    @State private var urlText = ""
    @State private var selected: IPAEntry?
    @State private var details: IPAEntry?
    @State private var toDelete: IPAEntry?

    private var filtered: [IPAEntry] {
        let s = search.trimmingCharacters(in: .whitespaces).lowercased()
        return s.isEmpty ? store.apps
            : store.apps.filter { $0.name.lowercased().contains(s) || $0.bundleID.lowercased().contains(s) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { app in
                    Button { selected = app } label: { AppCell(app: app) }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button("Uninstall", role: .destructive) { toDelete = app }
                        }
                }
            }
            .listStyle(.plain)
            .overlay { if store.apps.isEmpty {
                Text("No apps installed").foregroundStyle(.secondary) } }
            .navigationTitle("Apps")
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showPicker = true } label: {
                            Label("Install IPA File", systemImage: "doc.badge.plus") }
                        Button { showURLAlert = true } label: {
                            Label("Install from URL", systemImage: "link.badge.plus") }
                    } label: { Image(systemName: "plus") }
                }
            }
            .overlay(alignment: .bottom) {
                if store.busy {
                    HStack(spacing: 10) { ProgressView(); Text(store.statusText) }
                        .padding(.horizontal, 18).padding(.vertical, 12)
                        .background(.regularMaterial, in: Capsule()).padding(.bottom, 12)
                }
            }
        }
        // Выбор IPA
        .sheet(isPresented: $showPicker) {
            DocumentPicker(onPick: { url in
                showPicker = false
                store.request(.local(url))
            }, onCancel: { showPicker = false })
        }
        // Меню приложения (как в TrollStore)
        .confirmationDialog(selected?.name ?? "", isPresented: Binding(
            get: { selected != nil }, set: { if !$0 { selected = nil } }), titleVisibility: .visible) {
            if let a = selected {
                Button("Show Details") { details = a }
                Button("Reinstall") { Task { await store.installEntry(a) } }
                Button("Uninstall App", role: .destructive) { toDelete = a }
                Button("Cancel", role: .cancel) {}
            }
        }
        .sheet(item: $details) { a in AppDetailView(app: a) }
        .alert("Install from URL", isPresented: $showURLAlert) {
            TextField("URL", text: $urlText).textInputAutocapitalization(.never).keyboardType(.URL)
            Button("Install") {
                if let u = URL(string: urlText.trimmingCharacters(in: .whitespaces)) { store.request(.remote(u)) }
                urlText = ""
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Confirm Installation", isPresented: Binding(
            get: { store.pending != nil }, set: { if !$0 { store.pending = nil } })) {
            Button("Install") { if let p = store.pending { store.run(p) } }
            Button("Cancel", role: .cancel) { store.pending = nil }
        } message: {
            switch store.pending {
            case .local(let u): Text("Install '\(u.lastPathComponent)'?")
            case .remote(let u): Text("Install the app from \(u.absoluteString)?")
            case .none: Text("")
            }
        }
        .alert("Confirm Uninstallation", isPresented: Binding(
            get: { toDelete != nil }, set: { if !$0 { toDelete = nil } })) {
            Button("Uninstall", role: .destructive) { if let a = toDelete { store.delete(a) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removing '\(toDelete?.name ?? "")' deletes its IPA files from this app. The installed app stays on the home screen; delete it there.")
        }
        .alert("Error", isPresented: Binding(
            get: { store.errorText != nil }, set: { if !$0 { store.errorText = nil } })) {
            Button("Close", role: .cancel) {}
        } message: { Text(store.errorText ?? "") }
    }
}

struct AppCell: View {
    @EnvironmentObject var store: AppStore
    let app: IPAEntry

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let u = store.iconURL(app), let img = UIImage(contentsOfFile: u.path) {
                    Image(uiImage: img).resizable()
                } else {
                    Image(systemName: "app.fill").resizable().scaledToFit().padding(8).foregroundStyle(.gray)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(.body).foregroundStyle(.primary)
                Text("\(app.version) • \(app.bundleID)").font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if app.signedFileName != nil {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
            }
        }
        .contentShape(Rectangle())
    }
}

struct AppDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let app: IPAEntry

    var body: some View {
        NavigationStack {
            List {
                Text("Version: \(app.version)")
                Text("Bundle Identifier: \(app.bundleID)")
                Text("Size: \(ByteCountFormatter.string(fromByteCount: app.size, countStyle: .file))")
            }
            .listStyle(.insetGrouped)
            .navigationTitle(app.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } } }
        }
    }
}
