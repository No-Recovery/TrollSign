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
            ZStack {
                LiquidBackground()

                ScrollView {
                    LazyVStack(spacing: 12) {
                        if filtered.isEmpty {
                            emptyState
                        } else {
                            ForEach(filtered) { app in
                                Button { selected = app } label: {
                                    AppCell(app: app)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button { details = app } label: {
                                        Label("Show Details", systemImage: "info.circle")
                                    }
                                    Button { Task { await store.installEntry(app) } } label: {
                                        Label("Reinstall", systemImage: "arrow.clockwise")
                                    }
                                    Button(role: .destructive) { toDelete = app } label: {
                                        Label("Uninstall App", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 26)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Apps")
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showPicker = true } label: {
                            Label("Install IPA File", systemImage: "doc.badge.plus")
                        }
                        Button { showURLAlert = true } label: {
                            Label("Install from URL", systemImage: "link.badge.plus")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if store.busy {
                    HStack(spacing: 10) {
                        ProgressView().tint(.white)
                        Text(store.statusText)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(.black.opacity(0.55), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.85), value: store.busy)
        }
        .sheet(isPresented: $showPicker) {
            DocumentPicker(onPick: { url in
                showPicker = false
                store.request(.local(url))
            }, onCancel: { showPicker = false })
        }
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

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(LiquidTheme.accent)
                .frame(width: 76, height: 76)
                .background(LiquidTheme.accent.opacity(0.12), in: Circle())

            Text("No apps yet")
                .font(.headline)

            Text("Tap + to pick an IPA. TrollSign signs it with your certificate and installs it through the selected hosting provider.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .glassPanel(corner: 28)
    }
}

struct AppCell: View {
    @EnvironmentObject var store: AppStore
    let app: IPAEntry

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let u = store.iconURL(app), let img = UIImage(contentsOfFile: u.path) {
                    Image(uiImage: img).resizable().scaledToFit()
                } else {
                    Image(systemName: "app.fill")
                        .resizable()
                        .scaledToFit()
                        .padding(10)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(.white.opacity(0.16), lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(app.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("\(app.version) · \(app.bundleID)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if app.signedFileName != nil {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title3)
                    .foregroundStyle(LiquidTheme.aqua)
            }
        }
        .padding(14)
        .glassPanel(corner: 22)
        .contentShape(Rectangle())
    }
}

struct AppDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    let app: IPAEntry

    var body: some View {
        NavigationStack {
            ZStack {
                LiquidBackground()

                ScrollView {
                    VStack(spacing: 18) {
                        AppCell(app: app)

                        GlassSection("Information") {
                            detailRow("Version", app.version, icon: "number")
                            GlassDivider()
                            detailRow("Bundle identifier", app.bundleID, icon: "shippingbox.fill")
                            GlassDivider()
                            detailRow("Size", ByteCountFormatter.string(fromByteCount: app.size, countStyle: .file), icon: "internaldrive.fill")
                            GlassDivider()
                            detailRow("Signed", app.signedFileName == nil ? "Not yet" : "Yes", icon: "checkmark.seal.fill")
                        }

                        Button {
                            dismiss()
                            Task { await store.installEntry(app) }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.clockwise")
                                Text("Reinstall")
                            }
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(LinearGradient(colors: [LiquidTheme.accent, LiquidTheme.violet],
                                                       startPoint: .leading, endPoint: .trailing),
                                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle(app.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func detailRow(_ title: String, _ value: String, icon: String) -> some View {
        GlassRow(title, icon: icon, subtitle: value, tint: LiquidTheme.accent)
    }
}
