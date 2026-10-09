import AVFoundation
import Combine
import SwiftUI
import UIKit

/// A camera surface that can be animated out from underneath the top safe area.
struct StickerCameraView: View {
    let viewfinderTopInset: CGFloat
    let frameBorderWidth: CGFloat
    let isActive: Bool
    let dismissGesture: AnyGesture<DragGesture.Value>
    let onCapture: (Data) -> Void
    let onClose: () -> Void

    @State private var camera: StickerCameraController?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let camera {
                StickerCameraContent(viewfinderTopInset: viewfinderTopInset, frameBorderWidth: frameBorderWidth,
                                     isActive: isActive, dismissGesture: dismissGesture,
                                     onCapture: onCapture, camera: camera)
                    .transition(.opacity)
            } else {
                Color.black.contentShape(Rectangle()).gesture(dismissGesture)
                VStack(spacing: 12) {
                    ProgressView().tint(.white)
                    Text("正在打开相机…").font(.subheadline).foregroundStyle(.white)
                }
                .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("拍摄贴纸")
        .accessibilityAction(.escape, onClose)
        .accessibilityAction(named: "关闭相机", onClose)
        .accessibilityIdentifier("sticker-camera-panel")
        .task {
            guard camera == nil else { return }
            let prepared = await StickerCameraController.prepare()
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) { camera = prepared }
        }
    }
}

private struct StickerCameraContent: View {
    let viewfinderTopInset: CGFloat
    let frameBorderWidth: CGFloat
    let isActive: Bool
    let dismissGesture: AnyGesture<DragGesture.Value>
    let onCapture: (Data) -> Void

