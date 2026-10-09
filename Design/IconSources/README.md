# Roam rounded interface icons

The shared catalog contains 70 rounded-outline icons and four home-only solid
icons, serving 88 semantic names. The outline family follows the approved preview in
`rounded-approved.png`. These remain transparent template PDFs, inheriting each
screen's color, Dynamic Type sizing, and existing accessibility labels. The
launcher artwork in `Design/AppIcon` is independent of this interface update.

## Source and adaptation

- Collection: Hugeicons Free, Stroke Rounded.
- Official source: <https://github.com/hugeicons/hugeicons>.
- Package: `@hugeicons/core-free-icons`, version 4.3.5.
- License: MIT; the complete copyright and license are in `Hugeicons/LICENSE.md`
  and bundled in both apps as `Hugeicons-License.txt`.
- Package URL and integrity are recorded in `Hugeicons/provenance.json`.
- Original selected path arrays are stored in `Hugeicons/upstream-nodes.json`.

The build changes stroke width to 3 in a 24-unit viewport, retains smooth round
caps and joins, then fits artwork into a 22-unit optical box. `style.json` records
omitted decorative paths: camera indicator, luggage ribs, memo binding rings,
the middle fork tine, crowded train trim, and bed pillows. Train and bed interior
lines use 2.25 units to preserve small-size negative space. This keeps compact icons legible without changing
control meanings. Geometry comes from the licensed library; the preview is the
visual direction, not a claim of identical geometry for every glyph.

`manifest.json` and `Hugeicons/semantic-map.json` retain the original semantic
names, so model values and saved data do not depend on the chosen icon family.
The `DoodleIcon` type and catalog names are retained for API compatibility.
Unknown names use the rounded question-circle icon.

## Home solid variant

The four iOS home controls use official MingCute Core Filled artwork: `luggage`,
`notebook-2`, `settings-3`, and `search-3`. Their dedicated `home.*.fill` semantic
names keep detail-screen and menu icons unchanged. The same filled tab silhouette
is used when selected and unselected; selection is communicated by the existing
animated capsule. Control sizes, labels, hit regions, and layout remain intact.

Original SVG geometry is retained in `MingCute/` with `provenance.json` pinning
the upstream commit. Source: <https://github.com/mingcute-design/mingcute-icons>.
License: Apache-2.0, in `MingCute/LICENSE`; it is also bundled as
`MingCute-License.txt`. The generator only converts to template PDF and applies
the common optical fit. No external icon service or runtime package is needed.

## Archived first style

`DoodleIcons/` and `Roam/` preserve the previous hand-drawn sources. They are not
included in the current manifest or app catalog. The original Doodle collection
was made by Khushmeen Sidhu (<https://khushmeen.com/icons>), under CC0 1.0; its
legal text is in `DoodleIcons/CC0-1.0.txt`. The download mirror was
<https://github.com/svatsa159/react-doodle-icons>, revision
`b51da0371e992b5d03e768fd1f570e8e9500c617`, with its MIT notice also retained.
`Roam/` contains the app's earlier original supplemental artwork.

## Build and usage

Run `python3 scripts/build_doodle_icons.py` after installing the small build-only
dependencies in `scripts/doodle-icons-requirements.txt`. The script produces
identical template PDF image sets under `iOS/Roam/Assets.xcassets/DoodleIcons` and
`macOS/Roam/Assets.xcassets/DoodleIcons`, plus identical `DoodleIcon.swift` helpers.
The app itself has no new runtime dependency.

Use `DoodleIcon(systemName: "map", size: 20)`, or
`Label("Map", doodleSystemImage: "map")`. Buttons have the same explicit
`doodleSystemImage:` spelling. Set `size:` when changing an icon's dimensions;
`.font` continues to style text. Icons inherit their surrounding foreground
style and scale with Dynamic Type. Use a semantic accessibility label on an
icon-only control; decorative icon images are hidden from VoiceOver.
