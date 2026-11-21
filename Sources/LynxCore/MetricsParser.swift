import Foundation

/// 解析 RemoteScripts.metrics 的行协议输出为原始计数器。
/// 设计原则：shell 端只做采集、不做计算与 JSON 转义，所有数值逻辑在 Swift 端，可单测。
public enum MetricsParser {

    public static func parse(_ text: String) -> RawMetrics? {
        var raw = RawMetrics()
        var sawHeader = false
        var sawEnd = false

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard let tag = parts.first else { continue }
            let rest = Array(parts.dropFirst())

            switch tag {
            case "LYNX":
                sawHeader = true
                raw.isDarwin = false
            case "HOST": raw.host = rest.joined(separator: " ")
            case "OS": raw.os = rest.joined(separator: " ")
            case "KERNEL": raw.kernel = rest.joined(separator: " ")
            case "ARCH": raw.arch = rest.joined(separator: " ")
            case "UPTIME": raw.uptime = Double(rest.first ?? "") ?? 0
            case "CORES": raw.cores = Int(rest.first ?? "") ?? 0
            case "LOAD":
                raw.load = rest.prefix(3).compactMap(Double.init)
                if rest.count > 3 { raw.loadProcs = rest[3] }
            case "CPU":
                let v = rest.compactMap(UInt64.init)
                if v.count >= 4 { raw.cpuJiffies = Array(v.prefix(8)) }
            case "CPUP":
                let v = rest.compactMap(Double.init)
                if v.count >= 3 {
                    raw.cpuPercent = (v[0], v[1], v[2])
                    raw.isDarwin = true
                }
            case "CORE":
                let v = rest.dropFirst().compactMap(UInt64.init)
                if v.count >= 4 { raw.perCoreJiffies.append(Array(v.prefix(8))) }
            case "MEM":
                let v = rest.compactMap(UInt64.init)
                if v.count >= 8 {
                    raw.mem = MemInfo(totalKB: v[0], freeKB: v[1], availableKB: v[2],
                                      buffersKB: v[3], cachedKB: v[4], reclaimableKB: v[5],
                                      swapTotalKB: v[6], swapFreeKB: v[7])
                }
            case "SWAP":
                let v = rest.compactMap(Double.init)
                if v.count >= 2 {
                    var m = raw.mem ?? MemInfo()
                    m.swapTotalKB = UInt64(max(0, v[0]))
                    m.swapFreeKB = UInt64(max(0, v[1]))
                    raw.mem = m
                }
            case "NET":
                if rest.count >= 3, let rx = UInt64(rest[1]), let tx = UInt64(rest[2]) {
                    raw.nets.append((name: rest[0], rx: rx, tx: tx))
                }
            case "DISK":
                if rest.count >= 9 {
                    let counters = rest.dropFirst().prefix(8).compactMap(UInt64.init)
                    if counters.count == 8 {
                        raw.disks.append((device: rest[0], counters: counters))
                    }
                }
            case "FS":
                // FS <mount...> <usedKB> <totalKB>：挂载点可能含空格，取末尾两个数字
                if rest.count >= 3,
                   let used = UInt64(rest[rest.count - 2]),
                   let total = UInt64(rest[rest.count - 1]) {
                    let mount = rest.prefix(rest.count - 2).joined(separator: " ")
                    raw.fs.append(FSUsage(mount: mount, usedBytes: used &* 1024, totalBytes: total &* 1024))
                }
            case "TCP": raw.tcpEstablished = Int(rest.first ?? "")
            case "TEMP":
                if let milli = Double(rest.first ?? "") { raw.tempC = milli / 1000.0 }
            case "GPU":
                // GPU idx|name|util|memUsed|memTotal|temp|power
                let payload = rest.joined(separator: " ")
                let f = payload.split(separator: "|", omittingEmptySubsequences: false).map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                if f.count >= 5, let idx = Int(f[0]) {
                    raw.gpus.append(GPUInfo(
                        index: idx, name: f[1],
                        utilization: Double(f[2]) ?? 0,
                        memUsedMB: Double(f[3]) ?? 0,
                        memTotalMB: Double(f[4]) ?? 0,
                        tempC: f.count > 5 ? Double(f[5]) : nil,
                        powerW: f.count > 6 ? Double(f[6]) : nil))
                }
            case "END": sawEnd = true
            default: break
            }
        }

        guard sawHeader && sawEnd else { return nil }
        return raw
    }
}

/// 两次原始采样做差分，得到速率与 CPU 占用。每服务器一个实例，保存上次基准。
public final class MetricsCalculator {
    private var previous: RawMetrics?
    private var previousDate: Date?

    public init() {}

    public func reset() {
        previous = nil
        previousDate = nil
    }

