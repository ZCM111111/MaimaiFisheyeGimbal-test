// Services/Logger.swift
import Foundation
import os

/// 统一日志系统，同时输出到 OSLog 和 console
enum Logger {
    private static let oslog = OSLog(subsystem: "com.maimai.fisheyegimbal", category: "general")
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    enum Level: String {
        case debug = "🔍"
        case info  = "ℹ️"
        case warn  = "⚠️"
        case error = "❌"
        case fatal = "💀"
    }

    static func debug(_ msg: String, file: String = #file) {
        log(level: .debug, msg, file: file)
    }

    static func info(_ msg: String, file: String = #file) {
        log(level: .info, msg, file: file)
    }

    static func warn(_ msg: String, file: String = #file) {
        log(level: .warn, msg, file: file)
    }

    static func error(_ msg: String, file: String = #file) {
        log(level: .error, msg, file: file)
    }

    static func fatal(_ msg: String, file: String = #file) -> Never {
        log(level: .fatal, msg, file: file)
        fatalError(msg)
    }

    private static func log(level: Level, _ msg: String, file: String) {
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        let timestamp = dateFormatter.string(from: Date())
        let line = "[\(timestamp)] \(level.rawValue) [\(fileName)] \(msg)"
        print(line)
        os_log("%{public}@", log: oslog, type: level.osLogType, line)
    }
}

private extension Logger.Level {
    var osLogType: OSLogType {
        switch self {
        case .debug: return .debug
        case .info:  return .info
        case .warn:  return .default
        case .error: return .error
        case .fatal: return .fault
        }
    }
}
