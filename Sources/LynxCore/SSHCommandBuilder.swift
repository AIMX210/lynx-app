import Foundation

public enum HostKeyPolicy: String, Codable, CaseIterable, Sendable {
    /// 首次连接自动信任新主机密钥（TOFU），密钥变更仍拒绝
    case acceptNew
    /// 严格模式：新主机也需手动确认指纹
    case strict

    public var sshValue: String { self == .acceptNew ? "accept-new" : "yes" }
    public var displayName: String {
        self == .acceptNew ? "首次自动信任（推荐）" : "每次确认指纹"
    }
}

/// 构造 OpenSSH 命令行。所有会话复用同一 ControlMaster socket：
/// 一台服务器 = 一条 TCP 连接 + 一个 ssh 常驻进程，其余操作都是轻量复用客户端。
public struct SSHCommandBuilder: Sendable {
    public static let sshPath = "/usr/bin/ssh"

    public let server: ServerHost
    public let socketPath: String

    public init(server: ServerHost, socketPath: String) {
        self.server = server
        self.socketPath = socketPath
    }

    /// 每台服务器一个短 socket 路径（sun_path 上限 104 字节）
    public static func socketPath(for serverID: UUID, tempDirectory: String) -> String {
        let short = serverID.uuidString.prefix(8).lowercased()
        let dir = tempDirectory.hasSuffix("/") ? tempDirectory : tempDirectory + "/"
        return dir + "lynx-\(short).sock"
    }

    /// 常驻主连接：ssh -N -M，持有认证与 TCP 连接
    public func masterArgs(hostKeyPolicy: HostKeyPolicy, connectTimeout: Int = 15) -> [String] {
        var args = [
            "-N", "-M",
            "-S", socketPath,
            "-o", "ExitOnForwardFailure=yes",
            "-o", "ServerAliveInterval=30",
            "-o", "ServerAliveCountMax=3",
            "-o", "ConnectTimeout=\(connectTimeout)",
            "-o", "StrictHostKeyChecking=\(hostKeyPolicy.sshValue)",
            "-o", "NumberOfPasswordPrompts=3",
            "-p", String(server.port),
            "-l", server.user,
        ]
        switch server.auth {
        case .agent:
            break
        case .key:
            if let key = server.keyPath {
                args += ["-i", PathUtils.expandTilde(key), "-o", "IdentitiesOnly=yes"]
            }
            args += ["-o", "PreferredAuthentications=publickey"]
        case .password:
            args += ["-o", "PreferredAuthentications=password,keyboard-interactive",
                     "-o", "PubkeyAuthentication=no"]
        }
        if let jump = server.jump, !jump.isEmpty {
            args += ["-J", jump]
        }
        args.append(server.host)
        return args
    }

    /// 复用通道执行远端命令（命令整体交给远端 shell，路径已用 ShellQuote 处理）
    public func execArgs(remoteCommand: String) -> [String] {
        ["-S", socketPath,
         "-o", "ControlMaster=no",
         "-o", "ConnectTimeout=10",
         "-o", "BatchMode=yes",
         server.host, remoteCommand]
    }

    /// 交互式终端（本地 PTY 由终端视图提供，远端自动分配 TTY）
    public func terminalArgs() -> [String] {
        ["-S", socketPath,
         "-o", "ControlMaster=no",
         "-o", "ServerAliveInterval=30",
         "-o", "ServerAliveCountMax=3",
         server.host]
    }

    /// 控制命令：check / exit / forward / cancel
    public func controlArgs(_ command: String, extra: [String] = []) -> [String] {
        ["-S", socketPath, "-O", command] + extra + [server.host]
    }

    public func forwardArgs(rule: ForwardRule, cancel: Bool) -> [String] {
        controlArgs(cancel ? "cancel" : "forward", extra: [rule.kind.flag, rule.spec])
    }

    /// 终端环境变量：保留用户环境，固定 TERM 以获得完整彩色能力
    public static func terminalEnvironment() -> [String] {
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env.removeValue(forKey: "TERM_PROGRAM")
        return env.map { "\($0.key)=\($0.value)" }
    }
}