import SwiftUI
import PhotosUI

struct StickerBoardView: View {
    @EnvironmentObject private var board: StickerBoardStore
    @EnvironmentObject private var navigation: HomeNavigationState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedID: UUID?
    @State private var undoNoticeID: UUID?
    @State private var transformingItemID: UUID?
    @State private var cameraPresentation = StickerCameraPresentation()
    @State private var frozenCameraLayout: CameraLayout?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var processing = false
    @State private var processingTask: Task<Void, Never>?
    @State private var processingID = UUID()
    @State private var textEditor: StickerTextDraft?
    @State private var borderColorEditor: StickerCanvasItem?
    @State private var images: [UUID: UIImage] = [:]
    @State private var restingCanvasTop: CGFloat?
    @State private var canvasNavigation = StickerCanvasGestureSession()
    @State private var canvasMotion = StickerCanvasMotion()
    @State private var canvasSize = CGSize.zero
    @GestureState private var canvasNavigationGestureActive = false
    @GestureState private var closingCameraGestureActive = false

    private var selectedItem: StickerCanvasItem? { board.items.first { $0.id == selectedID } }
    private var cameraOpen: Bool { cameraPresentation.isMounted }
    private var canBrowseCanvas: Bool {
        !processing && textEditor == nil && borderColorEditor == nil &&
            (!cameraOpen || cameraPresentation.phase == .pulling)
    }

