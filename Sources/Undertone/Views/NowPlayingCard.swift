import AppKit
import SwiftUI
import UndertoneCore

struct NowPlayingCard: View {
    @Environment(PlayerEngine.self) private var engine

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(url: engine.track?.artworkURL, isResolving: engine.isResolving)
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                if engine.isResolving {
                    Text(engine.resolvingTitle ?? "Resolving…")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("Fetching audio…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Cancel") { engine.cancelResolving() }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundStyle(.tint)
                    }
                } else if let track = engine.track {
                    Text(track.title)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                    if let chapter = engine.chapter {
                        Text(chapter.title)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .help(chapter.title)
                    }
                    if let channel = track.channel {
                        Text(channel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                if let queue = engine.queue {
                    Text("\(queue.position) / \(queue.count)\(queue.title.map { " · \($0)" } ?? "")")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if engine.track != nil, !engine.isResolving {
                if engine.track?.chapters.isEmpty == false {
                    ChapterMenu()
                }
                Button { engine.toggleSavedTrack() } label: {
                    Image(systemName: engine.isTrackSaved ? "star.fill" : "star")
                        .font(.system(size: 14))
                        .foregroundStyle(engine.isTrackSaved ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(engine.isTrackSaved ? "Remove this track from saved links" : "Save this track")
            }
        }
    }
}

/// Every chapter of the playing video with its start time; pick one to jump there. The current one is checked.
struct ChapterMenu: View {
    @Environment(PlayerEngine.self) private var engine

    var body: some View {
        Menu {
            ForEach(Array((engine.track?.chapters ?? []).enumerated()), id: \.offset) { _, chapter in
                Toggle(isOn: Binding(get: { chapter == engine.chapter }, set: { _ in engine.seek(to: chapter.start) })) {
                    Text(chapter.title)
                    Text(TimeFormat.clock(chapter.start))
                }
            }
        } label: {
            Image(systemName: "list.bullet")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Chapters")
    }
}

/// Loads artwork through the shared cache; shows a placeholder while resolving.
struct ArtworkView: View {
    let url: URL?
    let isResolving: Bool
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.08))
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: isResolving ? "waveform.badge.magnifyingglass" : "music.note")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: url) {
            image = url.flatMap { ArtworkLoader.shared.cached($0) }
            guard let url else { return }
            let loaded = await ArtworkLoader.shared.image(for: url)
            if !Task.isCancelled { image = loaded }
        }
    }
}
