import SwiftUI
import Combine

enum HomeTab: Hashable { case trips, stickers }

@MainActor final class HomeNavigationState: ObservableObject {
    @Published var tab = HomeTab.trips
    @Published var search = ""
    @Published var isSearchPresented = false
    @Published var isCollapsed = false
    @Published var isStickerCapturePresented = false
    @Published var isLibraryRootVisible = true
    @Published private(set) var tabInteractionGeneration = 0

    var isBottomBarVisible: Bool {
        tab == .stickers ? !isStickerCapturePresented : isLibraryRootVisible
    }
    var shouldRestoreStickerBar: Bool {
        tab == .stickers && isCollapsed && !isStickerCapturePresented
    }
    @Published private(set) var searchFocusRequest = 0
    private var handledSearchFocusRequest = 0

    func select(_ page: HomeTab) {
        isSearchPresented = false
        search = ""
        // Preserve compact geometry across page changes; idle restoration owns expansion.
        if page == .trips { isLibraryRootVisible = true }
        tabInteractionGeneration += 1
        tab = page
    }

    func activateSearch() {
        isLibraryRootVisible = true
        tab = .trips
        isCollapsed = false
        isSearchPresented = true
        searchFocusRequest += 1
    }

    func consumeSearchFocusRequest(_ request: Int) -> Bool {
        guard request > handledSearchFocusRequest else { return false }
        handledSearchFocusRequest = request
        return true
    }
}

/// One glass surface for page navigation and destination search.
struct HomeBottomNavigationBar: View {
    @EnvironmentObject private var navigation: HomeNavigationState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool

    private var searching: Bool { navigation.tab == .trips && navigation.isSearchPresented }
    private var compact: Bool { navigation.isCollapsed && !searching }
    private var focusRequest: Int? {
        searching && navigation.isBottomBarVisible ? navigation.searchFocusRequest : nil
    }

    var body: some View {
        GeometryReader { geometry in
            let buttonWidth: CGFloat = searching ? 44 : (compact ? 48 : 60)
            let buttonHeight: CGFloat = compact ? 44 : 48
            let inset: CGFloat = compact ? 4 : 6
            let width = searching ? max(240, min(520, geometry.size.width - 32)) : buttonWidth * 3 + inset * 2
            let inputWidth = searching ? max(0, width - buttonWidth * 4 - inset * 2) : 0

            HStack(spacing: 0) {
                tabButton(.trips, symbol: "home.trips.fill", title: "Trips", width: buttonWidth, height: buttonHeight)
                tabButton(.stickers, symbol: "home.journal.fill", title: "Travel Journal", width: buttonWidth, height: buttonHeight)

                Button { AppHaptics.tap(); navigation.activateSearch() } label: {
                    DoodleIcon(systemName: "home.search.fill", size: 22)
                        .scaleEffect(compact ? 20.0 / 22 : 1)
                        .frame(width: buttonWidth, height: buttonHeight)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("搜索目的地")
                .accessibilityIdentifier("home-search-toggle")

                // Retain the same field while the capsule animates, preserving focus and text.
                TextField("搜索目的地", text: $navigation.search,
                          prompt: Text("搜索目的地").foregroundStyle(.black.opacity(0.5)))
                    .font(.body)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($isFocused)
                    .onSubmit {
                        isFocused = false
                        if navigation.search.isEmpty { navigation.isSearchPresented = false }
                    }
                    .frame(width: inputWidth, height: buttonHeight)
                    .opacity(searching ? 1 : 0)
                    .allowsHitTesting(searching)
                    .accessibilityHidden(!searching)
                    .accessibilityIdentifier("home-search-input")

                Button {
                    AppHaptics.tap()
                    if navigation.search.isEmpty {
                        isFocused = false
                        navigation.isSearchPresented = false
                    } else {
                        navigation.search = ""
                        navigation.activateSearch()
                    }
                } label: {
                    DoodleIcon(systemName: "xmark.circle.fill", size: 18)
                        .foregroundStyle(.black.opacity(0.45))
                        .frame(width: 44, height: buttonHeight)
                        .contentShape(Rectangle())
                }
                .frame(width: searching ? 44 : 0, height: buttonHeight)
                .opacity(searching ? 1 : 0)
                .allowsHitTesting(searching)
                .accessibilityHidden(!searching)
                .accessibilityLabel(navigation.search.isEmpty ? "结束搜索" : "清除搜索内容")
                .accessibilityIdentifier("home-search-clear")
            }
            .buttonStyle(BottomNavigationPressStyle(reduceMotion: reduceMotion))
            .background(alignment: .leading) {
                Capsule().fill(.black.opacity(0.09))
                    .frame(width: buttonWidth, height: buttonHeight)
                    .offset(x: navigation.tab == .trips ? 0 : buttonWidth)
                    .opacity(searching ? 0 : 1)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .font(.system(size: 22, weight: .regular))
            .foregroundStyle(.black)
            .tint(.black)
            .padding(inset)
            .frame(width: width, height: buttonHeight + inset * 2)
            .clipShape(Capsule())
            .glassEffect(.regular.interactive(), in: Capsule())
            .environment(\.colorScheme, .light)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("home-bottom-navigation")
            .accessibilityValue(searching ? "搜索中" : (compact ? "已收起" : "已展开"))
            .animation(motion, value: compact)
            .animation(motion, value: searching)
            .animation(motion, value: navigation.tab)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        // Keep the layout reservation stable while the visible capsule shrinks.
        .frame(height: 60)
        .task(id: focusRequest) {
            guard let request = focusRequest else { isFocused = false; return }
            await Task.yield()
            guard !Task.isCancelled, focusRequest == request,
                  navigation.consumeSearchFocusRequest(request) else { return }
            isFocused = true
        }
        .onDisappear { isFocused = false }
    }

    private var motion: Animation? {
        reduceMotion ? nil : .spring(response: 0.44, dampingFraction: 0.9, blendDuration: 0.18)
    }

    private func tabButton(_ tab: HomeTab, symbol: String, title: String, width: CGFloat, height: CGFloat) -> some View {
        Button {
            if navigation.tab != tab { AppHaptics.selection() }
            else { AppHaptics.tap() }
            isFocused = false
            navigation.select(tab)
        } label: {
            DoodleIcon(systemName: symbol, size: 22)
                .scaleEffect(compact ? 20.0 / 22 : 1)
                .frame(width: width, height: height)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(AppLocalization.text(title))
        .accessibilityAddTraits(navigation.tab == tab ? .isSelected : [])
        .accessibilityIdentifier(tab == .trips ? "home-tab-trips" : "home-tab-stickers")
    }
}

private struct BottomNavigationPressStyle: ButtonStyle {
    let reduceMotion: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.85), value: configuration.isPressed)
    }
}