    var body: some View {
        GeometryReader { geometry in
            let layout = cameraLayout(in: geometry)
            let offset = canvasOffset(in: geometry.size)
            ZStack(alignment: .top) {
                StickerCanvasPaper(offset: offset, motion: canvasMotion)
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture(count: 2).onEnded { tap in
                        writeText(at: worldPosition(tap.location, in: geometry.size))
                    })
                    .simultaneousGesture(TapGesture().onEnded { selectedID = nil })
                    .simultaneousGesture(browseCanvasGesture(in: geometry.size, cameraLayout: layout))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("无限画布")
                    .accessibilityHint("左右滑动浏览画布，下拉打开相机，双击空白处添加文字")
                    .accessibilityIdentifier("sticker-canvas")
                    .accessibilityAction(named: "向右浏览画布") { panCanvas(by: CGSize(width: -geometry.size.width * 0.75, height: 0), in: geometry.size) }
                    .accessibilityAction(named: "向左浏览画布") { panCanvas(by: CGSize(width: geometry.size.width * 0.75, height: 0), in: geometry.size) }
                    .accessibilityAction(named: "打开相机") { openCamera(layout: layout) }
                    .allowsHitTesting(canBrowseCanvas)
                    .accessibilityHidden(cameraOpen || processing)

                if board.items.isEmpty {
                    VStack(spacing: 14) {
                        DoodleIcon(systemName: "sparkles.rectangle.stack", size: 48).rotationEffect(.degrees(-8))
                        Text("把眼前的喜欢，贴在这里").font(JournalHandwriting.scaled(22, relativeTo: .title3))
                        Text("左右滑动画布 · 下拉拍照\n长按移动贴纸 · 双击空白处写字")
                            .font(JournalHandwriting.scaled(17, relativeTo: .subheadline)).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center).lineSpacing(6)
                    }
                    .foregroundStyle(Color(red: 0.38, green: 0.35, blue: 0.30))
                    .position(x: geometry.size.width / 2, y: geometry.size.height * 0.46)
                    .allowsHitTesting(false)
                    .accessibilityHidden(cameraOpen || processing)
                }

                StickerCanvasTranslatedLayer(offset: offset, motion: canvasMotion, size: geometry.size) {
                    ForEach(board.items) { item in
                        canvasElement(item, size: geometry.size, cameraLayout: layout)
                            .accessibilityHidden(cameraOpen || processing)
                    }
                }
                .allowsHitTesting(canBrowseCanvas)

                header(canvasSize: geometry.size, cameraLayout: layout)
                    .padding(.horizontal, 22).padding(.top, 6)
                    .accessibilityHidden(cameraOpen || processing)

                VStack {
                    Spacer()
                    if selectedItem != nil { selectionControls }
                    else if board.canUndoRemoval && undoNoticeID != nil {
                        Button(action: undoRemoval) { Label("撤销删除", doodleSystemImage: "arrow.uturn.backward") }
                            .font(.subheadline.weight(.medium)).padding(14)
                            .glassEffect(.regular, in: Capsule())
                            .accessibilityIdentifier("sticker-undo")
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 14)
                .allowsHitTesting(!cameraOpen && !processing)
                .accessibilityHidden(cameraOpen || processing)

                if cameraOpen {
                    Color.black.opacity(0.20 * cameraPresentation.progress).ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { closeCameraFromInteraction() }
                        .gesture(closeCameraGesture(layout: layout))
                        .allowsHitTesting(cameraPresentation.isInteractive)
                        .accessibilityHidden(true)
                }

                GeometryReader { cameraViewport in
                    cameraSurface(layout: layout)
                        .frame(maxWidth: .infinity, alignment: .top)
                        .offset(y: layout.globalTop - cameraViewport.frame(in: .global).minY)
                }
                    // The camera animates in screen space; status-bar safe-area changes
                    // must not add another movement to its island anchor.
                    .ignoresSafeArea(.container, edges: .top)
                    .zIndex(20)
                    .allowsHitTesting(cameraPresentation.isInteractive && !processing)
                    .accessibilityHidden(!cameraPresentation.isInteractive || processing)

                if processing {
                    Color.black.opacity(0.16).ignoresSafeArea()
                    VStack(spacing: 16) {
                        ProgressView().controlSize(.large)
                        Text("正在抠出主体…").font(.headline)
                        Button("取消") { AppHaptics.tap(); cancelProcessing() }.font(.subheadline)
                    }
                    .padding(28).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("sticker-processing")
                    .zIndex(30)
                }
            }
            .coordinateSpace(name: "sticker-board")
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { top in
                // Hiding the status bar must not move the animation's starting point.
                if !cameraOpen { restingCanvasTop = top }
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                finishCanvasPan()
                if canvasNavigationGestureActive { canvasNavigation.cancel() }
                canvasSize = size
            }
        }
        .background(Color(red: 0.96, green: 0.945, blue: 0.91).ignoresSafeArea())
        .statusBarHidden(cameraPresentation.hidesStatusBar)
        .tint(.black)
        .onAppear { loadImages() }
        .task(id: undoNoticeID) {
            guard let noticeID = undoNoticeID else { return }
            do { try await Task.sleep(for: .seconds(5)) }
            catch { return }
            guard !Task.isCancelled, undoNoticeID == noticeID else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                undoNoticeID = nil
            }
        }
        .onChange(of: board.canUndoRemoval) { _, canUndo in
            if !canUndo { undoNoticeID = nil }
        }
        .onChange(of: board.items.map(\.id)) { _, _ in loadImages() }
        .onChange(of: selectedPhoto) { _, photo in
            guard let photo else { return }
            cancelProcessing()
            let token = UUID()
            processingID = token
            processing = true
            processingTask = Task {
                do {
                    guard let data = try await photo.loadTransferable(type: Data.self) else { throw StickerSubjectError.unreadableImage }
                    try Task.checkCancellation()
                    let cutout = try await StickerSubjectProcessor.cutout(from: data)
                    try Task.checkCancellation()
                    selectedID = board.addSticker(cutout, at: nextPosition)
                    if selectedID != nil { AppHaptics.success() }
                    else { AppHaptics.error() }
                } catch is CancellationError { return }
                catch {
                    guard !Task.isCancelled, processingID == token else { return }
                    board.error = error.localizedDescription
                    AppHaptics.error()
                }
                guard !Task.isCancelled, processingID == token else { return }
                processing = false
                selectedPhoto = nil
            }
        }
        .onChange(of: cameraOpen || processing) { _, presented in
            if presented { finishCanvasPan() }
            navigation.isStickerCapturePresented = presented
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                finishCanvasPan()
                if canvasNavigationGestureActive { canvasNavigation.cancel() }
            }
        }
        .onChange(of: canvasNavigationGestureActive) { _, active in
            if !active {
                // A cancelled touch keeps its last visible position. A completed
                // swipe owns its coast and will save once that coast has settled.
                if canvasMotion.isDragging { finishCanvasPan() }
                canvasNavigation.reset()
                cancelCameraDragIfNeeded()
            }
        }
        .onChange(of: closingCameraGestureActive) { _, active in
            if !active { cancelCameraDragIfNeeded() }
        }
        .onDisappear {
            finishCanvasPan()
            undoNoticeID = nil
            transformingItemID = nil
            canvasNavigation.reset()
            cameraPresentation.reset()
            frozenCameraLayout = nil
            cancelProcessing()
            navigation.isStickerCapturePresented = false
        }
        .sheet(item: $textEditor) { draft in
            StickerTextEditor(draft: draft) { text, color, size in
                if let id = draft.itemID {
                    change(id) { item in item.text = text; item.textColor = color; item.fontSize = size }
                    selectedID = id
                    return board.error
                } else {
                    selectedID = board.addText(text, at: draft.position, color: color, fontSize: size)
                    return selectedID == nil ? (board.error ?? AppLocalization.text("文字未能保存，请重试。")) : nil
                }
            }
        }
        .sheet(item: $borderColorEditor) { item in
            StickerBorderColorEditor(item: item, image: images[item.id]) { color in
                guard item.borderColorHex != color else { return nil }
                change(item.id) { $0.borderColor = color }
                // The editor owns a failed save's alert; do not repeat it after dismissal.
                let saveError = board.error
                board.error = nil
                return saveError
            }
        }
        .alert("Travel Journal", isPresented: Binding(get: { board.error != nil && textEditor == nil && borderColorEditor == nil }, set: { if !$0 { board.error = nil } })) {
            Button("好") { AppHaptics.tap(); board.error = nil }
        } message: { Text(board.error ?? "") }
    }

    private struct CameraLayout {
        let globalTop: CGFloat
        let width: CGFloat
        let height: CGFloat
        let collapsedWidth: CGFloat
        let collapsedHeight: CGFloat
        let viewfinderTopInset: CGFloat

        var dragTravel: CGFloat { max(240, height - collapsedHeight) }
    }

    private func cameraLayout(in geometry: GeometryProxy) -> CameraLayout {
        if let frozenCameraLayout { return frozenCameraLayout }
        let canvasTop = geometry.frame(in: .global).minY
        let restingTop = restingCanvasTop ?? canvasTop
        // Public safe-area geometry supplies a visual anchor; the system island itself is untouched.
        let hasIslandAnchor = UIDevice.current.userInterfaceIdiom == .phone &&
            geometry.size.height > geometry.size.width && (51...100).contains(restingTop)
        let screenTop = hasIslandAnchor ? restingTop - 48 : max(12, restingTop)
        let top = screenTop - canvasTop
        return CameraLayout(globalTop: screenTop,
                            width: min(520, max(0, geometry.size.width - 24)),
                            height: min(620, max(0, geometry.size.height - top - 16)),
                            collapsedWidth: hasIslandAnchor ? 126 : 82,
                            collapsedHeight: hasIslandAnchor ? 37 : 28,
                            viewfinderTopInset: hasIslandAnchor ? restingTop - screenTop + 8 : 28)
    }

    private func browseCanvasGesture(in size: CGSize, cameraLayout layout: CameraLayout) -> AnyGesture<DragGesture.Value> {
        AnyGesture(DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .updating($canvasNavigationGestureActive) { _, active, _ in active = true }
            .onChanged { drag in
                guard canBrowseCanvas, transformingItemID == nil else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                transaction.tracksVelocity = true
                transaction.isContinuous = true
                withTransaction(transaction) {
                    switch canvasNavigation.update(translation: drag.translation) {
                    case .horizontal:
                        if selectedID != nil { selectedID = nil }
                        canvasMotion.drag(to: drag.translation.width)
                    case .camera:
                        finishCanvasPan()
                        if cameraPresentation.updateOpening(translation: drag.translation, travel: layout.dragTravel),
                           frozenCameraLayout == nil {
                            frozenCameraLayout = layout
                            selectedID = nil
                        }
                    case .undecided, .ignored:
                        break
                    }
                }
            }
            .onEnded { drag in
                guard transformingItemID == nil else {
                    canvasNavigation.reset()
                    return
                }
                switch canvasNavigation.intent {
                case .horizontal:
                    canvasMotion.drag(to: drag.translation.width)
                    canvasMotion.endDrag(
                        predictedAdditionalTravel: drag.predictedEndTranslation.width - drag.translation.width,
                        viewportWidth: size.width, reduceMotion: reduceMotion
                    ) { finishCanvasPan() }
                case .camera:
                    if let open = cameraPresentation.finishOpening(translation: drag.translation, predicted: drag.predictedEndTranslation) {
                        if open { AppHaptics.tap() }
                        settleCamera(open: open)
                    }
                case .undecided, .ignored:
                    break
                }
                canvasNavigation.reset()
            })
    }

    private func closeCameraGesture(layout: CameraLayout) -> AnyGesture<DragGesture.Value> {
        AnyGesture(DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .updating($closingCameraGestureActive) { _, active, _ in active = true }
            .onChanged { drag in
                var transaction = Transaction()
                transaction.disablesAnimations = true
                transaction.tracksVelocity = true
                transaction.isContinuous = true
                withTransaction(transaction) {
                    _ = cameraPresentation.updateClosing(translation: drag.translation, travel: layout.dragTravel)
                }
            }
            .onEnded { drag in
                if let open = cameraPresentation.finishClosing(translation: drag.translation, predicted: drag.predictedEndTranslation) {
                    if !open { AppHaptics.tap() }
                    settleCamera(open: open)
                }
            })
    }

    private func cameraSurface(layout: CameraLayout) -> some View {
        let progress = cameraPresentation.progress
        return ZStack(alignment: .top) {
            Color.black
            if cameraPresentation.showsCamera {
                StickerCameraView(viewfinderTopInset: layout.viewfinderTopInset,
                                  frameBorderWidth: layout.collapsedHeight,
                                  isActive: cameraPresentation.isActive,
                                  dismissGesture: closeCameraGesture(layout: layout), onCapture: { data in
                    guard cameraPresentation.isActive && !processing else { return }
                    closeCamera()
                    process(data)
                }, onClose: closeCameraFromInteraction)
                .id(cameraPresentation.presentationID)
                // Keep the preview's layout stable while a single outer mask grows from the island.
                .frame(width: layout.width, height: layout.height)
                .transition(.identity)
            } else if cameraOpen {
                VStack(spacing: 12) {
                    DoodleIcon(systemName: "camera.fill", size: 28)
                    Text("继续下拉打开相机")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.top, layout.viewfinderTopInset + 24)
                .transition(.identity)
                .allowsHitTesting(false)
            }
        }
        .modifier(StickerCameraMorph(progress: progress,
                                     expandedSize: CGSize(width: layout.width, height: layout.height),
                                     collapsedSize: CGSize(width: layout.collapsedWidth, height: layout.collapsedHeight)))
        .transaction { if reduceMotion { $0.animation = nil } }
    }

    private func canvasElement(_ item: StickerCanvasItem, size: CGSize, cameraLayout: CameraLayout) -> some View {
        let moveItem: (CGSize) -> Void = { delta in move(item.id, by: delta, in: size) }
        let scaleItem: (Double) -> Void = { factor in
            finishTransform(item.id) { value in value.scale *= factor }
        }
        let rotateItem: (Double) -> Void = { degrees in
            finishTransform(item.id) { value in value.rotation += degrees }
        }
        return StickerCanvasElement(item: item, image: images[item.id], canvasSize: size,
            selected: selectedID == item.id, onSelect: { select(item.id) },
            onBeginMove: {
                finishCanvasPan()
                // Activation is visual only; save position when the completed drag lands.
                selectedID = item.id
                AppHaptics.impact()
            }, onMove: moveItem, onScale: scaleItem, onRotate: rotateItem, onEdit: { edit(item) },
            onTransformActivity: { active in
                if active {
                    finishCanvasPan()
                    transformingItemID = item.id
                    canvasNavigation.reset()
                    cancelCameraDragIfNeeded()
                } else if transformingItemID == item.id {
                    transformingItemID = nil
                }
            },
            browseGesture: browseCanvasGesture(in: size, cameraLayout: cameraLayout))
            .accessibilityAction(named: "向左移动") { moveItem(CGSize(width: -24, height: 0)) }
            .accessibilityAction(named: "向右移动") { moveItem(CGSize(width: 24, height: 0)) }
            .accessibilityAction(named: "向上移动") { moveItem(CGSize(width: 0, height: -24)) }
            .accessibilityAction(named: "向下移动") { moveItem(CGSize(width: 0, height: 24)) }
            .accessibilityAction(named: "删除") { remove(item.id) }
    }

    @ViewBuilder private func itemMenu(_ item: StickerCanvasItem) -> some View {
        if item.kind == .text {
            Button("编辑文字", doodleSystemImage: "pencil") { edit(item) }
        } else {
            Button("实线 · 4px") { setBorder(.solid, for: item.id) }
            Button("虚线 · 4px") { setBorder(.dashed, for: item.id) }
            Button("描边颜色", doodleSystemImage: "paintpalette") { editBorderColor(item) }
        }
        Button("移到最前", doodleSystemImage: "square.3.layers.3d.top.filled") {
            board.bringToFront(item.id)
            if board.error == nil { AppHaptics.selection() }
            else { AppHaptics.error() }
        }
        Button("删除", doodleSystemImage: "trash", role: .destructive) { remove(item.id) }
    }

    private func header(canvasSize: CGSize, cameraLayout: CameraLayout) -> some View {
        HStack {
            Text("Travel Journal").font(.system(size: 28, weight: .bold, design: .rounded))
                .lineLimit(1).minimumScaleFactor(0.65)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
                .gesture(browseCanvasGesture(in: canvasSize, cameraLayout: cameraLayout))
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("sticker-page-title")
                .accessibilityAction(named: "打开相机") { openCamera(layout: cameraLayout) }
            ZStack {
                if isAwayFromOrigin {
                    Button {
                        finishCanvasPan()
                        selectedID = nil
                        withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.9)) {
                            board.moveViewport(to: StickerCanvasViewport(x: 0, y: board.viewport.y))
                        }
                        if board.error == nil { AppHaptics.tap() }
                        else { AppHaptics.error() }
                    } label: {
                        DoodleIcon(systemName: "arrow.uturn.backward").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("回到画布起点").accessibilityIdentifier("sticker-reset-viewport")
                    .transition(.opacity)
                }
            }
            .frame(width: 44, height: 44)
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                DoodleIcon(systemName: "photo.badge.plus").frame(width: 44, height: 44)
            }
            .accessibilityLabel("从相册制作贴纸").accessibilityIdentifier("sticker-import-photo")
            .simultaneousGesture(TapGesture().onEnded { AppHaptics.tap() })
            Button { writeText(at: nextPosition) } label: {
                Text("Aa").font(JournalHandwriting.scaled(24, relativeTo: .title3))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("添加文字").accessibilityIdentifier("sticker-add-text")
        }
        .foregroundStyle(.black)
        .font(.system(size: 20, weight: .medium))
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        // Keep the initiating title gesture alive until it ends; tools remain separate siblings.
        .allowsHitTesting(!processing && (!cameraOpen || cameraPresentation.phase == .pulling))
    }

    @ViewBuilder private var selectionControls: some View {
        if let item = selectedItem {
            HStack(spacing: 8) {
                if item.kind == .image {
                    ForEach(StickerBorderStyle.allCases) { style in
                        Button { setBorder(style, for: item.id) } label: {
                            Text(style.localizedTitle).font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12).frame(height: 40)
                                .background(item.borderStyle == style ? Color.black.opacity(0.10) : Color.clear, in: Capsule())
                        }
                        .accessibilityIdentifier("sticker-border-\(style.rawValue)")
                        .accessibilityAddTraits(item.borderStyle == style ? .isSelected : [])
                    }
                    Text("4px").font(.caption).foregroundStyle(.secondary)
                    Button { editBorderColor(item) } label: {
                        Circle().fill(stickerTextColor(item.borderColorHex))
                            .frame(width: 26, height: 26)
                            .overlay(Circle().stroke(.black.opacity(0.25), lineWidth: 1))
                            .overlay {
                                DoodleIcon(systemName: "paintpalette", size: 13)
                                    .foregroundStyle(stickerColorForeground(item.borderColorHex))
                            }
                            .frame(width: 40, height: 40).contentShape(Rectangle())
                    }
                    .accessibilityLabel("描边颜色")
                    .accessibilityValue(item.borderColorHex)
                    .accessibilityIdentifier("sticker-border-color")
                } else {
                    Button { edit(item) } label: { Label("编辑文字", doodleSystemImage: "pencil", size: 15).font(.subheadline.weight(.medium)) }
                        .padding(.horizontal, 10).frame(height: 40)
                        .accessibilityIdentifier("sticker-edit-text")
                }
                Divider().frame(height: 22)
                Menu { itemMenu(item) } label: {
                    DoodleIcon(systemName: "ellipsis").frame(width: 40, height: 40)
                }
                .accessibilityLabel("更多操作").accessibilityIdentifier("sticker-item-menu")
                Button(role: .destructive) { remove(item.id) } label: {
                    DoodleIcon(systemName: "trash").frame(width: 40, height: 40)
                }.accessibilityLabel("删除贴纸或文字").accessibilityIdentifier("sticker-delete")
            }
            .buttonStyle(.plain).padding(6)
            .glassEffect(.regular, in: Capsule())
        }
    }

    private var nextPosition: CGPoint {
        let offset = Double(board.items.count % 5) * 0.035
        return CGPoint(x: board.viewport.x - canvasMotion.translation / max(1, canvasSize.width) + 0.44 + offset,
                       y: board.viewport.y + 0.40 + offset)
    }

    private var isAwayFromOrigin: Bool {
        abs(board.viewport.x) > 0.01
    }

    private func canvasOffset(in size: CGSize) -> CGSize {
        CGSize(width: -board.viewport.x * size.width,
               height: -board.viewport.y * size.height)
    }

    private func worldPosition(_ point: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: board.viewport.x + (point.x - canvasMotion.translation) / max(1, size.width),
                y: board.viewport.y + point.y / max(1, size.height))
    }

    private func panCanvas(by delta: CGSize, in size: CGSize) {
        finishCanvasPan()
        selectedID = nil
        board.moveViewport(to: StickerCanvasViewport(
            x: board.viewport.x - delta.width / max(1, size.width),
            y: board.viewport.y
        ))
    }

    private func finishCanvasPan() {
        let delta = canvasMotion.translation
        canvasMotion.stop()
        guard delta != 0, canvasSize.width > 0 else { canvasMotion.reset(); return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            board.moveViewport(to: StickerCanvasViewport(
                x: board.viewport.x - delta / canvasSize.width, y: board.viewport.y
            ))
            canvasMotion.reset()
        }
    }

    private func openCamera(layout: CameraLayout) {
        guard !cameraOpen, !processing, textEditor == nil else { return }
        finishCanvasPan()
        AppHaptics.tap()
        selectedID = nil
        frozenCameraLayout = layout
        settleCamera(open: true)
    }

    private func closeCamera() {
        guard cameraOpen else { return }
        settleCamera(open: false)
    }

    private func cancelCameraDragIfNeeded() {
        if let open = cameraPresentation.cancelDrag() { settleCamera(open: open) }
    }

    private func settleCamera(open: Bool) {
        var token = UUID()
        // A critically damped spring carries finger velocity into a soft landing,
        // without bouncing the frame past the island or the expanded viewfinder.
        let motion = Animation.spring(response: open ? 0.48 : 0.42, dampingFraction: 1, blendDuration: 0.12)
        withAnimation(reduceMotion ? nil : motion, completionCriteria: .removed) {
            token = cameraPresentation.settle(open: open)
        } completion: {
            if cameraPresentation.complete(token: token), !cameraPresentation.isMounted {
                frozenCameraLayout = nil
            }
        }
    }

    private func closeCameraFromInteraction() {
        guard cameraOpen else { return }
        AppHaptics.tap()
        closeCamera()
    }

    private func cancelProcessing() {
        processingID = UUID()
        processingTask?.cancel()
        processingTask = nil
        processing = false
        selectedPhoto = nil
    }

    private func process(_ data: Data) {
        cancelProcessing()
        let token = UUID()
        processingID = token
        processing = true
        processingTask = Task {
            do {
                let cutout = try await StickerSubjectProcessor.cutout(from: data)
                try Task.checkCancellation()
                selectedID = board.addSticker(cutout, at: nextPosition)
                if selectedID != nil { AppHaptics.success() }
                else { AppHaptics.error() }
            } catch is CancellationError { return }
            catch {
                guard !Task.isCancelled, processingID == token else { return }
                board.error = error.localizedDescription
                AppHaptics.error()
            }
            guard !Task.isCancelled, processingID == token else { return }
            processing = false
        }
    }

    private func loadImages() {
        let ids = Set(board.items.map(\.id))
        images = images.filter { ids.contains($0.key) }
        for item in board.items where item.kind == .image && images[item.id] == nil {
            if let url = board.imageURL(for: item) { images[item.id] = UIImage(contentsOfFile: url.path) }
        }
        if let selectedID, !ids.contains(selectedID) { self.selectedID = nil }
    }

    private func select(_ id: UUID, feedback: Bool = true) {
        finishCanvasPan()
        guard selectedID != id else { return }
        selectedID = id
        board.bringToFront(id)
        if feedback {
            if board.error == nil { AppHaptics.selection() }
            else { AppHaptics.error() }
        }
    }

    @discardableResult
    private func change(_ id: UUID, _ mutation: (inout StickerCanvasItem) -> Void) -> Bool {
        guard var item = board.items.first(where: { $0.id == id }) else { return false }
        mutation(&item)
        board.update(item)
        return board.error == nil
    }

    private func finishTransform(_ id: UUID, _ mutation: (inout StickerCanvasItem) -> Void) {
        if change(id, mutation) { AppHaptics.impact() }
        else { AppHaptics.error() }
    }

    private func setBorder(_ style: StickerBorderStyle, for id: UUID) {
        guard let item = board.items.first(where: { $0.id == id }), item.borderStyle != style else { return }
        if change(id, { $0.borderStyle = style }) { AppHaptics.selection() }
        else { AppHaptics.error() }
    }

    private func editBorderColor(_ item: StickerCanvasItem) {
        guard item.kind == .image else { return }
        select(item.id, feedback: false)
        AppHaptics.tap()
        borderColorEditor = item
    }

    private func move(_ id: UUID, by translation: CGSize, in size: CGSize) {
        finishTransform(id) { item in
            item.x += translation.width / max(1, size.width)
            item.y += translation.height / max(1, size.height)
        }
    }

    private func remove(_ id: UUID) {
        guard board.items.contains(where: { $0.id == id }) else { return }
        board.remove(id)
        if board.items.contains(where: { $0.id == id }) { AppHaptics.error() }
        else {
            undoNoticeID = UUID()
            AppHaptics.impact()
        }
        selectedID = nil
    }

    private func undoRemoval() {
        guard board.canUndoRemoval else { return }
        board.undoLastRemoval()
        if board.canUndoRemoval { AppHaptics.error() }
        else {
            undoNoticeID = nil
            AppHaptics.success()
        }
    }

    private func writeText(at position: CGPoint) {
        finishCanvasPan()
        AppHaptics.tap()
        textEditor = StickerTextDraft(position: position)
    }

    private func edit(_ item: StickerCanvasItem) {
        guard item.kind == .text else { select(item.id); return }
        select(item.id, feedback: false)
        AppHaptics.tap()
        textEditor = StickerTextDraft(itemID: item.id, position: CGPoint(x: item.x, y: item.y),
                                     text: item.text, color: item.textColor, fontSize: item.fontSize)
    }
}

