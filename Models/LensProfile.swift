// Models/LensProfile.swift
import Foundation

/// 鱼眼镜头参数，所有数值均为归一化坐标（光学中心 0~1，焦距以纹理宽度的像素为单位）
struct LensProfile: Codable {
    /// 等效焦距（像素单位，相对于输入纹理宽度）—— 值越大鱼眼弯曲越小
    var focalLength: Float = 0.35
    /// 光学中心 X（0~1 归一化），0.5 = 纹理水平正中
    var opticalCenterX: Float = 0.5
    /// 光学中心 Y（0~1 归一化），0.5 = 纹理垂直正中
    var opticalCenterY: Float = 0.5
    /// 径向畸变系数 k1（影响 r² 项）
    var k1: Float = 0.0
    /// 径向畸变系数 k2（影响 r⁴ 项）
    var k2: Float = 0.0
    /// 径向畸变系数 k3（影响 r⁶ 项）
    var k3: Float = 0.0
    /// 输出画面水平 FOV（弧度），默认 90° = π/2 ≈ 1.571
    var outputFovX: Float = 1.571

    /// 加载预设：238° 超广角鱼眼（等距投影，初始无畸变修正）
    static let default238 = LensProfile(
        focalLength: 0.30,
        opticalCenterX: 0.5,
        opticalCenterY: 0.5,
        k1: 0.0,
        k2: 0.0,
        k3: 0.0,
        outputFovX: 1.571
    )

    /// 保存到 UserDefaults
    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: "lensProfile")
    }

    /// 从 UserDefaults 加载
    static func load() -> LensProfile {
        guard let data = UserDefaults.standard.data(forKey: "lensProfile"),
              let profile = try? JSONDecoder().decode(LensProfile.self, from: data) else {
            return .default238
        }
        return profile
    }
}