    @ObservedObject var camera: StickerCameraController
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: 0) {
                // The preview never extends behind the hardware island or the black frame.
                Color.clear.frame(height: viewfinderTopInset)
                    .contentShape(Rectangle()).gesture(dismissGesture)
                    .accessibilityHidden(true)
                viewfinder
                    .padding(.horizontal, frameBorderWidth)

                HStack {
                    Button {
                        AppHaptics.selection()
                        camera.flip()
                    } label: {
                        DoodleIcon(systemName: "arrow.triangle.2.circlepath.camera", size: 22)
                            .frame(width: 48, height: 48)
                            .background(.white.opacity(0.08), in: Circle())
                    }
                    .disabled(camera.phase != .ready || camera.isCapturing || !camera.canFlip)
                    .opacity(camera.canFlip ? 1 : 0.4)
                    .accessibilityLabel("切换前后摄像头")
                    .accessibilityIdentifier("sticker-camera-flip")

                    Spacer()
                    Button {
                        AppHaptics.cameraShutter()
                        camera.capture()
                    } label: {
                        ZStack {
                            Circle().strokeBorder(.white, lineWidth: 3)
                            Circle().fill(.white).padding(7)
                            if camera.isCapturing {
                                ProgressView().tint(.black)
                            }
                        }
                        .frame(width: 72, height: 72)
                        .contentShape(Circle())
                    }
                    .disabled(camera.phase != .ready || camera.isCapturing)
                    .opacity(camera.phase == .ready ? 1 : 0.4)
                    .accessibilityLabel("拍照制作贴纸")
                    .accessibilityIdentifier("sticker-camera-shutter")
                    Spacer()
                    Color.clear.frame(width: 48, height: 48).accessibilityHidden(true)
                }
                .padding(.horizontal, 28)
                .padding(.top, 20)
                .padding(.bottom, 22)
            }
        }
        .foregroundStyle(.white)
        .buttonStyle(.plain)
        .accessibilityElement(children: .contain)
        .onAppear {
            if isActive && !isPreviewFixture {
                AppHaptics.prepareCameraShutter()
                camera.appear(active: scenePhase == .active, onCapture: onCapture)
            }
        }
        .onDisappear { camera.disappear() }
        .onChange(of: isActive) { _, active in
            guard !isPreviewFixture else { return }
            if active {
                AppHaptics.prepareCameraShutter()
                camera.appear(active: scenePhase == .active, onCapture: onCapture)
            }
            else { camera.disappear() }
        }
        .onChange(of: scenePhase) { _, phase in
            if isActive && !isPreviewFixture {
                if phase == .active { AppHaptics.prepareCameraShutter() }
                camera.setActive(phase == .active)
            }
        }
    }

    private var isPreviewFixture: Bool {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--uitesting") && arguments.contains("--camera-preview-fixture")
        #else
        return false
        #endif
    }

    private var viewfinder: some View {
        GeometryReader { geometry in
            ZStack {
                ZStack {
                    if isPreviewFixture {
                        Image("template-fuji").resizable().scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .clipped()
                            .accessibilityLabel("相机取景测试画面")
                    } else {
                        StickerCameraPreview(controller: camera).accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
                .gesture(dismissGesture)
                // Status actions are siblings of the drag surface, never children of it.
                if !isPreviewFixture && camera.phase != .ready {
                    Color.black.opacity(0.72).allowsHitTesting(false)
                    status.padding(20)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("sticker-camera-viewfinder")
        }
    }

    @ViewBuilder private var status: some View {
        VStack(spacing: 12) {
            if camera.phase == .starting {
                ProgressView().tint(.white).allowsHitTesting(false)
                Text("正在打开相机…").font(.subheadline).allowsHitTesting(false)
            } else {
                DoodleIcon(systemName: camera.phase == .denied ? "camera.badge.ellipsis" : "camera", size: 28)
                    .allowsHitTesting(false)
                Text(camera.phase.message)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .allowsHitTesting(false)
                if camera.phase == .denied {
                    Button("去设置允许相机") {
                        AppHaptics.tap()
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                } else if camera.phase.canRetry {
                    Button("重试") {
                        AppHaptics.tap()
                        camera.retry()
                    }
                        .buttonStyle(.bordered)
                        .tint(.white)
                }
            }
        }
    }
}

enum StickerCameraPhase: Equatable {
    case starting, ready, denied, restricted, unavailable, interrupted
    case failed(String)

    var message: String {
        switch self {
        case .starting, .ready: return ""
        case .denied: return AppLocalization.text("允许使用相机后，就可以拍摄照片制作贴纸。")
        case .restricted: return AppLocalization.text("这台设备限制了相机使用，请检查屏幕使用时间或设备管理设置。")
        case .unavailable:
            #if targetEnvironment(simulator)
            return AppLocalization.text("模拟器无法使用相机，请在 iPhone 上拍摄，或返回后从相册添加。")
            #else
            return AppLocalization.text("当前设备没有可用的相机，可以返回后从相册添加照片。")
            #endif
        case .interrupted: return AppLocalization.text("相机暂时被占用，稍后可以重试。")
        case .failed(let message): return message
        }
    }

    var canRetry: Bool {
        switch self {
        case .failed, .interrupted: return true
        default: return false
        }
    }
}

/// Session state is confined to sessionQueue; UI state and callbacks are delivered on main.
final class StickerCameraController: NSObject, ObservableObject {
    @Published private(set) var phase: StickerCameraPhase = .starting
    @Published private(set) var isCapturing = false
    @Published private(set) var canFlip = false
    @Published private(set) var device: AVCaptureDevice?

    let session = AVCaptureSession()
    // Serialise camera handoffs too: a quick reopen must not race the old camera's stop.
    private static let sharedSessionQueue = DispatchQueue(label: "com.xiangchengjin.roam.sticker-camera", qos: .userInitiated)

    /// Capture session/output initialization can also block, before startRunning is called.
    /// Prepare them away from the display thread, serialized with previous camera teardown.
    static func prepare() async -> StickerCameraController {
        await withCheckedContinuation { continuation in
            sharedSessionQueue.async {
                continuation.resume(returning: StickerCameraController())
            }
        }
    }

    private let sessionQueue: DispatchQueue
    private let output = AVCapturePhotoOutput()
    private var input: AVCaptureDeviceInput?
    private var configured = false
    private var wantsRunning = false
    private var sessionRetired = false
    private var captureAngle: CGFloat = 90
    private var photoDelegate: StickerPhotoCaptureDelegate?
    private var observations: [NSObjectProtocol] = []

    // Accessed by the view and authorization callback on main only.
    private var visible = false
    private var active = false
    private var requestingPermission = false
    private var onCapture: ((Data) -> Void)?
    private var retired = false
    private weak var previewSurface: StickerCameraPreviewSurface?

    var acceptsPreviewUpdates: Bool { visible && active && !retired }

    func registerPreview(_ surface: StickerCameraPreviewSurface) {
        let isNew = previewSurface !== surface
        previewSurface = surface
        if isNew && acceptsPreviewUpdates { reconcile() }
    }

    init(sessionQueue: DispatchQueue = StickerCameraController.sharedSessionQueue) {
        self.sessionQueue = sessionQueue
        super.init()
        let center = NotificationCenter.default
        observations.append(center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) { [weak self] _ in
            self?.setPhase(.interrupted)
        })
        observations.append(center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil) { [weak self] _ in
            self?.sessionQueue.async { [weak self] in self?.startIfNeeded() }
        })
        observations.append(center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak self] _ in
            self?.setPhase(.failed(AppLocalization.text("相机暂时无法启动，请重试。")))
        })
    }

    deinit {
        observations.forEach { NotificationCenter.default.removeObserver($0) }
        // A disappearance normally stops the session first. Retain it until this final stop finishes.
        let captureSession = session
        let captureOutput = output
        let captureInput = input
        let captureDelegate = photoDelegate
        sessionQueue.async {
            if captureSession.isRunning { captureSession.stopRunning() }
            // An early cancelled preparation has not attached its output/input yet.
            // Their final release belongs on the camera queue as well.
            withExtendedLifetime((captureSession, captureOutput, captureInput, captureDelegate)) {}
        }
    }

    func appear(active: Bool, onCapture: @escaping (Data) -> Void) {
        guard !retired else { return }
        visible = true
        self.active = active
        self.onCapture = onCapture
        reconcile()
    }

    func disappear() {
        visible = false
        onCapture = nil
        previewSurface?.suspendRotationUpdates()
        reconcile()
    }

    func setActive(_ active: Bool) {
        self.active = active
        if !active { previewSurface?.suspendRotationUpdates() }
        reconcile()
    }

    func retry() { reconcile() }

    /// Keep the outgoing view alive while stopping. Detaching a live preview on main can
    /// wait for AVFoundation's session graph lock and freeze the entire interface.
    func retirePreview(completion: @escaping () -> Void) {
        retired = true
        visible = false
        onCapture = nil
        previewSurface?.suspendRotationUpdates()
        sessionQueue.async { [self] in
            sessionRetired = true
            wantsRunning = false
            if session.isRunning { session.stopRunning() }
            DispatchQueue.main.async { [self] in
                // Layer/view mutations stay on main, after all session work has finished.
                withExtendedLifetime(self) { completion() }
            }
        }
    }

    private func reconcile() {
        guard !retired else { return }
        guard visible && active else {
            sessionQueue.async { [weak self] in
                guard let self else { return }
                self.wantsRunning = false
                if self.session.isRunning { self.session.stopRunning() }
            }
            return
        }
        // Attach the empty preview before configuring/starting the session on its queue.
        guard previewSurface != nil else { return }
        #if targetEnvironment(simulator)
        phase = .unavailable
        return
        #else
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            phase = .starting
            sessionQueue.async { [weak self] in
                guard let self else { return }
                self.wantsRunning = true
                self.startIfNeeded()
            }
        case .notDetermined:
            guard !requestingPermission else { return }
            requestingPermission = true
            AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.requestingPermission = false
                    self?.reconcile()
                }
            }
        case .denied: phase = .denied
        case .restricted: phase = .restricted
        @unknown default: phase = .failed(AppLocalization.text("无法读取相机权限，请重试。"))
        }
        #endif
    }

    private func startIfNeeded() {
        guard wantsRunning && !sessionRetired else { return }
        do {
            if !configured { try configure() }
            guard configured else { return }
            if !session.isRunning { session.startRunning() }
            if let input { publishDevice(input.device) }
            if session.isInterrupted { setPhase(.interrupted) }
            else { setPhase(session.isRunning ? .ready : .failed(AppLocalization.text("相机暂时无法启动，请重试。"))) }
        } catch {
            setPhase(.failed(AppLocalization.text("无法打开相机，请重试。")))
        }
    }

    private func configure() throws {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            ?? AVCaptureDevice.default(for: .video) else {
            setPhase(.unavailable)
            return
        }
        let newInput = try AVCaptureDeviceInput(device: camera)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard session.canAddInput(newInput) else { throw StickerCameraError.configuration }
        session.addInput(newInput)
        guard session.canAddOutput(output) else {
            session.removeInput(newInput)
            throw StickerCameraError.configuration
        }
        session.addOutput(output)
        input = newInput
        configured = true
    }

    func flip() {
        sessionQueue.async { [weak self] in
            guard let self, !self.sessionRetired, self.wantsRunning, self.session.isRunning, !self.session.isInterrupted,
                  self.photoDelegate == nil, let previous = self.input else { return }
            let position: AVCaptureDevice.Position = previous.device.position == .front ? .back : .front
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
                  let replacement = try? AVCaptureDeviceInput(device: camera) else { return }
            self.session.beginConfiguration()
            self.session.removeInput(previous)
            if self.session.canAddInput(replacement) {
                self.session.addInput(replacement)
                self.input = replacement
            } else {
                self.session.addInput(previous)
            }
            self.session.commitConfiguration()
            self.publishDevice(self.input?.device ?? previous.device)
        }
    }

    func updateCaptureAngle(_ angle: CGFloat) {
        sessionQueue.async { [weak self] in self?.captureAngle = angle }
    }

    func capture() {
        sessionQueue.async { [weak self] in
            guard let self, !self.sessionRetired, self.wantsRunning, self.session.isRunning, !self.session.isInterrupted,
                  self.photoDelegate == nil, let connection = self.output.connection(with: .video) else { return }
            if connection.isVideoRotationAngleSupported(self.captureAngle) {
                connection.videoRotationAngle = self.captureAngle
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = self.input?.device.position == .front
            }
            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            settings.flashMode = .off
            settings.photoQualityPrioritization = .balanced
            let delegate = StickerPhotoCaptureDelegate { [weak self] data in
                self?.sessionQueue.async { [weak self] in
                    guard let self else { return }
                    self.photoDelegate = nil
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        self.isCapturing = false
                        guard self.visible && self.active else { return }
                        if let data { self.onCapture?(data) }
                        else {
                            self.phase = .failed(AppLocalization.text("这次没能拍下照片，请重试。"))
                            AppHaptics.error()
                        }
                    }
                }
            }
            self.photoDelegate = delegate
            DispatchQueue.main.async { [weak self] in self?.isCapturing = true }
            self.output.capturePhoto(with: settings, delegate: delegate)
        }
    }

    private func publishDevice(_ camera: AVCaptureDevice) {
        let otherPosition: AVCaptureDevice.Position = camera.position == .front ? .back : .front
        let hasOtherCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: otherPosition) != nil
        DispatchQueue.main.async { [weak self] in
            guard let self, self.acceptsPreviewUpdates else { return }
            self.device = camera
            self.canFlip = hasOtherCamera
        }
    }

    private func setPhase(_ phase: StickerCameraPhase) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.acceptsPreviewUpdates else { return }
            self.phase = phase
        }
    }
}

