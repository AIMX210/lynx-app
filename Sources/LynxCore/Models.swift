import Foundation

// MARK: - 服务器与组织

public enum AuthMethod: String, Codable, CaseIterable, Sendable {
    /// 交给 OpenSSH 默认行为：ssh-agent、~/.ssh/config、默认密钥
    case agent
    /// 指定私钥文件（IdentitiesOnly）
    case key
    /// 密码 / 键盘交互（密码存 Keychain）
    case password

    public var displayName: String {
        switch self {
        case .agent: return "Agent / 默认配置"
        case .key: return "指定密钥"
        case .password: return "密码"
        }
    }
}

public struct ServerHost: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var host: String
    public var port: Int
    public var user: String
    public var auth: AuthMethod
    public var keyPath: String?
    /// 跳板机，形如 user@bastion:22
    public var jump: String?
    public var groupID: UUID?
    public var tags: [String]
    public var notes: String
    public var autoConnect: Bool
    public var monitorEnabled: Bool
    /// 覆盖全局轮询间隔（秒），nil 用全局
    public var pollInterval: Double?
    public var sortOrder: Int
    public var createdAt: Date

    public init(id: UUID = UUID(), name: String = "", host: String = "", port: Int = 22,
                user: String = "root", auth: AuthMethod = .agent, keyPath: String? = nil,
                jump: String? = nil, groupID: UUID? = nil, tags: [String] = [], notes: String = "",
                autoConnect: Bool = false, monitorEnabled: Bool = true, pollInterval: Double? = nil,
                sortOrder: Int = 0, createdAt: Date = Date()) {
        self.id = id; self.name = name; self.host = host; self.port = port; self.user = user
        self.auth = auth; self.keyPath = keyPath; self.jump = jump; self.groupID = groupID
        self.tags = tags; self.notes = notes; self.autoConnect = autoConnect
        self.monitorEnabled = monitorEnabled; self.pollInterval = pollInterval
        self.sortOrder = sortOrder; self.createdAt = createdAt
    }

    public var displayName: String { name.isEmpty ? host : name }
    public var destination: String { "\(user)@\(host)" }
}

public struct ServerGroup: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var sortOrder: Int

    public init(id: UUID = UUID(), name: String, sortOrder: Int = 0) {
        self.id = id; self.name = name; self.sortOrder = sortOrder
    }
}

public struct Snippet: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var command: String
    public var sortOrder: Int

    public init(id: UUID = UUID(), name: String, command: String, sortOrder: Int = 0) {
        self.id = id; self.name = name; self.command = command; self.sortOrder = sortOrder
    }
}

public struct ForwardRule: Codable, Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case local, remote, dynamic
        public var displayName: String {
            switch self {
            case .local: return "本地转发 (-L)"
            case .remote: return "远程转发 (-R)"
            case .dynamic: return "动态 SOCKS (-D)"
            }
        }
        public var flag: String {
            switch self {
            case .local: return "-L"
            case .remote: return "-R"
            case .dynamic: return "-D"
            }
        }
    }

    public var id: UUID
    public var serverID: UUID
    public var kind: Kind
    public var bindHost: String
    public var bindPort: Int
    public var destHost: String
    public var destPort: Int
    public var autoStart: Bool
    public var label: String

    public init(id: UUID = UUID(), serverID: UUID, kind: Kind = .local,
                bindHost: String = "127.0.0.1", bindPort: Int = 8080,
                destHost: String = "127.0.0.1", destPort: Int = 80,
                autoStart: Bool = false, label: String = "") {
        self.id = id; self.serverID = serverID; self.kind = kind
        self.bindHost = bindHost; self.bindPort = bindPort
        self.destHost = destHost; self.destPort = destPort
        self.autoStart = autoStart; self.label = label
    }

    /// OpenSSH 转发规格
    public var spec: String {
        switch kind {
        case .dynamic: return "\(bindHost):\(bindPort)"
        case .local, .remote: return "\(bindHost):\(bindPort):\(destHost):\(destPort)"
        }
    }

    public var displayName: String {
        label.isEmpty ? spec : label
    }
}

