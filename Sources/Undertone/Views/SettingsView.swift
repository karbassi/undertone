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
                    .font(.headline)
                Spacer()
            }

            section("Shortcuts") {
                shortcutRow("Play / Pause", .togglePlayPause)
                shortcutRow("Cycle speed", .cycleSpeed)
                shortcutRow("Open panel", .togglePanel)
                shortcutRow("Next track", .nextTrack)
                shortcutRow("Previous track", .previousTrack)
                Text("Media keys and the Now Playing widget work without any setup.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            section("General") {
                toggleRow("Show track title in the menu bar", isOn: $settings.showTitleInMenuBar)
                toggleRow("Launch at login", isOn: $launchAtLogin)
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
                    Text("Run the built app (mise run install) to enable this.").font(.caption2).foregroundStyle(.secondary)
                } else if !LaunchAtLogin.isInApplications {
                    Text("Tip: install to /Applications first so the login item survives rebuilds.").font(.caption2).foregroundStyle(.secondary)
                }
                if loginRequiresApproval {
                    Button("Approve in System Settings…") { LaunchAtLogin.openSystemSettings() }.controlSize(.small)
                }
                if let loginError {
                    Text(loginError).font(.caption2).foregroundStyle(.red)
                }
            }

            section("Audio cache") {
                HStack {
                    Text(audioCacheLabel)
                    Spacer()
                    Button("Clear") { engine.clearAudioCache() }
                        .controlSize(.small)
                        .disabled(engine.audioCacheBytes == 0)
                }
                Text("Tracks you play are kept so replays need no download.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            section("yt-dlp") {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: toolSymbol).foregroundStyle(toolColor).padding(.top, 1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(toolTitle).font(.caption).fixedSize(horizontal: false, vertical: true)
                        if let path = service.executable?.path {
                            Text(path).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Text(service.jsRuntime.map { "deno: \($0.path)" } ?? "deno not found (YouTube needs it: brew install deno)")
                            .font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 0)
                }
                HStack {
                    Button("Recheck") { service.recheck() }
                    Button("Choose…") { choosePath() }
                    if settings.ytdlpPathOverride != nil {
                        Button("Use Default") { service.setOverride(nil) }
                    }
                    Spacer()
                    if needsInstallCommand {
                        Text(service.installCommand).font(.caption2.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                .controlSize(.small)
            }

            HStack {
                Text(versionLabel)
                    .font(.caption2).foregroundStyle(.secondary)
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

    /// Sentence-case semibold headers, as System Settings uses (not the older uppercase grouped-list style).
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    /// Label left in the row font, switch right-aligned: the System Settings layout, lined up with the shortcut rows.
    private func toggleRow(_ label: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(label)
            Spacer()
            Toggle(label, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
    }

    private func shortcutRow(_ label: String, _ name: KeyboardShortcuts.Name) -> some View {
        HStack {
            Text(label)
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

    /// The brew command is the fix, so it shows only when there is something to fix.
    private var needsInstallCommand: Bool {
        switch service.status {
        case .missing, .outdated, .broken: return true
        case .ready, .checking: return false
        }
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
        case .outdated: return .orange   // yellow is unreadable on light glass
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
