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

    private var errorCount: Int = 0
    private var lastError: Error? = nil

    /// 启动运动追踪
    func start() {
        guard motion.isDeviceMotionAvailable else {
            Logger.error("DeviceMotion 不可用 — 当前设备不支持或权限未授权。请检查: 1) iPhone 5s+ 2) 设置→隐私→运动与健身")
            return
        }

        motion.deviceMotionUpdateInterval = updateInterval

        motion.startDeviceMotionUpdates(using: .xMagneticNorthZVertical, to: .main) { [weak self] data, error in
            guard let self else { return }

            if let error {
                self.errorCount += 1
                // 仅首次或每 300 次（约 2.5 秒）报告一次，避免刷屏
                if self.errorCount == 1 || self.errorCount % 300 == 0 {
                    let lastErrStr = self.lastError.map { "\n  上一次错误: \($0.localizedDescription)" } ?? ""
                    Logger.error("""
                        CMMotionManager 回调异常 (第 \(self.errorCount) 次)
                        错误: \(error.localizedDescription)\(lastErrStr)
                        可能原因: 1) 传感器硬件故障 2) 主线程阻塞 3) 设备姿态数据不可用
                        """)
                }
                self.lastError = error
                return
            }

            if self.errorCount > 0 {
                Logger.info("CMMotionManager 恢复正常 (此前出错 \(self.errorCount) 次)")
                self.errorCount = 0
            }

            guard let data else {
                Logger.warn("CMMotionManager 回调 data=nil 且无 error — 传感器可能被系统挂起")
                return
            }

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

        Logger.info("MotionManager 启动 (更新频率=\(Int(1/updateInterval))Hz, rollDead=\(deadZone)rad)")
    }

    /// 把当前朝向设为新的"正中心"
    func recenter() {
        guard let attitude = motion.deviceMotion?.attitude else {
            Logger.warn("recenter 失败 — motion.deviceMotion 为 nil，MotionManager 是否已 start()?")
            return
        }
        let oldBase = (baseRoll, basePitch, baseYaw)
        baseRoll  = attitude.roll
        basePitch = attitude.pitch
        baseYaw   = attitude.yaw
        roll  = 0
        pitch = 0
        yaw   = 0
        Logger.info(String(format: "回中完成: roll %.2f°→0, pitch %.2f°→0, yaw %.2f°→0",
            oldBase.0 * 180/Double.pi, oldBase.1 * 180/Double.pi, oldBase.2 * 180/Double.pi))
    }

    /// 停止追踪
    func stop() {
        motion.stopDeviceMotionUpdates()
        Logger.info("MotionManager 已停止")
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