// MARK: - 密钥

public struct SSHKeyInfo: Identifiable, Hashable, Sendable {
    public var id: String { privatePath }
    public var name: String
    public var privatePath: String
    public var publicPath: String?
    public var publicKey: String?
    public var type: String
    public var comment: String
    public var hasPrivate: Bool

    public init(name: String, privatePath: String, publicPath: String? = nil,
                publicKey: String? = nil, type: String = "", comment: String = "",
                hasPrivate: Bool = true) {
        self.name = name; self.privatePath = privatePath; self.publicPath = publicPath
        self.publicKey = publicKey; self.type = type; self.comment = comment
        self.hasPrivate = hasPrivate
    }
}

// MARK: - 远端数据

public struct RemoteFile: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public var name: String
    public var isDir: Bool
    public var isLink: Bool
    public var linkTarget: String?
    public var size: UInt64
    public var mtime: Date?
    public var permissions: String
    public var owner: String
    public var group: String

    public init(name: String, isDir: Bool, isLink: Bool = false, linkTarget: String? = nil,
                size: UInt64 = 0, mtime: Date? = nil, permissions: String = "",
                owner: String = "", group: String = "") {
        self.name = name; self.isDir = isDir; self.isLink = isLink; self.linkTarget = linkTarget
        self.size = size; self.mtime = mtime; self.permissions = permissions
        self.owner = owner; self.group = group
    }
}

public struct ProcessRow: Identifiable, Hashable, Sendable {
    public var id: Int32 { pid }
    public var pid: Int32
    public var ppid: Int32
    public var user: String
    public var cpu: Double
    public var mem: Double
    public var rssKB: UInt64
    public var time: String
    public var command: String

    public init(pid: Int32, ppid: Int32, user: String, cpu: Double, mem: Double,
                rssKB: UInt64, time: String, command: String) {
        self.pid = pid; self.ppid = ppid; self.user = user; self.cpu = cpu; self.mem = mem
        self.rssKB = rssKB; self.time = time; self.command = command
    }
}

public struct DockerContainer: Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var image: String
    public var state: String
    public var status: String
    public var ports: String
    public var cpu: Double?
    public var memUsage: String?
    public var memPerc: String?
    public var netIO: String?
    public var blockIO: String?

    public init(id: String, name: String, image: String, state: String, status: String,
                ports: String, cpu: Double? = nil, memUsage: String? = nil,
                memPerc: String? = nil, netIO: String? = nil, blockIO: String? = nil) {
        self.id = id; self.name = name; self.image = image; self.state = state
        self.status = status; self.ports = ports; self.cpu = cpu; self.memUsage = memUsage
        self.memPerc = memPerc; self.netIO = netIO; self.blockIO = blockIO
    }

    public var isRunning: Bool { state == "running" }
}

public struct DockerImage: Identifiable, Hashable, Sendable {
    public var id: String
    public var tag: String
    public var size: String
    public var created: String

    public init(id: String, tag: String, size: String, created: String) {
        self.id = id; self.tag = tag; self.size = size; self.created = created
    }
}

public struct DockerOverview: Sendable {
    public var serverVersion: String
    public var running: Int
    public var stopped: Int
    public var imageCount: Int
    public var containers: [DockerContainer]
    public var images: [DockerImage]
    public var available: Bool

    public init(serverVersion: String = "", running: Int = 0, stopped: Int = 0,
                imageCount: Int = 0, containers: [DockerContainer] = [],
                images: [DockerImage] = [], available: Bool = false) {
        self.serverVersion = serverVersion; self.running = running; self.stopped = stopped
        self.imageCount = imageCount; self.containers = containers; self.images = images
        self.available = available
    }
}

// MARK: - 监控指标

public struct MemInfo: Hashable, Sendable {
    public var totalKB: UInt64
    public var freeKB: UInt64
    public var availableKB: UInt64
    public var buffersKB: UInt64
    public var cachedKB: UInt64
    public var reclaimableKB: UInt64
    public var swapTotalKB: UInt64
    public var swapFreeKB: UInt64

