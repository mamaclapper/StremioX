import SwiftUI
import UIKit

/// A request to play something full-screen.
struct PlaybackRequest: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
    var meta: PlaybackMeta? = nil
    var episodes: [CoreVideo] = []
}

/// Holds the active playback request. Set it to present the player; clear it to dismiss.
final class PlayerPresenter: ObservableObject {
    @Published var request: PlaybackRequest?
}

/// App root, two focus rules learned the hard way:
///  - The profile picker is ROOT REPLACEMENT: while it's up, the shell does not exist. On a real
///    Siri remote the focus engine would not move into an overlay above the (even disabled) UIKit
///    tab bar, leaving the picker unselectable; as the only root content it always gets focus.
///    Nothing is lost: the picker only shows at cold start or on an explicit profile switch.
///  - The player presents OVER the live but hidden + disabled shell, so closing it returns to the
///    exact page playback started from; the player's catcher window owns the remote (TVPlayerView).
struct RootView: View {
    @EnvironmentObject private var presenter: PlayerPresenter
    @EnvironmentObject private var profiles: ProfileStore

    var body: some View {
        Group {
            if profiles.needsPicker && presenter.request == nil {
                ProfilePickerView()
            } else {
                ZStack {
                    RootTabView()
                        .opacity(presenter.request == nil ? 1 : 0)
                        .disabled(presenter.request != nil)
                    if let req = presenter.request {
                        TVPlayerView(url: req.url, title: req.title, meta: req.meta, episodes: req.episodes,
                                     onClose: { presenter.request = nil })
                            .id(req.id)   // clean player teardown per request
                    }
                }
            }
        }
    }
}

/// The app shell: Home · Discover · Library · Add-ons · Search · Settings.
///
/// Uses the native tvOS `TabView` so the top tab bar gets correct focus behaviour for free: tabs switch
/// as focus crosses them, and focus moves cleanly between the tab bar and the page content (up/down). The
/// player no longer depends on the shell being a custom bar, it locks focus on its own catcher while up,
/// so the native tab bar can't steal the remote.
struct RootTabView: View {
    @EnvironmentObject private var account: StremioAccount
    @EnvironmentObject private var theme: ThemeManager

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
            DiscoverView()
                .tabItem { Label("Discover", systemImage: "safari.fill") }
            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical.fill") }
            AddonsView()
                .tabItem { Label("Add-ons", systemImage: "puzzlepiece.extension.fill") }
            NavigationStack { SearchView() }
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
        .tint(theme.accent)
        .onAppear { applyTabBarAccent() }
        // The active profile owns the theme: mirror Settings changes into it so they survive a switch.
        .onChange(of: theme.accentID) { applyTabBarAccent(); ProfileStore.shared.captureTheme() }
        .onChange(of: theme.oled) { applyTabBarAccent(); ProfileStore.shared.captureTheme() }
    }

    /// The focused tab's pill is system white by default; recolor it to the active accent (with the
    /// dark on-accent ink for the focused label) via UITabBarAppearance, and push the appearance onto
    /// any live tab bars so an accent change repaints without a relaunch.
    private func applyTabBarAccent() {
        let item = UITabBarItemAppearance()
        item.focused.titleTextAttributes = [.foregroundColor: UIColor(Theme.Palette.onAccent)]
        item.focused.iconColor = UIColor(Theme.Palette.onAccent)
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.selectionIndicatorTintColor = UIColor(Theme.Palette.accent)
        appearance.inlineLayoutAppearance = item
        appearance.stackedLayoutAppearance = item
        appearance.compactInlineLayoutAppearance = item
        UITabBar.appearance().standardAppearance = appearance
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows { retintTabBars(under: window.rootViewController, with: appearance) }
        }
    }

    private func retintTabBars(under controller: UIViewController?, with appearance: UITabBarAppearance) {
        guard let controller else { return }
        if let tabs = controller as? UITabBarController {
            tabs.tabBar.standardAppearance = appearance
            tabs.tabBar.setNeedsLayout()
        }
        controller.children.forEach { retintTabBars(under: $0, with: appearance) }
        retintTabBars(under: controller.presentedViewController, with: appearance)
    }
}

/// An invisible focus landing strip pinned to the very top of each tab page.
///
/// The tvOS tab bar auto-hides when focus dives into content, and UIKit only summons it back when
/// focus reaches the TOP EDGE of the screen (or on Menu). Our browse layouts keep every focusable
/// element in a bottom strip, so after popping back from a detail page there was nothing up top to
/// trigger the summon: Up from the rails did nothing and the bar looked gone until a Menu press.
/// Landing focus here satisfies the top-edge rule natively, and the explicit focus request hands
/// the remote straight to the bar so it never feels like focus vanished.
struct TabBarSummoner: View {
    var body: some View {
        Button(action: Self.focusTabBar) {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 8)
                .background { FocusReporter(onFocus: Self.focusTabBar) }
        }
        .buttonStyle(SummonerStyle())
    }

    /// Chrome-free: the strip is a pure focus target, never a visible control.
    private struct SummonerStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View { configuration.label }
    }

    static func focusTabBar() {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                guard let bar = firstTabBar(under: window.rootViewController) else { continue }
                bar.setNeedsLayout()
                UIFocusSystem.focusSystem(for: window)?.requestFocusUpdate(to: bar)
                return
            }
        }
    }

    private static func firstTabBar(under controller: UIViewController?) -> UITabBar? {
        guard let controller else { return nil }
        if let tabs = controller as? UITabBarController { return tabs.tabBar }
        for child in controller.children {
            if let bar = firstTabBar(under: child) { return bar }
        }
        return firstTabBar(under: controller.presentedViewController)
    }
}
