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

    init?() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("[MetalPipeline] Metal 不可用")
            return nil
        }
        self.device = device

        guard let queue = device.makeCommandQueue() else { return nil }
        self.commandQueue = queue

        guard let library = device.makeDefaultLibrary() else {
            print("[MetalPipeline] 找不到 default Metal library")
            return nil
        }
        guard let vertexFn   = library.makeFunction(name: "vertex_main"),
              let fragmentFn = library.makeFunction(name: "fragment_main") else {
            print("[MetalPipeline] 找不到着色器函数")
            return nil
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction   = vertexFn
        desc.fragmentFunction = fragmentFn
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm

        do {
            self.pipelineState = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            print("[MetalPipeline] 创建 pipeline state 失败: \(error)")
            return nil
        }

        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        guard let cache else { return nil }
        self.textureCache = cache
    }

    /// 渲染一帧：输入 CVPixelBuffer（摄像头原始帧），输出到 drawable 纹理
    func render(pixelBuffer: CVPixelBuffer, drawable: MTLTexture) {
        let width  = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        var cvTextureOut: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, textureCache, pixelBuffer, nil,
            .bgra8Unorm, width, height, 0, &cvTextureOut
        )
        guard let cvTexture = cvTextureOut,
              let inputTexture = CVMetalTextureGetTexture(cvTexture) else { return }

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

        guard let cmdBuf = commandQueue.makeCommandBuffer(),
              let enc = cmdBuf.makeRenderCommandEncoder(descriptor: rpd) else { return }

        enc.setRenderPipelineState(pipelineState)
        enc.setFragmentTexture(inputTexture, index: 0)
        enc.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
        enc.endEncoding()

        cmdBuf.commit()
        cmdBuf.waitUntilCompleted()
    }
}

// MARK: - 匹配 Metal 侧 Uniforms 布局

struct Uniforms {
    var opticalCenter: SIMD2<Float>   // offset 0
    var focalLength:  Float           // offset 8
    var k1: Float                     // offset 12
    var k2: Float                     // offset 16
    var k3: Float                     // offset 20
    var roll:  Float                  // offset 24
    var pitch: Float                  // offset 28
    var yaw:   Float                  // offset 32
    var outputFovX: Float             // offset 36
    var inputSize: SIMD2<Float>       // offset 40
    // total: 48 bytes
}
