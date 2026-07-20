// Services/MotionManager.swift
import CoreMotion
import Combine

/// 以 120Hz 追踪设备三轴姿态，支持一键回中
final class MotionManager: ObservableObject {
    private let motion = CMMotionManager()
    private let updateInterval = 1.0 / 120.0

    /// 当前三轴角度（相对基准，单位弧度）
    @Published var roll: Double = 0.0
    @Published var pitch: Double = 0.0
    @Published var yaw: Double = 0.0

    /// 回中基准
    private var baseRoll: Double = 0.0
    private var basePitch: Double = 0.0
    private var baseYaw: Double = 0.0

    /// 死区（弧度），小于此值的姿态变化视为噪声
    var deadZone: Double = 0.005

    /// 对各轴单独设置锁定强度（0~1，1=完全锁定）
    var rollStrength: Double = 1.0
    var pitchStrength: Double = 1.0
    var yawStrength: Double = 1.0

    /// 启动运动追踪
    func start() {
        guard motion.isDeviceMotionAvailable else {
            print("[MotionManager] DeviceMotion 不可用")
            return
        }
        motion.deviceMotionUpdateInterval = updateInterval
        motion.startDeviceMotionUpdates(using: .xMagneticNorthZVertical, to: .main) { [weak self] data, error in
            guard let self, let data else { return }
            if let error { print("[MotionManager] 错误: \(error.localizedDescription)") }

            let rawRoll  = data.attitude.roll
            let rawPitch = data.attitude.pitch
            let rawYaw   = data.attitude.yaw

            let dRoll  = rawRoll  - self.baseRoll
            let dPitch = rawPitch - self.basePitch
            let dYaw   = rawYaw   - self.baseYaw

            self.roll  = self.applyDeadZone(dRoll)  * self.rollStrength
            self.pitch = self.applyDeadZone(dPitch) * self.pitchStrength
            self.yaw   = self.applyDeadZone(dYaw)   * self.yawStrength
        }
    }

    /// 把当前朝向设为新的"正中心"
    func recenter() {
        guard let attitude = motion.deviceMotion?.attitude else { return }
        baseRoll  = attitude.roll
        basePitch = attitude.pitch
        baseYaw   = attitude.yaw
        roll  = 0
        pitch = 0
        yaw   = 0
    }

    /// 停止追踪
    func stop() {
        motion.stopDeviceMotionUpdates()
    }

    /// 原子读取当前快照
    func snapshot() -> (roll: Double, pitch: Double, yaw: Double) {
        return (roll, pitch, yaw)
    }

    // MARK: - Private

    private func applyDeadZone(_ value: Double) -> Double {
        if abs(value) < deadZone { return 0 }
        return value
    }
}
