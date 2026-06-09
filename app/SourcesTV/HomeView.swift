import SwiftUI

/// Native tvOS Home, driven by the **stremio-core** engine (via `CoreBridge`): a "Continue Watching"
/// rail plus every catalog of every installed addon, on the StremioX design system (Theme.swift).
struct HomeView: View {
    @EnvironmentObject private var core: CoreBridge
    @EnvironmentObject private var theme: ThemeManager
    @EnvironmentObject private var account: StremioAccount
    @StateObject private var focusModel = FocusedItemModel()

    var body: some View {
        NavigationStack {
            ZStack {
                // The living backdrop: whichever poster is focused fills the screen with its
                // artwork and details. Rows scrolling up fade out UNDER the hero band (the mask)
                // instead of driving over its text.
                BrowseHeroBackdrop(model: focusModel)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.Space.xl) {
                        if !core.continueWatching.isEmpty {
                            CoreContinueWatchingRow(items: core.continueWatching, focusModel: focusModel,
                                                    isTopRow: true)
                        }
                        ForEach(core.boardRows) { row in
                            CoreCatalogRowView(row: row, focusModel: focusModel,
                                               isTopRow: core.continueWatching.isEmpty
                                                         && row.id == core.boardRows.first?.id)
                        }
                        if core.continueWatching.isEmpty && core.boardRows.isEmpty {
                            if account.isSignedIn { LoadingRail() } else { CoreEmptyState.signedOut }
                        }
                    }
                    .padding(.bottom, Theme.Space.xl)
                }
                // A margin, not content: the hero band shows through here, and scrolled-to-top
                // detection still sees the resting position as "top" (so the tab bar can return).
                .contentMargins(.top, 480, for: .scrollContent)
                .mask(scrollMask)
            }
            .overlay(alignment: .topLeading) {
                header
                    .padding(.top, 44)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .ignoresSafeArea()   // absolute top-left, clear of the hero title below
            }
            .background(Theme.Palette.canvas.ignoresSafeArea())
        }
        .onAppear { seed() }
        .onChange(of: core.boardRows.first?.id) { seed() }
        .onChange(of: core.continueWatching.first?.id) { seed() }
    }

    /// Clear over the hero band, a short fade, then fully visible: rows slide under the hero.
    private var scrollMask: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                .frame(height: 110)
                .padding(.top, 440)
            Color.black
        }
        .ignoresSafeArea()
    }

    /// First render shows the strongest hero available (board items carry art + synopsis).
    private func seed() {
        focusModel.seedIfEmpty(core.boardRows.first?.items.first?.focusedHero
                               ?? core.continueWatching.first?.focusedHero)
    }

    /// Serif wordmark, the editorial signature: warm-white "Stremio" with an ember "X".
    private var header: some View {
        HStack(spacing: 0) {
            Text("Stremio").foregroundStyle(Theme.Palette.textPrimary)
            Text("X").foregroundStyle(Theme.Palette.accent)
            Spacer()
        }
        .font(Theme.Typography.wordmark)
        .padding(.horizontal, Theme.Space.screenEdge)
    }
}

/// Eyebrow kicker + section title, the shared header for every rail.
struct RailHeader: View {
    var eyebrow: String? = nil
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let eyebrow { Text(eyebrow).eyebrowStyle() }
            Text(title).sectionTitleStyle()
        }
        .padding(.horizontal, Theme.Space.screenEdge)
    }
}

/// "Continue Watching" rail from the engine (`continue_watching_preview`), newest first, with a
/// resume-progress stripe on each poster.
struct CoreContinueWatchingRow: View {
    let items: [CoreCWItem]
    var focusModel: FocusedItemModel? = nil
    var isTopRow: Bool = false   // only the page's top row shows the hero text block
    @EnvironmentObject private var theme: ThemeManager   // observe so the rail's cards repaint on a theme change

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            RailHeader(eyebrow: "Pick up where you left off", title: "Continue Watching")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Theme.Space.lg) {
                    ForEach(items) { item in
                        PosterCard(title: item.name, poster: item.poster,
                                   type: item.type, id: item.id, progress: item.progress,
                                   menu: .continueWatching,
                                   onFocus: focusModel.map { model in
                                       { model.focus(item.focusedHero, showsDetails: isTopRow) }
                                   })
                    }
                }
                .padding(.horizontal, Theme.Space.screenEdge)
                .padding(.vertical, Theme.Space.md)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One engine catalog row from the board (all installed-addon catalogs).
struct CoreCatalogRowView: View {
    let row: CoreBoardRow
    var focusModel: FocusedItemModel? = nil
    var isTopRow: Bool = false   // only the page's top row shows the hero text block
    @EnvironmentObject private var theme: ThemeManager

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            RailHeader(title: row.title)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: Theme.Space.lg) {
                    ForEach(row.items) { item in
                        PosterCard(title: item.name, poster: item.poster, type: item.type, id: item.id,
                                   menu: .catalog,
                                   onFocus: focusModel.map { model in
                                       { model.focus(item.focusedHero, showsDetails: isTopRow) }
                                   })
                    }
                }
                .padding(.horizontal, Theme.Space.screenEdge)
                .padding(.vertical, Theme.Space.md)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Skeleton rail shown while the engine is still loading (signed in). Calmer than a spinner.
struct LoadingRail: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            RailHeader(title: "Loading your library")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: Theme.Space.lg) {
                    ForEach(0..<6, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                            .fill(Theme.Palette.surface1)
                            .frame(width: kPosterWidth, height: kPosterWidth * 1.5)
                    }
                }
                .padding(.horizontal, Theme.Space.screenEdge)
                .padding(.vertical, Theme.Space.md)
            }
        }
    }
}
