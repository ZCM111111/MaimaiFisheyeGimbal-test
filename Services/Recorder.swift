// Services/Recorder.swift
import AVFoundation
import CoreVideo

/// 将渲染后的 CVPixelBuffer 写入 .mov 文件
final class Recorder {
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private(set) var isRecording = false
    private var frameCount: Int64 = 0
    private var errorCount: Int = 0
    private var startTime: Date?

    /// 输出尺寸（由 MetalPipeline 的 drawable 决定）
    var outputSize: CGSize = CGSize(width: 1920, height: 1080)

    /// 开始录制
    func start() {
        guard !isRecording else {
            Logger.warn("录制已在进行中，忽略重复 start()")
            return
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("stabilized_\(Int(Date().timeIntervalSince1970)).mp4")

        Logger.info("开始录制: \(url.lastPathComponent), 分辨率=\(Int(outputSize.width))x\(Int(outputSize.height))")

        guard let w = try? AVAssetWriter(url: url, fileType: .mp4) else {
            Logger.error("AVAssetWriter 创建失败 — fileType=.mp4, url=\(url.lastPathComponent)。可能原因: 1) 磁盘空间不足 2) 临时目录不可写")
            return
        }
        self.writer = w

        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey:  outputSize.width,
            AVVideoHeightKey: outputSize.height
        ]
        let avInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        avInput.expectsMediaDataInRealTime = true

        if !w.canAdd(avInput) {
            Logger.error("AVAssetWriter 无法添加视频输入 — 检查 outputSettings: \(settings)")
            return
        }
        w.add(avInput)

        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey  as String: outputSize.width,
            kCVPixelBufferHeightKey as String: outputSize.height
        ]
        self.adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: avInput,
            sourcePixelBufferAttributes: attrs
        )
        self.input = avInput
        self.frameCount = 0
        self.errorCount = 0
        self.startTime = Date()

        if !w.startWriting() {
            Logger.error("AVAssetWriter.startWriting() 失败 — status=\(w.status.rawValue), error=\(w.error?.localizedDescription ?? "nil")")
            return
        }
        w.startSession(atSourceTime: .zero)

        isRecording = true
        Logger.info("录制已开始 (HEVC, \(Int(outputSize.width))x\(Int(outputSize.height)), 60fps)")
    }

    /// 追加一帧
    func append(_ pixelBuffer: CVPixelBuffer) {
        guard isRecording else { return }
        guard let input, input.isReadyForMoreMediaData else {
            errorCount += 1
            if errorCount == 1 || errorCount % 120 == 0 {
                Logger.warn("""
                    录制帧写入被跳过 (累计 \(errorCount) 次)
                    isReadyForMoreMediaData=\(input?.isReadyForMoreMediaData ?? false)
                    可能原因: 1) 编码器来不及处理 (GPU 负载过高) 2) 磁盘 I/O 瓶颈
                    """)
            }
            return
        }
        guard let adaptor else { return }

        let pts = CMTime(value: frameCount, timescale: 60)
        if !adaptor.append(pixelBuffer, withPresentationTime: pts) {
            errorCount += 1
            if errorCount == 1 || errorCount % 120 == 0 {
                Logger.error("""
                    adaptor.append() 失败 (累计 \(errorCount) 次)
                    writer.status=\(writer?.status.rawValue ?? -1), writer.error=\(writer?.error?.localizedDescription ?? "nil")
                    """)
            }
            return
        }
        frameCount += 1
    }

    /// 完成录制，返回文件 URL
    func stop() -> URL? {
        guard isRecording else {
            Logger.warn("录制未在进行中，忽略 stop()")
            return nil
        }
        isRecording = false

        let elapsed = startTime.map { Date().timeIntervalSince($0) } ?? 0
        let actualFPS = elapsed > 0 ? Double(frameCount) / elapsed : 0
        Logger.info(String(format: "停止录制: \(frameCount) 帧 / %.1fs = %.1f fps, 错误=\(errorCount)", elapsed, actualFPS))

        guard let writer else { return nil }
        let url = writer.outputURL

        input?.markAsFinished()

        let semaphore = DispatchSemaphore(value: 0)
        writer.finishWriting {
            if writer.status == .failed {
                Logger.error("""
                    录制写入失败!
                    status=\(writer.status.rawValue)
                    error=\(writer.error?.localizedDescription ?? "nil")
                    url=\(url.path)
                    """)
            } else if writer.status == .completed {
                let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                Logger.info("录制完成: \(url.lastPathComponent) (\(fileSize / 1024 / 1024) MB)")
            } else {
                Logger.warn("录制完成但状态异常: status=\(writer.status.rawValue)")
            }
            semaphore.signal()
        }

        self.writer = nil
        self.input  = nil
        self.adaptor = nil

        // 最多等 5 秒
        _ = semaphore.wait(timeout: .now() + 5)
        return url
    }
}
