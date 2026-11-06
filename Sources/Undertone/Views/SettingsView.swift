import AppKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI
import UndertoneCore

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(PlayerEngine.self) private var engine
    @Environment(YTDLPService.self) private var service
    @Environment(PanelState.self) private var state
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var loginRequiresApproval = LaunchAtLogin.status == .requiresApproval
    @State private var loginError: String?

    var body: some View {
        @Bindable var settings = settings
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                IconButton(symbol: "chevron.left", help: "Back") { state.showSettings(false) }
                Text("Settings")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                IconButton(symbol: "power", help: "Quit Undertone") { NSApp.terminate(nil) }
            }

            section("Shortcuts") {
                shortcutRow("Play / Pause", .togglePlayPause)
                shortcutRow("Cycle speed", .cycleSpeed)
                shortcutRow("Open panel", .togglePanel)
                shortcutRow("Next track", .nextTrack)
                shortcutRow("Previous track", .previousTrack)
                Text("Media keys and the Now Playing widget work without any setup.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }

            section("General") {
                Toggle("Show track title in the menu bar", isOn: $settings.showTitleInMenuBar)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(!LaunchAtLogin.isAvailable)
                    .onChange(of: launchAtLogin) { _, enabled in
                        guard enabled != LaunchAtLogin.isEnabled else { return }
                        do {
                            try LaunchAtLogin.set(enabled)
                            loginError = nil
                            loginRequiresApproval = LaunchAtLogin.status == .requiresApproval
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                    }
                if !LaunchAtLogin.isAvailable {
                    Text("Run the built app (mise run install) to enable this.").font(.caption2).foregroundStyle(.tertiary)
                } else if !LaunchAtLogin.isInApplications {
                    Text("Tip: install to /Applications first so the login item survives rebuilds.").font(.caption2).foregroundStyle(.tertiary)
                }
                if loginRequiresApproval {
                    Button("Approve in System Settings…") { LaunchAtLogin.openSystemSettings() }.controlSize(.mini)
                }
                if let loginError {
                    Text(loginError).font(.caption2).foregroundStyle(.red)
                }
            }

            section("Audio cache") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(audioCacheLabel)
                            .font(.caption)
                        Text("Tracks you play are kept so replays need no download.")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Button("Clear") { engine.clearAudioCache() }
                        .controlSize(.mini)
                        .disabled(engine.audioCacheBytes == 0)
                }
            }

            section("yt-dlp") {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: toolSymbol).foregroundStyle(toolColor).padding(.top, 1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(toolTitle).font(.caption).fixedSize(horizontal: false, vertical: true)
                        if let path = service.executable?.path {
                            Text(path).font(.caption2.monospaced()).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                        }
                        Text(service.jsRuntime.map { "deno: \($0.path)" } ?? "deno not found (YouTube needs it: brew install deno)")
                            .font(.caption2.monospaced()).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                }
                HStack {
                    Button("Recheck") { service.recheck() }
                    Button("Choose…") { choosePath() }
                    if settings.ytdlpPathOverride != nil {
                        Button("Use default") { service.setOverride(nil) }
                    }
                    Spacer()
                    Text(service.installCommand).font(.caption2.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                }
                .controlSize(.mini)
            }

            HStack {
                Text(versionLabel)
                    .font(.caption2).foregroundStyle(.tertiary)
                    .textSelection(.enabled)
                Spacer()
                Button(role: .destructive) { NSApp.terminate(nil) } label: {
                    Label("Quit Undertone", systemImage: "power")
                }
                .controlSize(.small)
            }
        }
        .padding(16)
        .onAppear { engine.refreshAudioCacheSize() }
        .onChange(of: state.showCount) { _, _ in
            engine.refreshAudioCacheSize()
            launchAtLogin = LaunchAtLogin.isEnabled
            loginRequiresApproval = LaunchAtLogin.status == .requiresApproval
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .kerning(0.5)
            content()
        }
    }

    private func shortcutRow(_ label: String, _ name: KeyboardShortcuts.Name) -> some View {
        HStack {
            Text(label).font(.caption)
            Spacer()
            KeyboardShortcuts.Recorder(for: name)
                .controlSize(.small)
        }
    }

    private func choosePath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.message = "Choose the yt-dlp executable"
        panel.directoryURL = URL(fileURLWithPath: "/usr/local/bin")
        NSApp.activate()
        state.hide()
        panel.begin { response in
            if response == .OK, let url = panel.url {
                service.setOverride(url.path)
            }
        }
    }

    /// "Undertone 0.4.0 (183)": the build number (the commit count, from bundle.sh) tells two builds of one version apart.
    private var versionLabel: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "dev"
        guard let build = info?["CFBundleVersion"] as? String, !build.isEmpty else { return "Undertone \(version)" }
        return "Undertone \(version) (\(build))"
    }

    /// "Empty (up to 2 GB)" or "340 MB of 2 GB used". ByteCountFormatter alone says "Zero KB".
    private var audioCacheLabel: String {
        let cap = ByteCountFormatter.string(fromByteCount: engine.audioCache.capacity, countStyle: .file)
        guard engine.audioCacheBytes > 0 else { return "Empty (up to \(cap))" }
        return "\(ByteCountFormatter.string(fromByteCount: engine.audioCacheBytes, countStyle: .file)) of \(cap) used"
    }

    private var toolSymbol: String {
        switch service.status {
        case .ready: return "checkmark.circle.fill"
        case .checking: return "hourglass"
        case .outdated: return "arrow.up.circle.fill"
        case .missing, .broken: return "exclamationmark.triangle.fill"
        }
    }

    private var toolColor: Color {
        switch service.status {
        case .ready: return .green
        case .checking: return .secondary
        case .outdated: return .yellow
        case .missing, .broken: return .orange
        }
    }

    private var toolTitle: String {
        switch service.status {
        case .checking: return "Checking…"
        case .ready(let v): return "yt-dlp \(v)"
        case .outdated(let v): return "yt-dlp \(v) — update recommended (≥ \(YTDLPVersion.minimumRecommended))"
        case .missing: return "Not found. Install with Homebrew."
        case .broken(let m): return "Not working: \(m)"
        }
    }
}