    public init(totalKB: UInt64 = 0, freeKB: UInt64 = 0, availableKB: UInt64 = 0,
                buffersKB: UInt64 = 0, cachedKB: UInt64 = 0, reclaimableKB: UInt64 = 0,
                swapTotalKB: UInt64 = 0, swapFreeKB: UInt64 = 0) {
        self.totalKB = totalKB; self.freeKB = freeKB; self.availableKB = availableKB
        self.buffersKB = buffersKB; self.cachedKB = cachedKB; self.reclaimableKB = reclaimableKB
        self.swapTotalKB = swapTotalKB; self.swapFreeKB = swapFreeKB
    }

    /// htop 口径：total - free - buffers - cached - reclaimable
    public var usedKB: UInt64 {
        let subtract = freeKB &+ buffersKB &+ cachedKB &+ reclaimableKB
        return totalKB > subtract ? totalKB - subtract : 0
    }
    public var usedPercent: Double {
        totalKB == 0 ? 0 : Double(usedKB) / Double(totalKB) * 100
    }
    public var swapUsedKB: UInt64 { swapTotalKB > swapFreeKB ? swapTotalKB - swapFreeKB : 0 }
}

public struct CPUUsage: Hashable, Sendable {
    public var total: Double
    public var user: Double
    public var system: Double
    public var iowait: Double
    public var perCore: [Double]

    public init(total: Double, user: Double = 0, system: Double = 0,
                iowait: Double = 0, perCore: [Double] = []) {
        self.total = total; self.user = user; self.system = system
        self.iowait = iowait; self.perCore = perCore
    }
}

public struct NetInterface: Identifiable, Hashable, Sendable {
    public var id: String { name }
    public var name: String
    public var rxBps: Double
    public var txBps: Double
    public var rxTotal: UInt64
    public var txTotal: UInt64

    public init(name: String, rxBps: Double, txBps: Double, rxTotal: UInt64, txTotal: UInt64) {
        self.name = name; self.rxBps = rxBps; self.txBps = txBps
        self.rxTotal = rxTotal; self.txTotal = txTotal
    }
}

public struct DiskIO: Identifiable, Hashable, Sendable {
    public var id: String { device }
    public var device: String
    public var readBps: Double
    public var writeBps: Double
    public var readIOPS: Double
    public var writeIOPS: Double

    public init(device: String, readBps: Double, writeBps: Double,
                readIOPS: Double, writeIOPS: Double) {
        self.device = device; self.readBps = readBps; self.writeBps = writeBps
        self.readIOPS = readIOPS; self.writeIOPS = writeIOPS
    }
}

public struct FSUsage: Identifiable, Hashable, Sendable {
    public var id: String { mount }
    public var mount: String
    public var usedBytes: UInt64
    public var totalBytes: UInt64

    public init(mount: String, usedBytes: UInt64, totalBytes: UInt64) {
        self.mount = mount; self.usedBytes = usedBytes; self.totalBytes = totalBytes
    }
    public var usedPercent: Double {
        totalBytes == 0 ? 0 : Double(usedBytes) / Double(totalBytes) * 100
    }
}

public struct GPUInfo: Identifiable, Hashable, Sendable {
    public var id: Int { index }
    public var index: Int
    public var name: String
    public var utilization: Double
    public var memUsedMB: Double
    public var memTotalMB: Double
    public var tempC: Double?
    public var powerW: Double?

    public init(index: Int, name: String, utilization: Double, memUsedMB: Double,
                memTotalMB: Double, tempC: Double? = nil, powerW: Double? = nil) {
        self.index = index; self.name = name; self.utilization = utilization
        self.memUsedMB = memUsedMB; self.memTotalMB = memTotalMB
        self.tempC = tempC; self.powerW = powerW
    }
    public var memPercent: Double {
        memTotalMB == 0 ? 0 : memUsedMB / memTotalMB * 100
    }
}

