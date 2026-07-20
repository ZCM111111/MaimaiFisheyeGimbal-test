// ContentView.swift
import SwiftUI
import MetalKit
import AVFoundation

struct ContentView: View {
    @StateObject private var motion   = MotionManager()
    @StateObject private var camera   = CameraManager(resolution: .p1080_60)
    @State private var pipeline: MetalPipeline?
    @State private var recorder = Recorder()
    @State private var lens = LensProfile.load()
    @State private var isRecording = false
    @State private var showSettings = false
    @State private var resolution: CameraManager.Resolution = .p1080_60

    @State private var rollStrength: Double  = 1.0
    @State private var pitchStrength: Double = 1.0
    @State private var yawStrength: Double   = 1.0
    @State private var deadZone: Double      = 0.005

    var body: some View {
        ZStack {
            MetalPreviewView(
                pipeline: $pipeline,
                camera: camera,
                motion: motion,
                recorder: recorder,
                isRecording: $isRecording,
                rollStrength: $rollStrength,
                pitchStrength: $pitchStrength,
                yawStrength: $yawStrength
            )
            .ignoresSafeArea()

            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(resolutionLabel)
                            .font(.system(size: 12, design: .monospaced))
                        Text(isRecording ? "● REC" : "")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.red)
                    }
                    .padding(8)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    Spacer()

                    Button(resolutionLabel) {
                        toggleResolution()
                    }
                    .font(.system(size: 12))
                    .padding(6)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                }
                .padding(.horizontal, 16)
                .padding(.top, 48)

                Spacer()

                HStack(spacing: 40) {
                    Button {
                        motion.recenter()
                    } label: {
                        Image(systemName: "scope")
                            .font(.title2)
                            .padding(12)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }

                    Button {
                        toggleRecording()
                    } label: {
                        Circle()
                            .fill(isRecording ? .red : .white)
                            .frame(width: 64, height: 64)
                            .overlay(
                                Circle()
                                    .stroke(.white.opacity(0.3), lineWidth: 4)
                                    .frame(width: 74, height: 74)
                            )
                    }

                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.title2)
                            .padding(12)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
                .padding(.bottom, 48)
            }
        }
        .onAppear {
            pipeline = MetalPipeline()
            pipeline?.lens = lens
            motion.start()
            Task { await camera.start() }
        }
        .onChange(of: lens.outputFovX)    { _, _ in lens.save() }
        .onChange(of: lens.focalLength)   { _, _ in lens.save() }
        .onChange(of: lens.opticalCenterX) { _, _ in lens.save() }
        .onChange(of: lens.opticalCenterY) { _, _ in lens.save() }
        .onChange(of: lens.k1)            { _, _ in lens.save() }
        .onChange(of: lens.k2)            { _, _ in lens.save() }
        .onChange(of: lens.k3)            { _, _ in lens.save() }
        .sheet(isPresented: $showSettings) {
            SettingsView(
                lens: $lens,
                rollStrength: $rollStrength,
                pitchStrength: $pitchStrength,
                yawStrength: $yawStrength,
                deadZone: $deadZone,
                onRecenter: { motion.recenter() }
            )
        }
    }

    private var resolutionLabel: String {
        resolution == .p4k_60 ? "4K60" : "1080p60"
    }

    private func toggleRecording() {
        isRecording.toggle()
        if isRecording {
            recorder.start()
        } else {
            let url = recorder.stop()
            if let url {
                UISaveVideoAtPathToSavedPhotosAlbum(url.path, nil, nil, nil)
                print("[ContentView] 视频已保存: \(url)")
            }
        }
    }

    private func toggleResolution() {
        resolution = (resolution == .p4k_60) ? .p1080_60 : .p4k_60
        camera.switchResolution(resolution)
    }
}

// MARK: - Metal 预览 View

struct MetalPreviewView: UIViewRepresentable {
    @Binding var pipeline: MetalPipeline?
    var camera: CameraManager
    var motion: MotionManager
    var recorder: Recorder
    @Binding var isRecording: Bool
    @Binding var rollStrength: Double
    @Binding var pitchStrength: Double
    @Binding var yawStrength: Double

    func makeUIView(context: Context) -> MTKView {
        let mtk = MTKView()
        mtk.device = pipeline?.device
        mtk.framebufferOnly = false
        mtk.colorPixelFormat = .bgra8Unorm
        mtk.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mtk.delegate = context.coordinator
        mtk.preferredFramesPerSecond = 60
        return mtk
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.rollStrength  = rollStrength
        context.coordinator.pitchStrength = pitchStrength
        context.coordinator.yawStrength   = yawStrength
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, MTKViewDelegate {
        var parent: MetalPreviewView
        var rollStrength: Double  = 1.0
        var pitchStrength: Double = 1.0
        var yawStrength: Double   = 1.0

        init(parent: MetalPreviewView) {
            self.parent = parent
            super.init()
            parent.camera.onFrame = { [weak self] pixelBuffer in
                guard let self,
                      let pipeline = self.parent.pipeline,
                      let view = self.parent.pipeline?.device else { return }
                // render is driven by camera frame callback, not MTKView draw loop
                // the MTKView's current drawable is used in the callback
            }
        }

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            parent.recorder.outputSize = size
        }

        func draw(in view: MTKView) {
            guard let pipeline = parent.pipeline,
                  let drawable = view.currentDrawable?.texture else { return }

            // Camera frames drive the pipeline, not the MTKView draw loop
            // If we have a pending frame, process it; otherwise draw black (clear)
            // On real device, camera.onFrame callback should trigger view.setNeedsDisplay()
        }
    }
}
