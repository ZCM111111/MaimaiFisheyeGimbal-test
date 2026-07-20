// Views/SettingsView.swift
import SwiftUI

struct SettingsView: View {
    @Binding var lens: LensProfile
    @Binding var rollStrength: Double
    @Binding var pitchStrength: Double
    @Binding var yawStrength: Double
    @Binding var deadZone: Double

    var onRecenter: () -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("鱼眼镜头参数") {
                    slider(title: "焦距",       value: $lens.focalLength, range: 0.1...1.0, format: "%.2f")
                    slider(title: "光学中心 X", value: $lens.opticalCenterX, range: 0.3...0.7, format: "%.3f")
                    slider(title: "光学中心 Y", value: $lens.opticalCenterY, range: 0.3...0.7, format: "%.3f")
                    slider(title: "畸变 k1",    value: $lens.k1, range: -2.0...2.0, format: "%.2f")
                    slider(title: "畸变 k2",    value: $lens.k2, range: -2.0...2.0, format: "%.2f")
                    slider(title: "畸变 k3",    value: $lens.k3, range: -2.0...2.0, format: "%.2f")
                    slider(title: "输出 FOV",   value: $lens.outputFovX, range: 0.5...2.6, format: "%.2f rad")
                }

                Section("三轴锁定强度") {
                    slider(title: "Roll 强度",  value: $rollStrength, range: 0...1, format: "%.0f%%")
                    slider(title: "Pitch 强度", value: $pitchStrength, range: 0...1, format: "%.0f%%")
                    slider(title: "Yaw 强度",   value: $yawStrength, range: 0...1, format: "%.0f%%")
                }

                Section("高级") {
                    slider(title: "姿态死区", value: $deadZone, range: 0...0.05, format: "%.3f rad")
                    Button("回中（当前朝向 = 正中）") { onRecenter() }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func slider(
        title: String, value: Binding<Float>,
        range: ClosedRange<Float>, format: String
    ) -> some View {
        HStack {
            Text(title).frame(width: 100, alignment: .leading)
            Slider(value: value, in: range)
            Text(String(format: format, value.wrappedValue))
                .frame(width: 60, alignment: .trailing)
                .monospacedDigit()
        }
    }

    private func slider(
        title: String, value: Binding<Double>,
        range: ClosedRange<Double>, format: String
    ) -> some View {
        let cv = Binding<Float>(
            get: { Float(value.wrappedValue) },
            set: { value.wrappedValue = Double($0) }
        )
        return HStack {
            Text(title).frame(width: 100, alignment: .leading)
            Slider(value: cv, in: Float(range.lowerBound)...Float(range.upperBound))
            Text(String(format: format, value.wrappedValue))
                .frame(width: 60, alignment: .trailing)
                .monospacedDigit()
        }
    }
}
