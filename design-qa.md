# Rounded interface icon QA

final result: passed

## Scope and visual truth

- User approved the third displayed icon concept, “糯糯轮廓”. Scope is the existing native iOS and Mac interface icon family, not a new screen design or launcher icon.
- Source: `Design/IconSources/rounded-approved.png` (1254 × 1254 pixels).
- Combined source/implementation evidence: `../work/rounded-source-comparison.png` (1440 × 800). The source board is shown alongside the 16 principal icons rendered directly from the final production PDFs, enlarged and at 24pt. Both were opened together for review.
- Full catalog evidence: `../work/doodle-icon-sheet.png` (1280 × 1125); 70 unique assets serving 84 semantic names.
- Native iOS captures: `../work/rounded-ios-home.png` and `../work/rounded-ios-journal.png`, captured with simctl on iPhone 17 / iOS 27. These are device-screen captures, without the Device Hub frame.
- iOS viewport: 402 × 874pt, 3× density (1206 × 2622 pixels). CSS viewport is not applicable to native SwiftUI.
- Mac: the running `/Applications/漫游.app` was visually inspected with CUA in dark appearance, including the library/search, settings menu, and trip cards. CUA screenshots were reviewed inline at 2048 × 1536; no standalone Mac screenshot was exported.
- State: normal installed application, English UI; Trips and Travel Journal tab states and existing Mac itinerary. No test reset or content modification.

## Findings and iteration history

1. [P2, resolved] Dense interior details in train, bed, and fork icons merged at small size. The first enlarged/24pt comparison showed crowded train trim, pillows, and fork tines. Removed those optional upstream paths and used 2.25-unit interior strokes on train/bed while retaining 3-unit outer strokes. The final combined comparison and native Mac trip-card view show clear negative space.
2. [P2, resolved] Initial link, undo, and gear variants differed unnecessarily from the intended open, rounded silhouettes. Selected simpler official library variants (Link04, Undo03, Settings02); final combined comparison verifies cleaner silhouettes and rounded joins.
3. [Resolved distribution issue] Added the complete Hugeicons MIT notice to both app resource folders. Verified it exists in both final built bundles.

No actionable P0/P1/P2 issues remain in this icon-only scope.

## Required fidelity surfaces

- **Fonts / typography:** Interface titles, body copy, and journal handwriting remain unchanged. The concept board's display lettering is not part of the requested icon replacement. Native menu labels remain standard `Label<Text, Image>` and retain their localization/accessibility behavior.
- **Spacing / layout rhythm:** Existing control frames, padding, navigation capsules, and hit areas are preserved. All PDFs share a 24-unit viewport with a 22-unit optical fit. Selected/unselected tabs use the same silhouette, avoiding icon geometry changes during tab animations.
- **Colors / tokens:** Template rendering preserves screen tint, category colors, and light/dark foreground colors. Black navigation icons on the light journal and colored category icons on dark Mac cards were inspected.
- **Image quality / asset fidelity:** Smooth round caps/joins, simplified bold outlines, and vector scaling replace the earlier uneven doodles. Source geometry is from the official MIT-licensed Hugeicons Stroke Rounded library, with reproducible adaptations in `style.json`; no hand-authored replacement geometry. Enlarged and 24pt views were compared together.
- **Copy / content:** Control names, localized labels, travel data, and title text are unchanged. Mac settings menu accessibility text retains Language, iCloud Sync, Trash, Shared Inbox, Trip Templates, New Trip, and Import Trip File.

## Verification

- Final iOS simulator and Mac Catalyst Release builds succeeded; logs: `../work/rounded-ios-build.log`, `../work/rounded-mac-build.log`.
- Installed and launched the simulator build; checked tab switching and opening the Beijing template. Updated and launched the Mac app, verified its signature, opened its menu and an existing itinerary.
- All 84 semantic names map to valid assets; both platforms have exactly 70 image sets with byte-identical PDFs, asset metadata, and helpers.
- Original upstream nodes, package integrity, and license were independently checked. Old generated catalog assets were removed; previous artwork/app are backed up under `../work/before-rounded-icons`.
- No phone installation, App Store submission, or Git push was performed.

## Follow-up polish and limits

- [P3] Library silhouettes follow the approved visual direction rather than matching generated artwork point for point: suitcase proportions, journal spine, six-lobed settings, and three-panel map differ slightly from the concept board. Rounded outline weight, simple forms, and readable meanings are preserved.
- System-owned status indicators, native automatic controls, and window chrome are outside the app-owned icon catalog.
- Physical-device appearance was not rechecked because the user asked to defer phone installation. No functional logic or gesture changes were made in this round.

## Implementation checklist

- [x] Preserve the approved visual reference and licensed upstream artwork.
- [x] Generate matching local vector catalogs for both platforms.
- [x] Resolve crowded small-size details and inspect the revised comparison.
- [x] Build, run, and inspect the native applications.
- [x] Preserve existing fonts, colors, content, and interactions.

## 2026-10-04 — Four solid home icons

- Replaced the iOS home Settings, Trips, Travel Journal, and Search silhouettes with the soft, filled MingCute variants. Other icons retain the approved rounded outline style. The shared catalog now has 74 assets for 88 semantic names.
- Inspected the final production PDF preview (`../work/home-solid-icons-preview.png`) and both native UI-test screenshots under `../work/home-solid-icons-screenshots/`. The small black silhouettes, transparent cutouts, unchanged control geometry, and expanded search layout render correctly.
- Both home search/navigation UI tests passed (`../work/HomeSolidIcons.xcresult`). The signed iPhone Release build succeeded (`../work/home-solid-icons-device-build.log`), its signature validates, and its bundle includes the MingCute Apache-2.0 license.
- Phone installation was attempted for Apple的iPhone (iPhone 15 Pro Max), but the device connection could not satisfy CoreDevice service requirements (4016). The updated app is available in the simulator; this attempt did not update the physical phone.
