import SwiftUI
import UndertoneCore

struct MainView: View {
    @Environment(PlayerEngine.self) private var engine
    @Environment(YTDLPService.self) private var service
    @Environment(PanelState.self) private var state

    var body: some View {
        VStack(spacing: 12) {
            header
            if !service.status.isUsable || isOutdated {
                ToolStatusBanner()
            }
            URLBar()
            if engine.track != nil || engine.isResolving {
                NowPlayingCard()
                Scrubber()
                TransportBar()
                SecondaryControls()
            } else if engine.errorMessage == nil {
                // The error's own suggestion replaces the hint, so the two don't both say "paste a link".
                EmptyHint()
            }
            if let notice = engine.notice {
                MessageRow(icon: "info.circle", tone: .secondary, message: notice, detail: nil) { engine.clearNotice() }
            }
            if let error = engine.errorMessage {
                MessageRow(icon: "exclamationmark.triangle.fill", tone: .yellow, message: error, detail: engine.errorSuggestion) { engine.clearError() }
            }
        }
        .padding(16)
    }

    private var isOutdated: Bool {
        if case .outdated = service.status { return true }
        return false
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Undertone")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            IconButton(symbol: "gearshape", help: "Settings") {
                state.showSettings(true)
            }
            IconButton(symbol: "power", help: "Quit Undertone") {
                NSApp.terminate(nil)
            }
        }
    }
}

/// Small borderless symbol button. Its sizes are shared by every icon-only control in the panel (the link-bar menus,
/// the star, the chapter menu) so they all line up.
struct IconButton: View {
    static let side: CGFloat = 24
    static let symbolSize: CGFloat = 13

    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: Self.symbolSize, weight: .medium))
                .frame(width: Self.side, height: Self.side)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(help)
        // .help is only a tooltip and hint; without a label VoiceOver reads the SF Symbol name.
        .accessibilityLabel(help)
    }
}

struct EmptyHint: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "music.note.list")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Paste a YouTube link to listen in the background.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Videos, playlists, and most sites yt-dlp knows.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
    }
}

struct MessageRow: View {
    enum Tone { case secondary, yellow }
    let icon: String
    let tone: Tone
    let message: String
    let detail: String?
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(tone == .yellow ? AnyShapeStyle(.yellow) : AnyShapeStyle(.secondary))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(message)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            IconButton(symbol: "xmark", help: "Dismiss", action: dismiss)
                .controlSize(.small)
        }
        .padding(10)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }
}
