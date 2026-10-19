import SwiftUI
import Combine

enum HomeTab: Hashable { case trips, stickers }

@MainActor final class HomeNavigationState: ObservableObject {
    @Published var tab = HomeTab.trips
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

    func select(_ page: HomeTab) {
        // Preserve compact geometry across page changes; idle restoration owns expansion.
        if page == .trips { isLibraryRootVisible = true }
        tabInteractionGeneration += 1
        tab = page
    }

}

/// Compact navigation between trips and the travel journal.
struct HomeBottomNavigationBar: View {
    @EnvironmentObject private var navigation: HomeNavigationState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var compact: Bool { navigation.isCollapsed }

    var body: some View {
        GeometryReader { geometry in
            let buttonWidth: CGFloat = compact ? 48 : 60
            let buttonHeight: CGFloat = compact ? 44 : 48
            let inset: CGFloat = compact ? 4 : 6
            let width = buttonWidth * 2 + inset * 2

            HStack(spacing: 0) {
                tabButton(.trips, symbol: "home.trips.fill", title: "Trips", width: buttonWidth, height: buttonHeight)
                tabButton(.stickers, symbol: "home.journal.fill", title: "Travel Journal", width: buttonWidth, height: buttonHeight)

            }
            .buttonStyle(BottomNavigationPressStyle(reduceMotion: reduceMotion))
            .background(alignment: .leading) {
                Capsule().fill(.black.opacity(0.09))
                    .frame(width: buttonWidth, height: buttonHeight)
                    .offset(x: navigation.tab == .trips ? 0 : buttonWidth)
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
            .accessibilityValue(compact ? "已收起" : "已展开")
            .animation(motion, value: compact)
            .animation(motion, value: navigation.tab)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        // Keep the layout reservation stable while the visible capsule shrinks.
        .frame(height: 60)

    }

    private var motion: Animation? {
        reduceMotion ? nil : .spring(response: 0.44, dampingFraction: 0.9, blendDuration: 0.18)
    }

    private func tabButton(_ tab: HomeTab, symbol: String, title: String, width: CGFloat, height: CGFloat) -> some View {
        Button {
            if navigation.tab != tab { AppHaptics.selection() }
            else { AppHaptics.tap() }
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
