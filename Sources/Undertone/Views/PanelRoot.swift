import SwiftUI
import UndertoneCore

/// The SwiftUI content of the panel. Transparent: the AppKit glass view behind it provides the surface.
struct PanelRoot: View {
    let engine: PlayerEngine
    let settings: AppSettings
    let service: YTDLPService
    let state: PanelState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .top) {
            if state.showingSettings {
                page { SettingsView() }
                    .transition(pageTransition(from: .trailing))
            } else {
                page { MainView() }
                    .transition(pageTransition(from: .leading))
            }
        }
        // The window is sized to the page; pinning it to the top keeps any transient mismatch at the bottom.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipShape(.rect(cornerRadius: PanelController.cornerRadius))
        .environment(engine)
        .environment(settings)
        .environment(service)
        .environment(state)
    }

    /// Pages slide in from the side; with Reduce Motion they only cross-fade.
    private func pageTransition(from edge: Edge) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: edge).combined(with: .opacity)
    }

    /// A page takes its natural height up to what fits on the screen, scrolls beyond that, and reports its size.
    private func page<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(.vertical) {
            content().frame(width: PanelController.width)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: PanelController.width)
        .frame(maxHeight: state.maxContentHeight)
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            state.controller?.contentSizeChanged(size)
        }
    }
}
