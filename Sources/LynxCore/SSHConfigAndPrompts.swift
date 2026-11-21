import Foundation

// MARK: - ssh_config 导入

public struct ImportedSSHHost: Identifiable, Hashable, Sendable {
    public var id: String { pattern }
    public var pattern: String
    public var hostName: String
    public var user: String?
    public var port: Int?
    public var identityFile: String?
    public var proxyJump: String?

    public init(pattern: String, hostName: String, user: String? = nil, port: Int? = nil,
                identityFile: String? = nil, proxyJump: String? = nil) {
        self.pattern = pattern; self.hostName = hostName; self.user = user
        self.port = port; self.identityFile = identityFile; self.proxyJump = proxyJump
    }
}

public enum SSHConfigParser {
    /// 解析 ~/.ssh/config 中不含通配符的 Host 块
    public static func parse(_ text: String) -> [ImportedSSHHost] {
        var result: [ImportedSSHHost] = []
        var currentPatterns: [String] = []
        var fields: [String: String] = [:]

        func flush() {
            guard !currentPatterns.isEmpty else { return }
            for p in currentPatterns {
                if p.contains("*") || p.contains("?") || p.hasPrefix("!") { continue }
                let hostName = fields["hostname"] ?? p
                result.append(ImportedSSHHost(
                    pattern: p,
                    hostName: hostName,
                    user: fields["user"],
                    port: fields["port"].flatMap(Int.init),
                    identityFile: fields["identityfile"].map(PathUtils.expandTilde),
                    proxyJump: fields["proxyjump"]))
            }
            currentPatterns = []
            fields = [:]
        }

        for rawLine in text.split(separator: "\n") {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if let hash = line.firstIndex(of: "#") { line = String(line[..<hash]).trimmingCharacters(in: .whitespaces) }
            if line.isEmpty { continue }

            // key value 或 key=value
            let kv: (String, String)
            if let eq = line.firstIndex(of: "="), !line.contains(" ") || line.firstIndex(of: " ")! > eq {
                kv = (String(line[..<eq]).trimmingCharacters(in: .whitespaces),
                      String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces))
            } else {
                let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                guard parts.count == 2 else { continue }
                kv = (String(parts[0]), String(parts[1]).trimmingCharacters(in: .whitespaces))
            }
            let key = kv.0.lowercased()
            var value = kv.1
            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }

            if key == "host" {
                flush()
                currentPatterns = value.split(separator: " ").map(String.init)
            } else if !currentPatterns.isEmpty {
                // 同名键首次出现优先（OpenSSH 语义）
                if fields[key] == nil { fields[key] = value }
            }
        }
        flush()
        return result
    }
}

// MARK: - SSH 认证提示识别

public enum PromptSignal: Hashable, Sendable {
    case password
    case passphrase
    case hostKeyConfirm(fingerprint: String)
    case interactive(prompt: String)
    case authFailed
    case hostKeyChanged
    case networkError(String)
}

public enum PromptDetector {
    /// 分析 master 连接 PTY 的累计输出，识别当前需要处理的信号。
    /// 只看尾部输出，避免历史 banner 干扰。
    public static func detect(in text: String) -> PromptSignal? {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let tail = String(normalized.suffix(2500))
        let lower = tail.lowercased()

        if lower.contains("remote host identification has changed") || lower.contains("host key verification failed") {
            return .hostKeyChanged
        }
        if lower.contains("permission denied") {
            return .authFailed
        }
        for (needle, message) in [
            ("connection refused", "连接被拒绝"),
            ("connection timed out", "连接超时"),
            ("operation timed out", "连接超时"),
            ("no route to host", "无法路由到主机"),
            ("could not resolve hostname", "无法解析主机名"),
            ("network is unreachable", "网络不可达"),
            ("connection closed by", "连接被远端关闭"),
            ("kex_exchange_identification", "密钥交换失败"),
            ("connection reset by peer", "连接被重置"),
        ] where lower.contains(needle) {
            return .networkError(message)
        }

        let lines = tail.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let last = lines.last(where: { !$0.isEmpty }) else { return nil }
        let lastLower = last.lowercased()

        if lastLower.contains("(yes/no") || lastLower.contains("[yes/no]") {
            var fingerprint = ""
            for l in lines.reversed() where l.lowercased().contains("fingerprint is") {
                fingerprint = l
                break
            }
            return .hostKeyConfirm(fingerprint: fingerprint.isEmpty ? last : fingerprint)
        }
        if lastLower.hasSuffix(":") || lastLower.hasSuffix("：") {
            if lastLower.contains("passphrase") { return .passphrase }
            if lastLower.contains("password") { return .password }
            if last.count < 120 && !lastLower.contains("last login") {
                return .interactive(prompt: last)
            }
        }
        return nil
    }
}