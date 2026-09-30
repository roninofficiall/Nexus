import SwiftUI
import Vision
import AVFoundation

struct HandTrackingView: View {

    @StateObject private var tracker = HandTracker()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                CameraTrackingView(tracker: tracker)
                    .ignoresSafeArea()

                HandSkeletonOverlay(
                    hands: tracker.hands,
                    size: geometry.size
                )
                .allowsHitTesting(false)
            }
        }
        .onDisappear {
            tracker.stop()
        }
    }
}

// MARK: - Camera

struct CameraTrackingView: UIViewRepresentable {

    let tracker: HandTracker

    func makeUIView(context: Context) -> CameraTrackingPreview {
        let view = CameraTrackingPreview(tracker: tracker)
        view.start()
        return view
    }

    func updateUIView(
        _ uiView: CameraTrackingPreview,
        context: Context
    ) {}
}

final class CameraTrackingPreview: UIView {

    private let session = AVCaptureSession()
    private let previewLayer = AVCaptureVideoPreviewLayer()

    private let videoOutput = AVCaptureVideoDataOutput()

    private weak var tracker: HandTracker?

    init(tracker: HandTracker) {
        self.tracker = tracker
        super.init(frame: .zero)

        backgroundColor = .black

        previewLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        previewLayer.frame = bounds

        if let connection = previewLayer.connection,
           connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
    }

    func start() {

        guard !session.isRunning else {
            return
        }

        session.beginConfiguration()

        session.sessionPreset = .vga640x480

        guard let camera = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ) else {
            session.commitConfiguration()
            return
        }

        do {

            let input = try AVCaptureDeviceInput(device: camera)

            guard session.canAddInput(input) else {
                session.commitConfiguration()
                return
            }

            session.addInput(input)

            videoOutput.alwaysDiscardsLateVideoFrames = true

            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String:
                    kCVPixelFormatType_32BGRA
            ]

            guard session.canAddOutput(videoOutput) else {
                session.commitConfiguration()
                return
            }

            session.addOutput(videoOutput)

            if let connection = videoOutput.connection(
                with: .video
            ),
            connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }

            previewLayer.session = session

            videoOutput.setSampleBufferDelegate(
                tracker,
                queue: tracker.queue
            )

            session.commitConfiguration()

            DispatchQueue.global(
                qos: .userInitiated
            ).async { [weak self] in
                self?.session.startRunning()
            }

        } catch {

            session.commitConfiguration()

            print("NEXUS CAMERA ERROR:", error)
        }
    }

    func stop() {
        session.stopRunning()
    }
}

// MARK: - Hand Tracking

final class HandTracker: NSObject,
                          ObservableObject,
                          AVCaptureVideoDataOutputSampleBufferDelegate {

    struct TrackedHand: Identifiable {
        let id = UUID()
        let points: [CGPoint]
    }

    @Published private(set) var hands: [TrackedHand] = []

    let queue = DispatchQueue(
        label: "nexus.handtracking",
        qos: .userInitiated
    )

    // Jeden request — używamy go ponownie.
    private let handRequest = VNDetectHumanHandPoseRequest()

    private let sequenceHandler = VNSequenceRequestHandler()

    private var lastDetectionTime: CFTimeInterval = 0

    override init() {
        super.init()

        handRequest.maximumHandCount = 2
    }

    func stop() {

        DispatchQueue.main.async { [weak self] in
            self?.hands = []
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {

        let now = CACurrentMediaTime()

        // Vision maksymalnie ~30 analiz/s.
        guard now - lastDetectionTime >= 1.0 / 30.0 else {
            return
        }

        lastDetectionTime = now

        guard let pixelBuffer =
                CMSampleBufferGetImageBuffer(sampleBuffer)
        else {
            return
        }

        do {

            try sequenceHandler.perform(
                [handRequest],
                on: pixelBuffer,
                orientation: .right
            )

            guard let observations =
                    handRequest.results
            else {
                publish([])
                return
            }

            var detectedHands: [TrackedHand] = []

            for observation in observations {

                let recognized =
                    try observation.recognizedPoints(.all)

                let points = recognized.values
                    .filter {
                        $0.confidence > 0.35
                    }
                    .map {
                        CGPoint(
                            x: $0.location.x,
                            y: 1.0 - $0.location.y
                        )
                    }

                if !points.isEmpty {
                    detectedHands.append(
                        TrackedHand(points: points)
                    )
                }
            }

            publish(detectedHands)

        } catch {

            publish([])
        }
    }

    private func publish(
        _ newHands: [TrackedHand]
    ) {

        DispatchQueue.main.async { [weak self] in
            self?.hands = newHands
        }
    }
}

// MARK: - Skeleton

struct HandSkeletonOverlay: View {

    let hands: [HandTracker.TrackedHand]
    let size: CGSize

    var body: some View {

        Canvas { context, canvasSize in

            for hand in hands {

                for point in hand.points {

                    let position = CGPoint(
                        x: point.x * canvasSize.width,
                        y: point.y * canvasSize.height
                    )

                    let circle = Path(
                        ellipseIn: CGRect(
                            x: position.x - 5,
                            y: position.y - 5,
                            width: 10,
                            height: 10
                        )
                    )

                    context.fill(
                        circle,
                        with: .color(.cyan)
                    )
                }
            }
        }
    }
}