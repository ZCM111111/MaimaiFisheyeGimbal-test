// Services/CrashCatcher.swift
import Foundation

/// 全局异常和信号捕获，崩溃时把堆栈写入 Documents/crash.log
enum CrashCatcher {
    private static var isInstalled = false

    static func install() {
        guard !isInstalled else { return }
        isInstalled = true

        // 1. NSException 捕获
        NSSetUncaughtExceptionHandler { exception in
            let log = """
            === CRASH: NSException ===
            时间: \(Date())
            名称: \(exception.name.rawValue)
            原因: \(exception.reason ?? "nil")
            栈: \(exception.callStackSymbols.joined(separator: "\n"))
            ===========================

            """
            writeToFile(log)
        }

        // 2. 信号捕获 (SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGFPE)
        signal(SIGABRT) { sig in handleSignal(sig, name: "SIGABRT") }
        signal(SIGSEGV) { sig in handleSignal(sig, name: "SIGSEGV") }
        signal(SIGBUS)  { sig in handleSignal(sig, name: "SIGBUS") }
        signal(SIGILL)  { sig in handleSignal(sig, name: "SIGILL") }
        signal(SIGTRAP) { sig in handleSignal(sig, name: "SIGTRAP") }
        signal(SIGFPE)  { sig in handleSignal(sig, name: "SIGFPE") }

        print("[CrashCatcher] 已安装")
    }

    private static func handleSignal(_ sig: Int32, name: String) {
        let log = """
        === CRASH: Signal ===
        时间: \(Date())
        信号: \(name) (\(sig))
        ======================

        """
        writeToFile(log)
        // 信号处理后必须退出
        signal(sig, SIG_DFL)
        raise(sig)
    }

    private static func writeToFile(_ log: String) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let file = docs.appendingPathComponent("crash.log")
        if let existing = try? String(contentsOf: file) {
            try? (existing + "\n" + log).write(to: file, atomically: true, encoding: .utf8)
        } else {
            try? log.write(to: file, atomically: true, encoding: .utf8)
        }
        print(log)
    }
}
