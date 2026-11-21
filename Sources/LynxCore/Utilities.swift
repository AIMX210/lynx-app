import Foundation

// MARK: - Shell 引用

public enum ShellQuote {
    /// POSIX 单引号安全引用，任何路径/参数都可安全嵌入远端 sh 命令
    public static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

// MARK: - 路径

public enum PathUtils {
    public static func expandTilde(_ path: String) -> String {
        if path == "~" { return NSHomeDirectory() }
        if path.hasPrefix("~/") {
            return (NSHomeDirectory() as NSString).appendingPathComponent(String(path.dropFirst(2)))
        }
        return path
    }

    public static func join(_ base: String, _ component: String) -> String {
        if component.hasPrefix("/") { return component }
        if base == "/" { return "/" + component }
        return base.hasSuffix("/") ? base + component : base + "/" + component
    }

    public static func parent(_ path: String) -> String {
        if path == "/" { return "/" }
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        let p = (trimmed as NSString).deletingLastPathComponent
        return p.isEmpty ? "/" : p
    }

    public static func displayName(_ path: String) -> String {
        if path == "/" { return "/" }
        return (path as NSString).lastPathComponent
    }
}

// MARK: - 格式化

public enum Formatters {
    public static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .binary)
    }

    /// KB 为单位（/proc 口径）
    public static func kiloBytes(_ kb: UInt64) -> String {
        bytes(kb &* 1024)
    }

    public enum RateUnit: String, Codable, CaseIterable, Sendable {
        case bytes, bits
        public var displayName: String { self == .bytes ? "字节 (KB/s)" : "比特 (Kbps)" }
    }

    /// 速率，明确区分 B/s 与 bps，避免单位歧义混淆
    public static func rate(_ bytesPerSecond: Double, unit: RateUnit = .bytes) -> String {
        let v = max(0, bytesPerSecond)
        switch unit {
        case .bytes:
            if v < 1024 { return String(format: "%.0f B/s", v) }
            if v < 1024 * 1024 { return String(format: "%.1f KB/s", v / 1024) }
            if v < 1024 * 1024 * 1024 { return String(format: "%.2f MB/s", v / 1024 / 1024) }
            return String(format: "%.2f GB/s", v / 1024 / 1024 / 1024)
        case .bits:
            let b = v * 8
            if b < 1000 { return String(format: "%.0f bps", b) }
            if b < 1000_000 { return String(format: "%.1f Kbps", b / 1000) }
            if b < 1000_000_000 { return String(format: "%.2f Mbps", b / 1000_000) }
            return String(format: "%.2f Gbps", b / 1000_000_000)
        }
    }

    public static func percent(_ value: Double, digits: Int = 0) -> String {
        String(format: "%.\(digits)f%%", max(0, value))
    }

    public static func uptime(_ seconds: TimeInterval) -> String {
        let s = Int(max(0, seconds))
        let days = s / 86400, hours = (s % 86400) / 3600, minutes = (s % 3600) / 60
        if days > 0 { return "\(days) 天 \(hours) 小时" }
        if hours > 0 { return "\(hours) 小时 \(minutes) 分" }
        return "\(minutes) 分钟"
    }

    public static func shortUptime(_ seconds: TimeInterval) -> String {
        let s = Int(max(0, seconds))
        let days = s / 86400, hours = (s % 86400) / 3600, minutes = (s % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    public static func dateTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: date)
    }
}