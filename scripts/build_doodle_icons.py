#!/usr/bin/env python3
"""Build identical local vector icon catalogs and semantic SwiftUI helpers."""
from pathlib import Path
import json
import re
import xml.etree.ElementTree as ET
from reportlab import rl_config
from reportlab.graphics import renderPDF
from reportlab.graphics.shapes import Drawing
from svglib.svglib import svg2rlg

ROOT = Path(__file__).resolve().parents[1]
rl_config.invariant = 1  # Reproducible PDFs without timestamp differences.
SOURCES = ROOT / "Design/IconSources"
manifest = json.loads((SOURCES / "manifest.json").read_text())

# Render the licensed library geometry with the approved rounded outline weight.
# Keep original nodes so this adaptation is reproducible without a network fetch.
library = SOURCES / "Hugeicons"
style = json.loads((library / "style.json").read_text())
nodes_by_name = json.loads((library / "upstream-nodes.json").read_text())
for name, nodes in nodes_by_name.items():
    svg = ET.Element("svg", {"xmlns": "http://www.w3.org/2000/svg", "width": "24", "height": "24",
                             "viewBox": "0 0 24 24", "fill": "none", "stroke": "#000000",
                             "stroke-linecap": "round", "stroke-linejoin": "round"})
    omitted = style["omittedDecorativePaths"].get(name, [])
    for tag, attributes in nodes:
        if attributes.get("key") in omitted:
            continue
        attrs = {re.sub(r"([A-Z])", lambda match: "-" + match[1].lower(), key): str(value)
                 for key, value in attributes.items() if key != "key"}
        for key, value in list(attrs.items()):
            if value == "currentColor":
                attrs[key] = "#000000"
        if "stroke-width" in attrs:
            attrs["stroke-width"] = str(style.get("detailStrokeWidths", {}).get(name, {}).get(
                attributes.get("key"), style["strokeWidth"]))
        attrs["stroke-linecap"] = "round"
        attrs["stroke-linejoin"] = "round"
        ET.SubElement(svg, tag, attrs)
    (library / f"{name}.svg").write_text(ET.tostring(svg, encoding="unicode") + "\n")

for source in sorted(set(manifest.values())):
    artwork = svg2rlg(str(SOURCES / source))
    if artwork is None or artwork.width <= 0 or artwork.height <= 0:
        raise ValueError(f"Unreadable SVG: {source}")
    # A square optical box avoids per-icon layout shifts during tab animation.
    factor = 22 / max(artwork.width, artwork.height)
    artwork.scale(factor, factor)
    artwork.translate((24 / factor - artwork.width) / 2,
                      (24 / factor - artwork.height) / 2)
    drawing = Drawing(24, 24)
    drawing.add(artwork)
    asset = "Doodle_" + Path(source).stem.replace("-", "_")
    for platform in ("iOS", "macOS"):
        folder = ROOT / platform / "Roam/Assets.xcassets/DoodleIcons" / (asset + ".imageset")
        folder.mkdir(parents=True, exist_ok=True)
        renderPDF.drawToFile(drawing, str(folder / "icon.pdf"))
        (folder / "Contents.json").write_text(json.dumps({
            "images": [{"filename": "icon.pdf", "idiom": "universal"}],
            "info": {"author": "xcode", "version": 1},
            "properties": {"preserves-vector-representation": True,
                           "template-rendering-intent": "template"},
        }, indent=2) + "\n")

mapping = "\n".join(f'        "{key}": "Doodle_{Path(value).stem.replace(chr(45), chr(95))}",' for key, value in sorted(manifest.items()))
swift = r'''import SwiftUI
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
__MAPPING__
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
'''.replace("__MAPPING__", mapping)

for platform in ("iOS", "macOS"):
    (ROOT / platform / "Roam/DoodleIcon.swift").write_text(swift)
    (ROOT / platform / "Roam/Hugeicons-License.txt").write_text(
        "Hugeicons Free — rounded interface icons\n\n" + (library / "LICENSE.md").read_text())
    (ROOT / platform / "Roam/MingCute-License.txt").write_text(
        "MingCute — home solid icons (https://github.com/mingcute-design/mingcute-icons)\n\n"
        + (SOURCES / "MingCute/LICENSE").read_text())
    catalog = ROOT / platform / "Roam/Assets.xcassets/DoodleIcons/Contents.json"
    catalog.write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
print(f"Built {len(set(manifest.values()))} vector assets for {len(manifest)} semantic names on both platforms.")