/// 脚本一次采样的原始计数器（未做差分）
public struct RawMetrics: Sendable {
    public var host: String = ""
    public var os: String = ""
    public var kernel: String = ""
    public var arch: String = ""
    public var uptime: TimeInterval = 0
    public var cores: Int = 0
    public var load: [Double] = []
    public var loadProcs: String = ""
    /// Linux: user nice system idle iowait irq softirq steal
    public var cpuJiffies: [UInt64]?
    public var perCoreJiffies: [[UInt64]] = []
    /// macOS: user% system% idle%
    public var cpuPercent: (user: Double, system: Double, idle: Double)?
    public var mem: MemInfo?
    /// iface -> (rxBytes, txBytes)
    public var nets: [(name: String, rx: UInt64, tx: UInt64)] = []
    /// device -> diskstats 8 个计数器
    public var disks: [(device: String, counters: [UInt64])] = []
    public var fs: [FSUsage] = []
    public var tcpEstablished: Int?
    public var tempC: Double?
    public var gpus: [GPUInfo] = []
    public var isDarwin: Bool = false

    public init() {}
}

/// 差分后的展示快照
public struct MetricsSnapshot: Sendable {
    public var timestamp: Date
    public var host: String
    public var os: String
    public var kernel: String
    public var arch: String
    public var uptime: TimeInterval
    public var cores: Int
    public var load: [Double]
    public var loadProcs: String
    /// 首次采样为 nil（无差分基准）
    public var cpu: CPUUsage?
    public var mem: MemInfo?
    public var nets: [NetInterface]
    public var disks: [DiskIO]
    public var fs: [FSUsage]
    public var tcpEstablished: Int?
    public var tempC: Double?
    public var gpus: [GPUInfo]
    public var isDarwin: Bool

    public init(timestamp: Date, raw: RawMetrics, cpu: CPUUsage?,
                nets: [NetInterface], disks: [DiskIO]) {
        self.timestamp = timestamp
        self.host = raw.host; self.os = raw.os; self.kernel = raw.kernel; self.arch = raw.arch
        self.uptime = raw.uptime; self.cores = raw.cores; self.load = raw.load
        self.loadProcs = raw.loadProcs; self.cpu = cpu; self.mem = raw.mem
        self.nets = nets; self.disks = disks; self.fs = raw.fs
        self.tcpEstablished = raw.tcpEstablished; self.tempC = raw.tempC
        self.gpus = raw.gpus; self.isDarwin = raw.isDarwin
    }

    public var totalRxBps: Double { nets.reduce(0) { $0 + $1.rxBps } }
    public var totalTxBps: Double { nets.reduce(0) { $0 + $1.txBps } }
}

// MARK: - 连接状态

public enum AuthPrompt: Hashable, Sendable {
    case password
    case passphrase
    case hostKeyConfirm(fingerprint: String)
    case interactive(prompt: String)
}

public enum ConnectionPhase: Hashable, Sendable {
    case disconnected
    case connecting
    case awaitingInput(AuthPrompt)
    case ready
    case failed(String)

    public var isReady: Bool { self == .ready }
    public var isBusy: Bool {
        switch self {
        case .connecting, .awaitingInput: return true
        default: return false
        }
    }
}

// MARK: - 执行结果与错误

public struct ExecResult: Sendable {
    public var stdout: Data
    public var stderr: Data
    public var exitCode: Int32

    public init(stdout: Data, stderr: Data, exitCode: Int32) {
        self.stdout = stdout; self.stderr = stderr; self.exitCode = exitCode
    }
    public var stdoutString: String { String(data: stdout, encoding: .utf8) ?? "" }
    public var stderrString: String { String(data: stderr, encoding: .utf8) ?? "" }
    public var succeeded: Bool { exitCode == 0 }
}

public enum SSHError: Error, LocalizedError, Sendable {
    case notConnected
    case timeout
    case cancelled
    case execFailed(code: Int32, message: String)
    case masterExited(String)
    case launchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notConnected: return "服务器未连接"
        case .timeout: return "操作超时"
        case .cancelled: return "操作已取消"
        case .execFailed(let code, let message):
            return "远端命令失败（退出码 \(code)）：\(message)"
        case .masterExited(let message): return "连接已断开：\(message)"
        case .launchFailed(let message): return "无法启动 ssh 进程：\(message)"
        }
    }
}