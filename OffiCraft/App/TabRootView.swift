import SwiftUI

/// iPhone shell: the five sections in a system tab bar.
///
/// The tab bar is the system one on purpose — the doc asks for "iOS 原生語彙",
/// and that buys correct safe-area handling, keyboard avoidance and the scroll
/// edge effect for free. Only the glyphs are ours, rasterised from the same
/// SVG set the rest of the app draws.
struct TabRootView: View {
    @Binding var section: AppSection
    @Environment(StudioStore.self) private var store

    var body: some View {
        TabView(selection: $section) {
            NavigationStack { AsksView() }
                .tabItem { tabLabel(.asks) }
                .badge(store.waitingCardCount)
                .tag(AppSection.asks)

            NavigationStack { TasksView() }
                .tabItem { tabLabel(.tasks) }
                .badge(store.tasksWaitingOnOwner.count)
                .tag(AppSection.tasks)

            NavigationStack { OfficeView() }
                .tabItem { tabLabel(.office) }
                .badge(store.unreadTotal)
                .tag(AppSection.office)

            NavigationStack { MonitorView() }
                .tabItem { tabLabel(.monitor) }
                .tag(AppSection.monitor)

            NavigationStack { MoreView() }
                .tabItem { tabLabel(.more) }
                .tag(AppSection.more)
        }
        .tint(OC.accent)
    }

    private func tabLabel(_ section: AppSection) -> some View {
        Label {
            Text(section.title)
        } icon: {
            if let image = TabIconCache.image(for: section.icon) {
                Image(uiImage: image)
            } else {
                Image(systemName: "circle")
            }
        }
    }
}

/// `tabItem` only accepts `Image`, not an arbitrary view, so the SVG glyphs are
/// rasterised once and cached as template images.
@MainActor
enum TabIconCache {
    private static var cache: [OCIcon: UIImage] = [:]

    static func image(for icon: OCIcon) -> UIImage? {
        if let cached = cache[icon] { return cached }
        let renderer = ImageRenderer(
            content: Icon(icon, size: 25).foregroundStyle(Color.black)
        )
        renderer.scale = UIScreen.main.scale
        guard let rendered = renderer.uiImage?.withRenderingMode(.alwaysTemplate) else {
            return nil
        }
        cache[icon] = rendered
        return rendered
    }
}
