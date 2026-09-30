import SwiftUI
import AVFoundation

struct CameraView: UIViewRepresentable {

    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()

        view.startCamera()

        return view
    }

    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
    }
}

final class CameraPreviewView: UIView {

    private let session = AVCaptureSession()
    private let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)

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

    func startCamera() {

        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {

            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in

                guard granted else { return }

                DispatchQueue.main.async {
                    self?.configureCamera()
                }
            }

            return
        }

        configureCamera()
    }

    private func configureCamera() {

        guard !session.isRunning else { return }

        session.beginConfiguration()

        session.sessionPreset = .high

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

            if session.canAddInput(input) {
                session.addInput(input)
            }

            if session.canAddOutput(AVCaptureVideoDataOutput()) {
                let output = AVCaptureVideoDataOutput()
                session.addOutput(output)
            }

            previewLayer.session = session

            session.commitConfiguration()

            DispatchQueue.global(qos: .userInitiated).async {
                self.session.startRunning()
            }

        } catch {

            session.commitConfiguration()

            print("NEXUS CAMERA ERROR:", error)
        }
    }
}