/// Gesture bookkeeping does not invalidate the page on every finger sample.
@MainActor
private final class StickerCanvasGestureSession {
    private var navigation = StickerCanvasNavigation()
    private var cancelled = false
    var intent: StickerCanvasNavigation.Intent { cancelled ? .ignored : navigation.intent }
    func update(translation: CGSize) -> StickerCanvasNavigation.Intent {
        cancelled ? .ignored : navigation.update(translation: translation)
    }
    func cancel() { cancelled = true }
    func reset() { cancelled = false; navigation.reset() }
}

/// Only this lightweight transform observes live motion, not the individual stickers or toolbar.
private struct StickerCanvasTranslatedLayer<Content: View>: View {
    let offset: CGSize
    let motion: StickerCanvasMotion
    let size: CGSize
    @ViewBuilder var content: Content

    var body: some View {
        ZStack { content }
            .frame(width: size.width, height: size.height)
            .offset(x: offset.width + motion.translation, y: offset.height)
            .frame(width: size.width, height: size.height)
            .clipped()
    }
}

/// Reuse an oversized grid and translate it by one tile; panning never rebuilds its dots.
private struct StickerCanvasPaper: View {
    let offset: CGSize
    let motion: StickerCanvasMotion

    var body: some View {
        GeometryReader { geometry in
            Color(red: 0.96, green: 0.945, blue: 0.91)
            StickerCanvasDots()
                .equatable()
                .frame(width: geometry.size.width + 48, height: geometry.size.height + 48)
                .modifier(StickerPaperTranslation(offset: CGSize(
                    width: offset.width + motion.translation, height: offset.height
                )))
        }.clipped()
    }
}

