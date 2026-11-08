import SwiftUI
import UIKit

struct HostingView: View {
    @AppStorage("hostingProvider") private var providerRaw = HostingProvider.ready.rawValue
    @AppStorage("ghOwner") private var owner = GitHubHostingConfig.defaultOwner
    @AppStorage("ghRepo") private var repo = GitHubHostingConfig.defaultRepo
    @AppStorage("ghBranch") private var branch = "main"
    @AppStorage("ghPagesBase") private var pagesBase = ""

    @State private var token = ""
    @State private var hasToken = false
    @State private var status: String?
    @State private var busy = false
    @State private var editingToken = false

    private var provider: HostingProvider {
        HostingProvider(rawValue: providerRaw) ?? .ready
    }

    var body: some View {
        ZStack {
            LiquidBackground()

            ScrollView {
                VStack(spacing: 18) {
                    header

                    GlassSection("Provider",
                                 footer: "Ready hosting needs no account. GitHub hosting publishes to your own repository and requires a personal access token.") {
                        ForEach(Array(HostingProvider.allCases.enumerated()), id: \.element.id) { index, item in
                            providerRow(item)
                            if index < HostingProvider.allCases.count - 1 {
                                GlassDivider()
                            }
                        }
                    }

                    if provider == .ready {
                        readySection
                    } else {
                        githubSection
                    }

                    if let status {
                        Text(status)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 18)
                    }

                    if let page = HostingConfig.installPage {
                        Link(destination: page) {
                            GlassRow("Open install page",
                                     icon: "safari.fill",
                                     subtitle: page.absoluteString,
                                     tint: LiquidTheme.aqua) {
                                GlassChevron()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Hosting")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            hasToken = !GitHubHostingConfig.token.isEmpty
            token = ""
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [LiquidTheme.aqua, LiquidTheme.accent],
                                         startPoint: .topLeading,
                                         endPoint: .bottomTrailing))
                    .frame(width: 56, height: 56)
                    .shadow(color: LiquidTheme.aqua.opacity(0.4), radius: 14, x: 0, y: 6)

                Image(systemName: provider == .ready ? "bolt.horizontal.circle.fill" : "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(provider == .ready ? "Ready hosting" : "GitHub hosting")
                    .font(.headline)
                Text(provider == .ready
                     ? "No setup · uploads automatically"
                     : (hasToken ? "Token saved in Keychain" : "Access token required"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: isReady ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.title2)
                .foregroundStyle(isReady ? .green : .orange)
        }
        .padding(16)
        .glassPanel(corner: 26)
    }

    private var isReady: Bool {
        provider == .ready || GitHubHostingConfig.isConfigured
    }

    private func providerRow(_ item: HostingProvider) -> some View {
        Button {
            providerRaw = item.rawValue
            status = nil
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: provider == item ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(provider == item ? LiquidTheme.accent : Color.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(item.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Ready

    private var readySection: some View {
        VStack(spacing: 18) {
            GlassSection("How it works",
                         footer: "The signed IPA is uploaded over HTTPS and installed through itms-services. Links are public but unlisted; keep them private if the app is private.") {
                bullet("checkmark.shield.fill", "Signed locally with your certificate")
                GlassDivider()
                bullet("icloud.and.arrow.up.fill", "IPA and manifest uploaded to a public HTTPS host")
                GlassDivider()
                bullet("bolt.fill", "No token, no localhost server, no setup")
            }

            Button {
                busy = true
                status = "Checking…"
                Task {
                    status = await ReadyHosting.test()
                    busy = false
                }
            } label: {
                HStack(spacing: 8) {
                    if busy { ProgressView().tint(.white) }
                    else { Image(systemName: "antenna.radiowaves.left.and.right") }
                    Text(busy ? "Checking…" : "Test ready hosting")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(LinearGradient(colors: [LiquidTheme.aqua, LiquidTheme.accent],
                                           startPoint: .leading, endPoint: .trailing),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(busy)
        }
    }

    // MARK: GitHub

    private var githubSection: some View {
        VStack(spacing: 18) {
            GlassSection("Repository",
                         footer: "Default Pages URL: https://\(owner.lowercased()).github.io/\(repo)/. The repository is used as-is; enable Pages with the /docs folder.") {
                field("Owner", icon: "person.fill", text: $owner)
                GlassDivider()
                field("Repository", icon: "folder.fill", text: $repo)
                GlassDivider()
                field("Branch", icon: "arrow.triangle.branch", text: $branch)
                GlassDivider()
                field("Pages URL", icon: "globe", text: $pagesBase, keyboard: .URL)
            }

            GlassSection("Access token",
                         footer: "Classic scope: repo. Fine-grained: Contents, Releases and Pages read/write, plus Administration if TrollSign should create the repository. Stored only in the iOS Keychain.") {
                GlassRow("Token",
                         icon: "key.fill",
                         subtitle: hasToken ? "Saved in the iOS Keychain" : "Not configured") {
                    Button(hasToken ? "Replace" : "Add") {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            editingToken.toggle()
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                }

                if editingToken {
                    GlassDivider()

                    VStack(alignment: .leading, spacing: 10) {
                        SecureField("ghp_… or github_pat_…", text: $token)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(12)
                            .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                        HStack(spacing: 10) {
                            Button("Save token") {
                                let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !value.isEmpty else { return }
                                Keychain.set(value, for: "github.token")
                                token = ""
                                hasToken = true
                                editingToken = false
                                status = "Token saved to the Keychain."
                            }
                            .font(.subheadline.weight(.semibold))
                            .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            if hasToken {
                                Button("Remove", role: .destructive) {
                                    Keychain.delete("github.token")
                                    hasToken = false
                                    status = "Token removed."
                                }
                                .font(.subheadline)
                            }

                            Spacer()
                        }
                    }
                    .padding(14)
                }
            }

            Button {
                busy = true
                status = "Checking…"
                Task {
                    status = await GitHubHosting.test()
                    busy = false
                }
            } label: {
                HStack(spacing: 8) {
                    if busy { ProgressView().tint(.white) }
                    else { Image(systemName: "network") }
                    Text(busy ? "Checking…" : "Test GitHub connection")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(LinearGradient(colors: [LiquidTheme.violet, LiquidTheme.accent],
                                           startPoint: .leading, endPoint: .trailing),
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(busy)
        }
    }

    private func bullet(_ icon: String, _ text: String) -> some View {
        GlassRow(text, icon: icon, tint: LiquidTheme.aqua)
    }

    private func field(_ title: String, icon: String, text: Binding<String>,
                       keyboard: UIKeyboardType = .default) -> some View {
        GlassRow(title, icon: icon) {
            TextField("", text: text)
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(keyboard)
                .font(.subheadline)
                .frame(maxWidth: 190)
        }
    }
}
