import SwiftUI
import Vision
import AVFoundation

struct HandTrackingView: View {

    @StateObject private var tracker = HandTracker()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                CameraViewWithFrames(tracker: tracker)
                    .ignoresSafeArea()

                HandOverlay(
                    points: tracker.points,
                    size: geometry.size
                )
                .allowsHitTesting(false)
            }
        }
        .onAppear {
            tracker.start()
        }
        .onDisappear {
            tracker.stop()
        }
    }
}

struct CameraViewWithFrames: UIViewRepresentable {

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

final class HandTracker: NSObject, ObservableObject,
                          AVCaptureVideoDataOutputSampleBufferDelegate {

    @Published private(set) var points: [CGPoint] = []

    let queue = DispatchQueue(
        label: "nexus.handtracking",
        qos: .userInitiated
    )

    private let sequenceHandler = VNSequenceRequestHandler()

    private var lastDetectionTime: CFTimeInterval = 0

    func start() {}

    func stop() {
        DispatchQueue.main.async { [weak self] in
            self?.points = []
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {

        let now = CACurrentMediaTime()

        // Ograniczamy koszt Vision.
        // Kamera może działać szybciej niż detekcja.
        guard now - lastDetectionTime >= 1.0 / 30.0 else {
            return
        }

        lastDetectionTime = now

        guard let pixelBuffer =
                CMSampleBufferGetImageBuffer(sampleBuffer)
        else {
            return
        }

        let request = VNDetectHumanHandPoseRequest()

        request.maximumHandCount = 2

        do {

            try sequenceHandler.perform(
                [request],
                on: pixelBuffer,
                orientation: .right
            )

            guard let observation =
                    request.results?.first
            else {
                updatePoints([])
                return
            }

            let recognizedPoints =
                try observation.recognizedPoints(.all)

            let validPoints = recognizedPoints.values
                .filter { $0.confidence > 0.35 }
                .map {
                    CGPoint(
                        x: $0.location.x,
                        y: 1.0 - $0.location.y
                    )
                }

            updatePoints(validPoints)

        } catch {

            updatePoints([])
        }
    }

    private func updatePoints(_ newPoints: [CGPoint]) {

        DispatchQueue.main.async { [weak self] in
            self?.points = newPoints
        }
    }
}

struct HandOverlay: View {

    let points: [CGPoint]
    let size: CGSize

    var body: some View {

        Canvas { context, canvasSize in

            for point in points {

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