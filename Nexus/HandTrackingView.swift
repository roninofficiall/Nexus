import SwiftUI
import Vision
import AVFoundation

// MARK: - Main View

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

    private let tracker: HandTracker

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

            if let connection = videoOutput.connection(with: .video),
               connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }

            previewLayer.session = session

            videoOutput.setSampleBufferDelegate(
                tracker,
                queue: tracker.queue
            )

            session.commitConfiguration()

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.startRunning()
            }

        } catch {
            session.commitConfiguration()
            print("NEXUS CAMERA ERROR:", error)
        }
    }

    func stop() {
        if session.isRunning {
            session.stopRunning()
        }
    }
}

// MARK: - Landmark Model

struct HandLandmarks {

    let wrist: CGPoint

    let thumbCMC: CGPoint
    let thumbMP: CGPoint
    let thumbIP: CGPoint
    let thumbTip: CGPoint

    let indexMCP: CGPoint
    let indexPIP: CGPoint
    let indexDIP: CGPoint
    let indexTip: CGPoint

    let middleMCP: CGPoint
    let middlePIP: CGPoint
    let middleDIP: CGPoint
    let middleTip: CGPoint

    let ringMCP: CGPoint
    let ringPIP: CGPoint
    let ringDIP: CGPoint
    let ringTip: CGPoint

    let littleMCP: CGPoint
    let littlePIP: CGPoint
    let littleDIP: CGPoint
    let littleTip: CGPoint
}

// MARK: - Hand Tracker

final class HandTracker: NSObject,
                         ObservableObject,
                         AVCaptureVideoDataOutputSampleBufferDelegate {

    struct TrackedHand: Identifiable {

        let id = UUID()
        let landmarks: HandLandmarks
    }

    @Published private(set) var hands: [TrackedHand] = []

    let queue = DispatchQueue(
        label: "nexus.handtracking",
        qos: .userInitiated
    )

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

            guard let observations = handRequest.results else {
                publish([])
                return
            }

            var detectedHands: [TrackedHand] = []

            for observation in observations {

                guard let landmarks =
                        makeLandmarks(from: observation)
                else {
                    continue
                }

                detectedHands.append(
                    TrackedHand(
                        landmarks: landmarks
                    )
                )
            }

            publish(detectedHands)

        } catch {

            publish([])
        }
    }

    private func makeLandmarks(
        from observation: VNHumanHandPoseObservation
    ) -> HandLandmarks? {

        do {

            let points = try observation.recognizedPoints(.all)

            func point(
                _ name: VNHumanHandPoseObservation.JointName
            ) -> CGPoint? {

                guard let p = points[name],
                      p.confidence > 0.35
                else {
                    return nil
                }

                return CGPoint(
                    x: p.location.x,
                    y: 1.0 - p.location.y
                )
            }

            guard
                let wrist = point(.wrist),

                let thumbCMC = point(.thumbCMC),
                let thumbMP = point(.thumbMP),
                let thumbIP = point(.thumbIP),
                let thumbTip = point(.thumbTip),

                let indexMCP = point(.indexMCP),
                let indexPIP = point(.indexPIP),
                let indexDIP = point(.indexDIP),
                let indexTip = point(.indexTip),

                let middleMCP = point(.middleMCP),
                let middlePIP = point(.middlePIP),
                let middleDIP = point(.middleDIP),
                let middleTip = point(.middleTip),

                let ringMCP = point(.ringMCP),
                let ringPIP = point(.ringPIP),
                let ringDIP = point(.ringDIP),
                let ringTip = point(.ringTip),

                let littleMCP = point(.littleMCP),
                let littlePIP = point(.littlePIP),
                let littleDIP = point(.littleDIP),
                let littleTip = point(.littleTip)

            else {
                return nil
            }

            return HandLandmarks(
                wrist: wrist,

                thumbCMC: thumbCMC,
                thumbMP: thumbMP,
                thumbIP: thumbIP,
                thumbTip: thumbTip,

                indexMCP: indexMCP,
                indexPIP: indexPIP,
                indexDIP: indexDIP,
                indexTip: indexTip,

                middleMCP: middleMCP,
                middlePIP: middlePIP,
                middleDIP: middleDIP,
                middleTip: middleTip,

                ringMCP: ringMCP,
                ringPIP: ringPIP,
                ringDIP: ringDIP,
                ringTip: ringTip,

                littleMCP: littleMCP,
                littlePIP: littlePIP,
                littleDIP: littleDIP,
                littleTip: littleTip
            )

        } catch {
            return nil
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

// MARK: - Skeleton Overlay

struct HandSkeletonOverlay: View {

    let hands: [HandTracker.TrackedHand]
    let size: CGSize

    var body: some View {

        Canvas { context, canvasSize in

            for hand in hands {

                let p = hand.landmarks

                let connections: [(CGPoint, CGPoint)] = [

                    // Wrist → thumb
                    (p.wrist, p.thumbCMC),
                    (p.thumbCMC, p.thumbMP),
                    (p.thumbMP, p.thumbIP),
                    (p.thumbIP, p.thumbTip),

                    // Wrist → index
                    (p.wrist, p.indexMCP),
                    (p.indexMCP, p.indexPIP),
                    (p.indexPIP, p.indexDIP),
                    (p.indexDIP, p.indexTip),

                    // Wrist → middle
                    (p.wrist, p.middleMCP),
                    (p.middleMCP, p.middlePIP),
                    (p.middlePIP, p.middleDIP),
                    (p.middleDIP, p.middleTip),

                    // Wrist → ring
                    (p.wrist, p.ringMCP),
                    (p.ringMCP, p.ringPIP),
                    (p.ringPIP, p.ringDIP),
                    (p.ringDIP, p.ringTip),

                    // Wrist → little
                    (p.wrist, p.littleMCP),
                    (p.littleMCP, p.littlePIP),
                    (p.littlePIP, p.littleDIP),
                    (p.littleDIP, p.littleTip),

                    // Palm
                    (p.indexMCP, p.middleMCP),
                    (p.middleMCP, p.ringMCP),
                    (p.ringMCP, p.littleMCP)
                ]

                for (a, b) in connections {

                    let start = CGPoint(
                        x: a.x * canvasSize.width,
                        y: a.y * canvasSize.height
                    )

                    let end = CGPoint(
                        x: b.x * canvasSize.width,
                        y: b.y * canvasSize.height
                    )

                    var path = Path()

                    path.move(to: start)
                    path.addLine(to: end)

                    context.stroke(
                        path,
                        with: .color(.cyan),
                        lineWidth: 2
                    )
                }

                let allPoints: [CGPoint] = [
                    p.wrist,

                    p.thumbCMC,
                    p.thumbMP,
                    p.thumbIP,
                    p.thumbTip,

                    p.indexMCP,
                    p.indexPIP,
                    p.indexDIP,
                    p.indexTip,

                    p.middleMCP,
                    p.middlePIP,
                    p.middleDIP,
                    p.middleTip,

                    p.ringMCP,
                    p.ringPIP,
                    p.ringDIP,
                    p.ringTip,

                    p.littleMCP,
                    p.littlePIP,
                    p.littleDIP,
                    p.littleTip
                ]

                for point in allPoints {

                    let position = CGPoint(
                        x: point.x * canvasSize.width,
                        y: point.y * canvasSize.height
                    )

                    let circle = Path(
                        ellipseIn: CGRect(
                            x: position.x - 4,
                            y: position.y - 4,
                            width: 8,
                            height: 8
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