private enum StickerCameraError: Error { case configuration }

private final class StickerPhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private var data: Data?
    private let completion: (Data?) -> Void

    init(completion: @escaping (Data?) -> Void) { self.completion = completion }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if error == nil { data = photo.fileDataRepresentation() }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        completion(error == nil ? data : nil)
    }
}

private struct StickerCameraPreview: UIViewRepresentable {
    @ObservedObject var controller: StickerCameraController

    func makeUIView(context: Context) -> StickerCameraPreviewSurface {
        let view = StickerCameraPreviewSurface()
        view.connect(controller)
        return view
    }

    func updateUIView(_ uiView: StickerCameraPreviewSurface, context: Context) { uiView.connect(controller) }

    static func dismantleUIView(_ uiView: StickerCameraPreviewSurface, coordinator: ()) { uiView.disconnect() }
}

final class StickerCameraPreviewSurface: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    private var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    private var rotation: AVCaptureDevice.RotationCoordinator?
    private var previewRotation: NSKeyValueObservation?
    private var captureRotation: NSKeyValueObservation?
    private var deviceID: String?
    private var controller: StickerCameraController?
    private var isDisconnecting = false
    private var lastPreviewAngle: CGFloat?

    func connect(_ controller: StickerCameraController) {
        guard !isDisconnecting else { return }
        if self.controller == nil {
            self.controller = controller
            previewLayer.session = controller.session
            previewLayer.videoGravity = .resizeAspectFill
            controller.registerPreview(self)
        }
        guard self.controller === controller else { return }
        guard controller.acceptsPreviewUpdates, controller.phase == .ready else { return }
        guard let device = controller.device else { return }
        if deviceID != device.uniqueID {
            suspendRotationUpdates()
            deviceID = device.uniqueID
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
            rotation = coordinator
            previewRotation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak self] coordinator, _ in
                self?.setPreviewAngle(coordinator.videoRotationAngleForHorizonLevelPreview)
            }
            captureRotation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.initial, .new]) { [weak controller] coordinator, _ in
                controller?.updateCaptureAngle(coordinator.videoRotationAngleForHorizonLevelCapture)
            }
            if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = device.position == .front
            }
        }
    }

    private func setPreviewAngle(_ angle: CGFloat) {
        guard !isDisconnecting, controller?.acceptsPreviewUpdates == true, controller?.phase == .ready,
              lastPreviewAngle != angle else { return }
        guard let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
        lastPreviewAngle = angle
    }

    func suspendRotationUpdates() {
        previewRotation = nil
        captureRotation = nil
        rotation = nil
        deviceID = nil
        lastPreviewAngle = nil
    }

    func disconnect() {
        guard !isDisconnecting else { return }
        isDisconnecting = true
        suspendRotationUpdates()
        guard let controller else { return }
        controller.retirePreview { [self] in
            previewLayer.session = nil
            self.controller = nil
        }
    }
}
