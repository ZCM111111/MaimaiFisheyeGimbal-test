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

    /// 帧率统计
    private var frameCount: Int64 = 0
    private var lastFPSReportTime = Date()
    private var droppedFrames: Int = 0

    /// 当前分辨率配置
    enum Resolution: String {
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
        Logger.info("CameraManager 初始化 (默认分辨率=\(resolution.rawValue))")
    }

    /// 请求权限并启动
    func start() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        Logger.info("当前相机权限状态: \(status.rawValue) (0=未决定 1=受限 2=拒绝 3=已授权)")

        let granted = await AVCaptureDevice.requestAccess(for: .video)
        guard granted else {
            Logger.error("""
                相机权限被拒绝 — 无法启动摄像头预览。
                解决: 设置 → 隐私与安全性 → 相机 → 启用 MaimaiFisheyeGimbal
                """)
            return
        }

        configure()
        session.startRunning()

        if session.isRunning {
            Logger.info("AVCaptureSession 已启动 (resolution=\(resolution.rawValue), fps=\(resolution.fps))")
        } else {
            Logger.error("AVCaptureSession.startRunning() 返回但 isRunning=false")
        }
    }

    func stop() {
        session.stopRunning()
        Logger.info("CameraManager 已停止 (共处理 \(frameCount) 帧, 丢弃 \(droppedFrames) 帧)")
    }

    func switchResolution(_ res: Resolution) {
        Logger.info("切换分辨率: \(resolution.rawValue) → \(res.rawValue)")
        session.stopRunning()
        resolution = res
        frameCount = 0
        droppedFrames = 0
        configure()
        session.startRunning()
        Logger.info("分辨率切换完成: session.isRunning=\(session.isRunning)")
    }

    // MARK: - Private

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = resolution.preset

        // 移除旧输入 + 旧输出
        let oldInputs = session.inputs.count
        let oldOutputs = session.outputs.count
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }

        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera, for: .video, position: .back
        ) else {
            Logger.error("找不到后置摄像头 — 模拟器不支持摄像头，请在真机上运行")
            session.commitConfiguration()
            return
        }

        Logger.debug("使用设备: \(device.localizedName), 支持格式数=\(device.formats.count)")

        do {
            try device.lockForConfiguration()
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: resolution.fps)
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: resolution.fps)
            device.unlockForConfiguration()
            Logger.debug("帧率锁定: \(resolution.fps)fps")
        } catch {
            Logger.error("""
                配置帧率失败: \(error.localizedDescription)
                请求帧率: \(resolution.fps)fps, 设备: \(device.localizedName)
                可能原因: 1) 设备不支持该帧率 2) 其他进程占用摄像头 3) 格式锁定冲突
                """)
        }

        guard let input = try? AVCaptureDeviceInput(device: device) else {
            Logger.error("AVCaptureDeviceInput 创建失败 — device=\(device.localizedName)")
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
            Logger.debug("视频连接已配置: rotation=90°, mirror=\(connection.isVideoMirrored)")
        } else {
            Logger.warn("output.connection(with: .video) 返回 nil")
        }

        session.commitConfiguration()
        Logger.debug("configure() 完成: 输入数=\(session.inputs.count) → \(oldInputs)个旧输入已清除")
    }

    private func reportFPS() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastFPSReportTime)
        guard elapsed >= 5.0 else { return }

        let fps = Double(frameCount) / elapsed
        let dropRate = frameCount > 0 ? Double(droppedFrames) / Double(frameCount + Int64(droppedFrames)) * 100 : 0

        if dropRate > 5 {
            Logger.warn(String(format: "帧率: %.1f fps | 丢帧率: %.1f%% (\(droppedFrames)帧) — 可能 GPU 负载过高", fps, dropRate))
        } else {
            Logger.debug(String(format: "帧率: %.1f fps | 丢帧: \(droppedFrames)帧 (%.1f%%)", fps, dropRate))
        }

        frameCount = 0
        droppedFrames = 0
        lastFPSReportTime = now
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            droppedFrames += 1
            return
        }
        frameCount += 1
        reportFPS()
        onFrame?(pixelBuffer)
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        droppedFrames += 1
        if droppedFrames == 1 || droppedFrames % 120 == 0 {
            Logger.warn("摄像头丢帧 (累计 \(droppedFrames) 帧) — 可能原因: 1) GPU 处理跟不上 2) 主线程阻塞 3) 系统资源不足")
        }
    }
}