private struct StickerPaperTranslation: GeometryEffect {
    var offset: CGSize

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(offset.width, offset.height) }
        set { offset = CGSize(width: newValue.first, height: newValue.second) }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(
            translationX: offset.width.truncatingRemainder(dividingBy: 24) - 24,
            y: offset.height.truncatingRemainder(dividingBy: 24) - 24
        ))
    }
}

private struct StickerCanvasDots: View, Equatable {
    var body: some View {
        Canvas { context, size in
            var dots = Path()
            for x in stride(from: 12.0, to: size.width, by: 24) {
                for y in stride(from: 12.0, to: size.height, by: 24) {
                    dots.addEllipse(in: CGRect(x: x, y: y, width: 1.5, height: 1.5))
                }
            }
            context.fill(dots, with: .color(.black.opacity(0.08)))
        }
    }
}

private struct StickerCanvasElement: View {
    let item: StickerCanvasItem
    let image: UIImage?
    let canvasSize: CGSize
    let selected: Bool
    let onSelect: () -> Void
    let onBeginMove: () -> Void
    let onMove: (CGSize) -> Void
    let onScale: (Double) -> Void
    let onRotate: (Double) -> Void
    let onEdit: () -> Void
    let onTransformActivity: (Bool) -> Void
    let browseGesture: AnyGesture<DragGesture.Value>
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var movement = Movement()
    @GestureState private var magnification = 1.0
    @GestureState private var rotation = Angle.zero
    @GestureState private var isMagnifying = false
    @GestureState private var isRotating = false

