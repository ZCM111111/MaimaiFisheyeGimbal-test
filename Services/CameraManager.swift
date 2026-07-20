// Services/CameraManager.swift
import AVFoundation
import CoreVideo

/// 管理 AVCaptureSession，输出 BGRA 像素缓冲
final class CameraManager: NSObject, ObservableObject {
    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "camera.queue", qos: .userInteractive)

    /// 每当有新帧时调用
    var onFrame: ((CVPixelBuffer) -> Void)?

    /// 当前分辨率配置
    enum Resolution {
        case p1080_60, p4k_60

        var preset: AVCaptureSession.Preset {
            switch self {
            case .p1080_60: return .hd1920x1080
            case .p4k_60:   return .hd4K3840x2160
            }
        }

        var fps: Int32 { 60 }
    }

    private var resolution: Resolution

    init(resolution: Resolution = .p1080_60) {
        self.resolution = resolution
        super.init()
    }

    /// 请求权限并启动
    func start() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        guard granted else {
            print("[CameraManager] 相机权限被拒绝")
            return
        }
        configure()
        session.startRunning()
    }

    func stop() {
        session.stopRunning()
    }

    func switchResolution(_ res: Resolution) {
        session.stopRunning()
        resolution = res
        configure()
        session.startRunning()
    }

    // MARK: - Private

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = resolution.preset

        session.inputs.forEach { session.removeInput($0) }

        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: .back
        ) else {
            print("[CameraManager] 找不到后置摄像头")
            session.commitConfiguration()
            return
        }

        do {
            try device.lockForConfiguration()
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: resolution.fps)
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: resolution.fps)
            device.unlockForConfiguration()
        } catch {
            print("[CameraManager] 配置帧率失败: \(error)")
        }

        guard let input = try? AVCaptureDeviceInput(device: device) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.setSampleBufferDelegate(self, queue: queue)
        session.addOutput(output)

        if let connection = output.connection(with: .video) {
            connection.videoRotationAngle = 90
        }

        session.commitConfiguration()
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(pixelBuffer)
    }
}
