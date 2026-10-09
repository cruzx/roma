import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A local vector illustration. Semantic names deliberately match our models,
/// but the rendered artwork comes from the approved smooth, rounded catalog.
struct DoodleIcon: View {
    let systemName: String
    @ScaledMetric(relativeTo: .body) private var scaledSize: CGFloat = 20

    init(systemName: String, size: CGFloat = 20) {
        self.systemName = systemName
        _scaledSize = ScaledMetric(wrappedValue: size, relativeTo: .body)
    }

    var body: some View {
        Image(decorative: Self.assetName(for: systemName))
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: scaledSize, height: scaledSize)
    }

    /// Native menus extract a standard Label<Text, Image>. Keep its icon as an
    /// Image instead of wrapping it in a custom View, and cache the tiny raster
    /// made from the local vector asset so rebuilding a menu never redraws it.
    @MainActor
    static func labelImage(for systemName: String, size: CGFloat) -> Image {
        #if canImport(UIKit)
        if let image = nativeImage(systemName, size: size) {
            return Image(uiImage: image).renderingMode(.template)
        }
        #endif
        return Image(assetName(for: systemName)).renderingMode(.template)
    }

    #if canImport(UIKit)
    @MainActor private static let nativeImages = NSCache<NSString, UIImage>()

    @MainActor
    private static func nativeImage(_ systemName: String, size: CGFloat) -> UIImage? {
        let name = assetName(for: systemName)
        let key = "\(name):\(size)" as NSString
        if let cached = nativeImages.object(forKey: key) { return cached }
        guard let source = UIImage(named: name) else { return nil }
        let bounds = CGRect(x: 0, y: 0, width: size, height: size)
        let image = UIGraphicsImageRenderer(size: bounds.size).image { _ in
            source.withRenderingMode(.alwaysOriginal).draw(in: bounds)
        }.withRenderingMode(.alwaysTemplate)
        nativeImages.setObject(image, forKey: key)
        return image
    }
    #endif

    /// Set only the images used by native search and navigation controls. Their
    /// system behavior, tint, materials, and accessibility remain unchanged.
    @MainActor
    static func configureNativeControls() {
        #if canImport(UIKit)
        let searchBar = UISearchBar.appearance()
        if let search = nativeImage("magnifyingglass", size: 18) {
            searchBar.setImage(search, for: .search, state: .normal)
        }
        if let clear = nativeImage("xmark.circle.fill", size: 16) {
            searchBar.setImage(clear, for: .clear, state: .normal)
        }
        if let back = nativeImage("chevron.left", size: 20) {
            let navigationBar = UINavigationBar.appearance()
            navigationBar.backIndicatorImage = back
            navigationBar.backIndicatorTransitionMaskImage = back
        }
        #endif
    }

    static func assetName(for systemName: String) -> String {
        if let asset = assets[systemName] { return asset }
        if systemName.hasSuffix(".fill"), let asset = assets[String(systemName.dropLast(5))] { return asset }
        return assets["questionmark"]!
    }

    static let assets: [String: String] = [
        "airplane": "Doodle_Airplane01Icon",
        "arrow.down": "Doodle_ArrowDown02Icon",
        "arrow.triangle.2.circlepath.camera": "Doodle_SwitchCameraIcon",
        "arrow.triangle.turn.up.right.diamond": "Doodle_Route01Icon",
        "arrow.up": "Doodle_ArrowUp02Icon",
        "arrow.up.arrow.down": "Doodle_ArrowUpDownIcon",
        "arrow.up.left.and.arrow.down.right": "Doodle_ArrowExpand01Icon",
        "arrow.up.right": "Doodle_ArrowUpRight01Icon",
        "arrow.up.right.square": "Doodle_ExternalLinkIcon",
        "arrow.uturn.backward": "Doodle_Undo03Icon",
        "bed.double": "Doodle_BedDoubleIcon",
        "bicycle": "Doodle_Bicycle01Icon",
        "building.2": "Doodle_Building03Icon",
        "building.columns": "Doodle_BankIcon",
        "bus.fill": "Doodle_BusFrontIcon",
        "calendar": "Doodle_Calendar03Icon",
        "calendar.badge.minus": "Doodle_CalendarRemove01Icon",
        "calendar.badge.plus": "Doodle_CalendarAdd01Icon",
        "camera": "Doodle_Camera01Icon",
        "camera.badge.ellipsis": "Doodle_Camera01Icon",
        "camera.fill": "Doodle_Camera01Icon",
        "car.side.fill": "Doodle_Car01Icon",
        "checklist": "Doodle_CheckListIcon",
        "checkmark": "Doodle_Tick02Icon",
        "checkmark.circle": "Doodle_CheckmarkCircle02Icon",
        "checkmark.circle.fill": "Doodle_CheckmarkCircle02Icon",
        "chevron.left": "Doodle_ArrowLeft01Icon",
        "chevron.right": "Doodle_ArrowRight01Icon",
        "chevron.up.chevron.down": "Doodle_ArrowUpDownIcon",
        "circle": "Doodle_CircleIcon",
        "clock": "Doodle_Clock01Icon",
        "creditcard": "Doodle_Wallet01Icon",
        "ellipsis": "Doodle_MoreHorizontalIcon",
        "ellipsis.circle": "Doodle_MoreHorizontalCircle01Icon",
        "exclamationmark.triangle": "Doodle_Alert02Icon",
        "ferry": "Doodle_FerryBoatIcon",
        "ferry.fill": "Doodle_FerryBoatIcon",
        "figure.walk": "Doodle_WalkingIcon",
        "folder": "Doodle_Folder01Icon",
        "fork.knife": "Doodle_UtensilsIcon",
        "gearshape": "Doodle_Settings02Icon",
        "globe": "Doodle_GlobalIcon",
        "globe.asia.australia.fill": "Doodle_GlobalIcon",
        "home.journal.fill": "Doodle_notebook_2",
        "home.search.fill": "Doodle_search_3",
        "home.settings.fill": "Doodle_settings_3",
        "home.trips.fill": "Doodle_luggage",
        "icloud": "Doodle_CloudIcon",
        "leaf": "Doodle_Leaf01Icon",
        "link": "Doodle_Link04Icon",
        "magnifyingglass": "Doodle_Search01Icon",
        "map": "Doodle_MapsIcon",
        "mappin": "Doodle_Location01Icon",
        "mappin.circle.fill": "Doodle_Location01Icon",
        "mountain.2": "Doodle_MountainIcon",
        "note.text": "Doodle_Note01Icon",
        "paintpalette": "Doodle_PaintBoardIcon",
        "pencil": "Doodle_PencilEdit01Icon",
        "photo": "Doodle_Image01Icon",
        "photo.badge.exclamationmark": "Doodle_ImageNotFound01Icon",
        "photo.badge.plus": "Doodle_ImageAdd01Icon",
        "photo.on.rectangle": "Doodle_Image01Icon",
        "plus": "Doodle_Add01Icon",
        "plus.circle": "Doodle_AddCircleIcon",
        "plus.circle.fill": "Doodle_AddCircleIcon",
        "point.topleft.down.to.point.bottomright.curvepath": "Doodle_Route01Icon",
        "questionmark": "Doodle_CircleQuestionMarkIcon",
        "rectangle.stack": "Doodle_Layers01Icon",
        "scope": "Doodle_FocusIcon",
        "sparkles.rectangle.stack": "Doodle_Album01Icon",
        "square.3.layers.3d.top.filled": "Doodle_LayerBringToFrontIcon",
        "square.and.arrow.down": "Doodle_Download01Icon",
        "square.and.arrow.up": "Doodle_Upload01Icon",
        "square.grid.2x2": "Doodle_DashboardSquare01Icon",
        "square.on.circle": "Doodle_BookBookmark02Icon",
        "square.on.circle.fill": "Doodle_BookBookmark02Icon",
        "suitcase": "Doodle_Luggage01Icon",
        "suitcase.rolling": "Doodle_Luggage02Icon",
        "suitcase.rolling.fill": "Doodle_Luggage02Icon",
        "sun.max.fill": "Doodle_Sun03Icon",
        "train.side.front.car": "Doodle_TrainFrontIcon",
        "train.side.middle.car": "Doodle_Train01Icon",
        "tram": "Doodle_TrainFrontIcon",
        "tram.fill": "Doodle_TrainFrontIcon",
        "trash": "Doodle_Delete02Icon",
        "water.waves": "Doodle_WavesIcon",
        "xmark": "Doodle_Cancel01Icon",
        "xmark.circle.fill": "Doodle_CancelCircleIcon",
    ]
}

extension Label where Title == Text, Icon == Image {
    @MainActor
    init(_ titleKey: LocalizedStringKey, doodleSystemImage: String, size: CGFloat = 20) {
        self.init { Text(titleKey) } icon: { DoodleIcon.labelImage(for: doodleSystemImage, size: size) }
    }

    @_disfavoredOverload
    @MainActor
    init<S: StringProtocol>(_ title: S, doodleSystemImage: String, size: CGFloat = 20) {
        self.init { Text(title) } icon: { DoodleIcon.labelImage(for: doodleSystemImage, size: size) }
    }
}

extension Button where Label == SwiftUI.Label<Text, Image> {
    @MainActor
    init(_ titleKey: LocalizedStringKey, doodleSystemImage: String, size: CGFloat = 20,
         role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.init(role: role, action: action) {
            SwiftUI.Label(titleKey, doodleSystemImage: doodleSystemImage, size: size)
        }
    }

    @_disfavoredOverload
    @MainActor
    init<S: StringProtocol>(_ title: S, doodleSystemImage: String, size: CGFloat = 20,
                           role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.init(role: role, action: action) {
            SwiftUI.Label(title, doodleSystemImage: doodleSystemImage, size: size)
        }
    }
}