    private struct Movement {
        var active = false
        var translation = CGSize.zero
    }

    private var scale: Double { min(3, max(0.35, item.scale * magnification)) }

    private var interactiveContent: some View {
        StickerCanvasArtwork(item: item, image: image, canvasSize: canvasSize, scale: scale)
        .equatable()
        .shadow(color: .white.opacity(movement.active ? 0.95 : 0), radius: movement.active ? 10 : 0)
        .shadow(color: Color(red: 0.55, green: 0.82, blue: 1).opacity(movement.active ? 0.6 : 0), radius: movement.active ? 15 : 0)
        .scaleEffect(movement.active && !reduceMotion ? 1.035 : 1)
        .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.85), value: movement.active)
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .stroke(movement.active ? Color.white.opacity(0.8) : Color.black.opacity(selected ? 0.3 : 0),
                        style: StrokeStyle(lineWidth: 1, dash: movement.active ? [] : [4, 4]))
                .padding(-3)
        }
        .contentShape(Rectangle())
        .rotationEffect(.degrees(item.rotation) + rotation)
        .onTapGesture(count: 2, perform: onEdit)
        .onTapGesture(perform: onSelect)
        .simultaneousGesture(moveGesture.exclusively(before: browseGesture))
        .simultaneousGesture(MagnifyGesture()
            .updating($isMagnifying) { _, state, _ in state = true }
            .updating($magnification) { value, state, _ in state = value.magnification }
            .onChanged { _ in onSelect() }
            .onEnded { onScale($0.magnification) })
        .simultaneousGesture(RotateGesture()
            .updating($isRotating) { _, state, _ in state = true }
            .updating($rotation) { value, state, _ in state = value.rotation }
            .onChanged { _ in onSelect() }
            .onEnded { onRotate($0.rotation.degrees) })
        .onChange(of: movement.active) { _, active in
            if active { onBeginMove() }
        }
        .onChange(of: isMagnifying || isRotating) { _, active in onTransformActivity(active) }
    }

    private var moveGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.4, maximumDistance: 10)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("sticker-board")))
            .updating($movement) { value, state, transaction in
                // The first stage is only a possible press; activation requires its completion.
                if case .second(true, let drag) = value {
                    transaction.animation = nil
                    state.active = true
                    state.translation = drag?.translation ?? .zero
                }
            }
            .onEnded { value in
                if case .second(true, let drag?) = value, drag.translation != .zero {
                    onMove(drag.translation)
                }
            }
    }

    var body: some View {
        interactiveContent
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(item.kind == .text ? item.text : AppLocalization.text("照片贴纸"))
        .accessibilityValue(positionDescription)
        .accessibilityHint(item.kind == .text ? AppLocalization.text("长按后拖动调整位置，双击编辑文字；直接滑动浏览画布") : AppLocalization.text("长按后拖动调整位置，双指缩放和旋转；直接滑动浏览画布"))
        .accessibilityIdentifier("sticker-item-\(item.id)")
        .accessibilityAction { onSelect() }
        .position(x: canvasSize.width * item.x + movement.translation.width,
                  y: canvasSize.height * item.y + movement.translation.height)
        .zIndex(movement.active ? 1 : 0)
    }

    private var positionDescription: String {
        let position = AppLocalization.format("%lld, %lld · %@", Int64(item.x * 100), Int64(item.y * 100), item.borderStyle.localizedTitle)
        let value = item.kind == .image ? "\(position) · \(item.borderColorHex)" : position
        return movement.active ? "\(value) · \(AppLocalization.text("移动已激活"))" : value
    }
}

