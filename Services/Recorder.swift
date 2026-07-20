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

    /// 输出尺寸（由 MetalPipeline 的 drawable 决定）
    var outputSize: CGSize = CGSize(width: 1920, height: 1080)

    /// 开始录制
    func start() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("stabilized_\(Int(Date().timeIntervalSince1970)).mp4")

        guard let w = try? AVAssetWriter(url: url, fileType: .mp4) else {
            print("[Recorder] AVAssetWriter 创建失败")
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
        w.startWriting()
        w.startSession(atSourceTime: .zero)
        isRecording = true
    }

    /// 追加一帧
    func append(_ pixelBuffer: CVPixelBuffer) {
        guard let input, input.isReadyForMoreMediaData, let adaptor else { return }
        let pts = CMTime(value: frameCount, timescale: 60)
        adaptor.append(pixelBuffer, withPresentationTime: pts)
        frameCount += 1
    }

    /// 完成录制，返回文件 URL
    func stop() -> URL? {
        isRecording = false
        guard let writer else { return nil }
        let url = writer.outputURL
        input?.markAsFinished()
        writer.finishWriting {
            print("[Recorder] 写入完成: \(url.path)")
        }
        self.writer = nil
        self.input  = nil
        self.adaptor = nil
        return url
    }
}