    public func next(_ raw: RawMetrics, at date: Date = Date()) -> MetricsSnapshot {
        defer {
            previous = raw
            previousDate = date
        }
        guard let prev = previous, let prevDate = previousDate else {
            return MetricsSnapshot(timestamp: date, raw: raw, cpu: nil,
                                   nets: raw.nets.map { NetInterface(name: $0.name, rxBps: 0, txBps: 0, rxTotal: $0.rx, txTotal: $0.tx) },
                                   disks: raw.disks.map { DiskIO(device: $0.device, readBps: 0, writeBps: 0, readIOPS: 0, writeIOPS: 0) })
        }

        let dt = date.timeIntervalSince(prevDate)
        guard dt > 0.05 else {
            return MetricsSnapshot(timestamp: date, raw: raw, cpu: nil,
                                   nets: raw.nets.map { NetInterface(name: $0.name, rxBps: 0, txBps: 0, rxTotal: $0.rx, txTotal: $0.tx) },
                                   disks: raw.disks.map { DiskIO(device: $0.device, readBps: 0, writeBps: 0, readIOPS: 0, writeIOPS: 0) })
        }

        // CPU
        var cpu: CPUUsage?
        if let p = raw.cpuPercent {
            cpu = CPUUsage(total: min(100, p.user + p.system), user: p.user, system: p.system)
        } else if let cur = raw.cpuJiffies, let old = prev.cpuJiffies, cur.count >= 4, old.count >= 4 {
            cpu = Self.cpuUsage(current: cur, previous: old)
            if !raw.perCoreJiffies.isEmpty && raw.perCoreJiffies.count == prev.perCoreJiffies.count {
                cpu?.perCore = zip(raw.perCoreJiffies, prev.perCoreJiffies).compactMap { c, o in
                    Self.cpuUsage(current: c, previous: o)?.total
                }
            }
        }

        // 网络
        var prevNet: [String: (UInt64, UInt64)] = [:]
        for n in prev.nets { prevNet[n.name] = (n.rx, n.tx) }
        let nets = raw.nets.map { n -> NetInterface in
            var rxRate = 0.0, txRate = 0.0
            if let o = prevNet[n.name] {
                rxRate = Double(n.rx >= o.0 ? n.rx - o.0 : 0) / dt
                txRate = Double(n.tx >= o.1 ? n.tx - o.1 : 0) / dt
            }
            return NetInterface(name: n.name, rxBps: rxRate, txBps: txRate, rxTotal: n.rx, txTotal: n.tx)
        }

        // 磁盘（扇区固定 512 字节，与内核统计口径一致）
        var prevDisk: [String: [UInt64]] = [:]
        for d in prev.disks { prevDisk[d.device] = d.counters }
        let disks = raw.disks.map { d -> DiskIO in
            var rBps = 0.0, wBps = 0.0, rIOPS = 0.0, wIOPS = 0.0
            if let o = prevDisk[d.device], o.count == 8, d.counters.count == 8 {
                let dReads = d.counters[0] >= o[0] ? d.counters[0] - o[0] : 0
                let dSectorsR = d.counters[2] >= o[2] ? d.counters[2] - o[2] : 0
                let dWrites = d.counters[4] >= o[4] ? d.counters[4] - o[4] : 0
                let dSectorsW = d.counters[6] >= o[6] ? d.counters[6] - o[6] : 0
                rBps = Double(dSectorsR) * 512 / dt
                wBps = Double(dSectorsW) * 512 / dt
                rIOPS = Double(dReads) / dt
                wIOPS = Double(dWrites) / dt
            }
            return DiskIO(device: d.device, readBps: rBps, writeBps: wBps, readIOPS: rIOPS, writeIOPS: wIOPS)
        }

        return MetricsSnapshot(timestamp: date, raw: raw, cpu: cpu, nets: nets, disks: disks)
    }

    /// busy = total - idle - iowait
    static func cpuUsage(current: [UInt64], previous: [UInt64]) -> CPUUsage? {
        guard current.count >= 4, previous.count >= 4, current.count == previous.count else { return nil }
        let deltas = zip(current, previous).map { c, o in c >= o ? c - o : 0 }
        let total = deltas.reduce(0, +)
        guard total > 0 else { return CPUUsage(total: 0) }
        let idle = deltas[3] + (deltas.count > 4 ? deltas[4] : 0)
        let busy = total > idle ? total - idle : 0
        let user = deltas[0] + (deltas.count > 1 ? deltas[1] : 0)
        let system = deltas[2] + (deltas.count > 5 ? deltas[5] + deltas[6] : 0)
        let iowait = deltas.count > 4 ? deltas[4] : 0
        let t = Double(total)
        return CPUUsage(total: Double(busy) / t * 100,
                        user: Double(user) / t * 100,
                        system: Double(system) / t * 100,
                        iowait: Double(iowait) / t * 100)
    }
}