/// Expensive contour strokes and shadows are independent of camera/selection/pan state.
private struct StickerCanvasArtwork: View, Equatable {
    let item: StickerCanvasItem
    let image: UIImage?
    let canvasSize: CGSize
    let scale: Double

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.item == rhs.item && lhs.image === rhs.image &&
            lhs.canvasSize == rhs.canvasSize && lhs.scale == rhs.scale
    }

    private var imageSize: CGSize {
        let longest = min(200, canvasSize.width * 0.48) * scale
        let aspect = max(0.1, item.aspectRatio)
        return aspect >= 1 ? CGSize(width: longest, height: longest / aspect) : CGSize(width: longest * aspect, height: longest)
    }

    var body: some View {
        if item.kind == .image {
            imageContent.drawingGroup()
        } else {
            Text(item.text)
                .font(JournalHandwriting.fixed(item.fontSize * scale))
                .foregroundStyle(stickerTextColor(item.textColor))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: min(canvasSize.width * 0.84, 280 * scale))
                .padding(10)
        }
    }

    private var imageContent: some View {
        let dashed = item.borderStyle == .dashed
        let dash: [CGFloat] = dashed ? [8, 6] : []
        // Butt caps keep a real gap; round caps on the 8pt backing stroke join short dashes together.
        let stroke = StrokeStyle(lineWidth: 8, lineCap: dashed ? .butt : .round, lineJoin: .round, dash: dash)
        return ZStack {
            if let image {
                StickerSubjectOutline(contours: item.contours).stroke(stickerTextColor(item.borderColorHex), style: stroke)
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.65))
                Label("照片暂时无法读取", doodleSystemImage: "photo.badge.exclamationmark", size: 12)
                    .font(.caption).foregroundStyle(.secondary).padding(12)
            }
        }
        .frame(width: imageSize.width, height: imageSize.height)
        .padding(8)
        .shadow(color: .black.opacity(0.18), radius: 5, y: 3)
    }
}

