// Services/MetalPipeline.swift
import Metal
import MetalKit
import CoreVideo

/// 管理 Metal 渲染管线，执行单 pass 鱼眼矫正 + 三轴稳定
final class MetalPipeline {
    let device: MTLDevice
    private let pipelineState: MTLRenderPipelineState
    private let commandQueue: MTLCommandQueue
    private let textureCache: CVMetalTextureCache

    /// 当前镜头和稳定参数
    var lens = LensProfile.default238
    var roll: Double = 0
    var pitch: Double = 0
    var yaw: Double = 0

    /// 渲染统计
    private var renderCount: Int64 = 0
    private var lastLogTime = Date()
    private var skipCount: Int = 0

    init?() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            Logger.error("Metal 不可用 — 模拟器可能不支持 Metal，请在真机上运行。要求: iPhone 13+ (Metal 3)")
            return nil
        }
        self.device = device
        Logger.info("Metal 设备: \(device.name), GPU 内存: \(device.recommendedMaxWorkingSetSize / 1024 / 1024) MB")

        guard let queue = device.makeCommandQueue() else {
            Logger.error("MTLCommandQueue 创建失败")
            return nil
        }
        self.commandQueue = queue

        guard let library = device.makeDefaultLibrary() else {
            Logger.error("""
                找不到 default Metal library — Shaders/*.metal 未编译进 bundle。
                检查: 1) .metal 文件在 target sources 中 2) MTL_COMPILE_IN_METAL 设置
                """)
            return nil
        }
        Logger.debug("Metal library 已加载, 函数数=\(library.functionNames.count)")

        guard let vertexFn = library.makeFunction(name: "vertex_main") else {
            Logger.error("着色器函数 'vertex_main' 未找到。可用函数: \(library.functionNames.joined(separator: ", "))")
            return nil
        }
        guard let fragmentFn = library.makeFunction(name: "fragment_main") else {
            Logger.error("着色器函数 'fragment_main' 未找到。可用函数: \(library.functionNames.joined(separator: ", "))")
            return nil
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction   = vertexFn
        desc.fragmentFunction = fragmentFn
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm

        do {
            self.pipelineState = try device.makeRenderPipelineState(descriptor: desc)
            Logger.info("Render pipeline state 创建成功")
        } catch {
            Logger.error("""
                创建 pipeline state 失败: \(error.localizedDescription)
                可能原因: 1) 着色器语法错误 2) Metal 版本不匹配 3) pixelFormat 不支持
                请检查 StabilizerShader.metal 语法
                """)
            return nil
        }

        var cache: CVMetalTextureCache?
        let status = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        guard status == kCVReturnSuccess, let cache else {
            Logger.error("CVMetalTextureCache 创建失败 — CVReturn=\(status)")
            return nil
        }
        self.textureCache = cache
        Logger.info("MetalPipeline 初始化完成")
    }

    /// 渲染一帧：输入 CVPixelBuffer（摄像头原始帧），输出到 drawable 纹理
    func render(pixelBuffer: CVPixelBuffer, drawable: MTLTexture) -> Bool {
        let width  = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var cvTextureOut: CVMetalTexture?
        let cvStatus = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, textureCache, pixelBuffer, nil,
            .bgra8Unorm, width, height, 0, &cvTextureOut
        )
        guard cvStatus == kCVReturnSuccess, let cvTexture = cvTextureOut,
              let inputTexture = CVMetalTextureGetTexture(cvTexture) else {
            skipCount += 1
            if skipCount == 1 || skipCount % 120 == 0 {
                Logger.warn("CVMetalTextureCache 映射失败 (累计 \(skipCount) 次) — CVReturn=\(cvStatus), size=\(width)x\(height)")
            }
            return false
        }

        var uniforms = Uniforms(
            opticalCenter: SIMD2(lens.opticalCenterX, lens.opticalCenterY),
            focalLength:   lens.focalLength,
            k1:            lens.k1,
            k2:            lens.k2,
            k3:            lens.k3,
            roll:          Float(-roll),
            pitch:         Float(-pitch),
            yaw:           Float(-yaw),
            outputFovX:    lens.outputFovX,
            inputSize:     SIMD2(Float(width), Float(height))
        )

        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture     = drawable
        rpd.colorAttachments[0].loadAction  = .clear
        rpd.colorAttachments[0].clearColor  = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        rpd.colorAttachments[0].storeAction = .store

        guard let cmdBuf = commandQueue.makeCommandBuffer() else {
            Logger.warn("MTLCommandBuffer 创建失败 — commandQueue 可能已失效")
            return false
        }
        guard let enc = cmdBuf.makeRenderCommandEncoder(descriptor: rpd) else {
            Logger.warn("MTLRenderCommandEncoder 创建失败")
            return false
        }

        enc.setRenderPipelineState(pipelineState)
        enc.setFragmentTexture(inputTexture, index: 0)
        enc.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        enc.endEncoding()

        cmdBuf.addCompletedHandler { [weak self] buf in
            if let error = buf.error {
                Logger.error("GPU 命令执行失败: \(error.localizedDescription)")
            }
            // 渲染超时告警
            let gpuTime = buf.gpuEndTime - buf.gpuStartTime
            if gpuTime > 0.016 { // > 16ms = 低于 60fps
                Logger.warn(String(format: "GPU 帧耗时 %.1fms 超过 16ms 阈值 (%.1f fps)", gpuTime * 1000, 1/gpuTime))
            }
        }

        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()

        renderCount += 1
        reportStats()

        return true
    }

    private func reportStats() {
        let now = Date()
        let elapsed = now.timeIntervalSince(lastLogTime)
        guard elapsed >= 10.0 else { return }
        Logger.debug("渲染统计: \(renderCount) 帧 / \(String(format: "%.1f", elapsed))s = \(String(format: "%.0f", Double(renderCount)/elapsed)) fps, 跳过=\(skipCount)")
        renderCount = 0
        skipCount = 0
        lastLogTime = now
    }
}

// MARK: - 匹配 Metal 侧 Uniforms 布局

struct Uniforms {
    var opticalCenter: SIMD2<Float>
    var focalLength:  Float
    var k1: Float
    var k2: Float
    var k3: Float
    var roll:  Float
    var pitch: Float
    var yaw:   Float
    var outputFovX: Float
    var inputSize: SIMD2<Float>
}