struct StickerSubjectOutline: Shape {
    let contours: [[StickerOutlinePoint]]
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for contour in contours {
            guard let first = contour.first else { continue }
            path.move(to: CGPoint(x: rect.minX + first.x * rect.width, y: rect.minY + first.y * rect.height))
            for point in contour.dropFirst() {
                path.addLine(to: CGPoint(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height))
            }
            path.closeSubpath()
        }
        return path
    }
}

private struct StickerTextDraft: Identifiable {
    let id = UUID()
    var itemID: UUID? = nil
    var position: CGPoint
    var text = ""
    var color = "#1D1D1F"
    var fontSize = 28.0
}

private struct StickerTextEditor: View {
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @State private var text: String
    @State private var color: String
    @State private var fontSize: Double
    @State private var saveError: String?
    let draft: StickerTextDraft
    let onSave: (String, String, Double) -> String?
    private let colors = ["#1D1D1F", "#FFFFFF", "#BC534B", "#3E637A", "#63835E", "#AD823D"]

    init(draft: StickerTextDraft, onSave: @escaping (String, String, Double) -> String?) {
        self.draft = draft
        self.onSave = onSave
        _text = State(initialValue: draft.text)
        _color = State(initialValue: draft.color)
        _fontSize = State(initialValue: draft.fontSize)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("写点什么…", text: $text, axis: .vertical)
                        .lineLimit(3...7).font(JournalHandwriting.scaled(24, relativeTo: .title3))
                        .lineSpacing(4).focused($focused)
                        .accessibilityIdentifier("sticker-text-input")
                }
                Section("颜色") {
                    HStack(spacing: 14) {
                        ForEach(colors, id: \.self) { value in
                            Button {
                                guard color != value else { return }
                                color = value
                                AppHaptics.selection()
                            } label: {
                                Circle().fill(stickerTextColor(value))
                                    .frame(width: 32, height: 32)
                                    .overlay(Circle().stroke(.gray.opacity(0.4), lineWidth: 1))
                                    .padding(4)
                                    .overlay(Circle().stroke(color == value ? Color.primary : Color.clear, lineWidth: 2))
                            }.buttonStyle(.plain).accessibilityLabel(colorName(value))
                        }
                    }
                }
                Section("字号") {
                    Slider(value: $fontSize, in: 18...56, step: 1)
                    Text("\(Int(fontSize))").monospacedDigit().foregroundStyle(.secondary)
                }
            }
            .navigationTitle(draft.itemID == nil ? AppLocalization.text("添加文字") : AppLocalization.text("编辑文字"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { AppHaptics.tap(); dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveError = onSave(text.trimmingCharacters(in: .whitespacesAndNewlines), color, fontSize)
                        if saveError == nil { AppHaptics.success(); dismiss() }
                        else { AppHaptics.error() }
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("sticker-save-text")
                }
            }
            .onAppear { focused = true }
            .alert("文字未能保存", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("好") { AppHaptics.tap(); saveError = nil }
            } message: { Text(saveError ?? "") }
        }
        .tint(.black)
    }

    private func colorName(_ value: String) -> String {
        switch value {
        case "#FFFFFF": return AppLocalization.text("白色")
        case "#BC534B": return AppLocalization.text("砖红色")
        case "#3E637A": return AppLocalization.text("蓝色")
        case "#63835E": return AppLocalization.text("绿色")
        case "#AD823D": return AppLocalization.text("赭黄色")
        default: return AppLocalization.text("黑色")
        }
    }
}

private enum JournalHandwriting {
    private static let name = "Xiaolai"

    // Canvas sizes are saved with each item and already respond to pinch scaling.
    static func fixed(_ size: CGFloat) -> Font { .custom(name, fixedSize: size) }

    static func scaled(_ size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        .custom(name, size: size, relativeTo: style)
    }
}

func stickerTextColor(_ hex: String) -> Color {
    let rgb = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x1D1D1F
    return Color(red: Double((rgb >> 16) & 0xff) / 255, green: Double((rgb >> 8) & 0xff) / 255, blue: Double(rgb & 0xff) / 255)
}

private func stickerColorForeground(_ hex: String) -> Color {
    let rgb = UInt64(hex.dropFirst(), radix: 16) ?? 0xFFFFFF
    let brightness = Double((rgb >> 16) & 0xff) * 0.2126 + Double((rgb >> 8) & 0xff) * 0.7152 + Double(rgb & 0xff) * 0.0722
    return brightness < 145 ? .white : .black
}
