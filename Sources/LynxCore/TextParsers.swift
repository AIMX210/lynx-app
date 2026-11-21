import Foundation

// MARK: - 进程表

public enum PSParser {
    /// ps -eo pid,ppid,user,pcpu,pmem,rss,etime,comm
    public static func parse(_ text: String) -> [ProcessRow] {
        var rows: [ProcessRow] = []
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.uppercased().hasPrefix("PID") { continue }
            // 前 7 个字段定长，comm 允许含空格 → 保留剩余部分
            let parts = trimmed.split(separator: " ", maxSplits: 7, omittingEmptySubsequences: true)
            guard parts.count >= 8,
                  let pid = Int32(parts[0]), let ppid = Int32(parts[1]),
                  let cpu = Double(parts[3]), let mem = Double(parts[4]),
                  let rss = UInt64(parts[5]) else { continue }
            rows.append(ProcessRow(pid: pid, ppid: ppid, user: String(parts[2]),
                                   cpu: cpu, mem: mem, rssKB: rss,
                                   time: String(parts[6]), command: String(parts[7])))
        }
        return rows
    }
}

// MARK: - Docker

public enum DockerParser {
    public static func parse(_ text: String) -> DockerOverview {
        if text.contains("NO_DOCKER") { return DockerOverview(available: false) }

        var section = ""
        var containers: [DockerContainer] = []
        var stats: [String: [String]] = [:]
        var images: [DockerImage] = []
        var overview = DockerOverview(available: true)

        for line in text.split(separator: "\n") {
            let l = String(line)
            if l.hasPrefix("---") {
                section = l
                continue
            }
            let f = l.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            switch section {
            case "---CONTAINERS---":
                guard f.count >= 6 else { continue }
                containers.append(DockerContainer(id: f[0], name: f[1], image: f[2],
                                                  state: f[3], status: f[4], ports: f[5]))
            case "---STATS---":
                guard f.count >= 6 else { continue }
                stats[f[0]] = Array(f.dropFirst())
            case "---IMAGES---":
                guard f.count >= 4 else { continue }
                images.append(DockerImage(id: f[0], tag: f[1], size: f[2], created: f[3]))
            case "---INFO---":
                guard f.count >= 4 else { continue }
                overview.serverVersion = f[0]
                overview.running = Int(f[1]) ?? 0
                overview.stopped = Int(f[2]) ?? 0
                overview.imageCount = Int(f[3]) ?? 0
            default: break
            }
        }

        for i in containers.indices {
            if let s = stats[containers[i].name], s.count >= 5 {
                containers[i].cpu = Double(s[0].replacingOccurrences(of: "%", with: ""))
                containers[i].memUsage = s[1]
                containers[i].memPerc = s[2]
                containers[i].netIO = s[3]
                containers[i].blockIO = s[4]
            }
        }
        overview.containers = containers
        overview.images = images
        return overview
    }
}

// MARK: - 目录列表

public enum LSParser {
    /// GNU: perms links owner group size epoch name
    /// BSD: perms links owner group size month day time/year name
    public static func parse(_ text: String, gnu: Bool) -> [RemoteFile] {
        var files: [RemoteFile] = []
        for line in text.split(separator: "\n") {
            let l = String(line)
            if l.hasPrefix("total ") || l.hasPrefix("PWD ") || l.hasPrefix("MODE ") { continue }
            guard let first = l.first, "dl-".contains(first) || first == "d" || first == "l" || first == "-" else { continue }

            let maxSplits = gnu ? 6 : 8
            let parts = l.split(separator: " ", maxSplits: maxSplits, omittingEmptySubsequences: true)
            guard parts.count >= maxSplits + 1 else { continue }

            let perms = String(parts[0])
            let isDir = perms.hasPrefix("d")
            let isLink = perms.hasPrefix("l")
            guard let size = UInt64(parts[4]) else { continue }
            let owner = String(parts[2])
            let group = String(parts[3])

            var mtime: Date?
            if gnu, let epoch = TimeInterval(parts[5]) {
                mtime = Date(timeIntervalSince1970: epoch)
            }

            var name = String(parts[maxSplits])
            var linkTarget: String?
            if isLink, let range = name.range(of: " -> ") {
                linkTarget = String(name[range.upperBound...])
                name = String(name[..<range.lowerBound])
            }
            if name == "." || name == ".." { continue }

            files.append(RemoteFile(name: name, isDir: isDir, isLink: isLink,
                                    linkTarget: linkTarget, size: size, mtime: mtime,
                                    permissions: perms, owner: owner, group: group))
        }
        return files
    }

    /// 从 listDirectory 脚本输出中提取 (pwd, mode, files)
    public static func parseListing(_ text: String) -> (path: String?, files: [RemoteFile]) {
        var path: String?
        var gnu = true
        for line in text.split(separator: "\n") {
            if line.hasPrefix("PWD ") { path = String(line.dropFirst(4)) }
            if line.hasPrefix("MODE bsd") { gnu = false }
        }
        if text.contains("CD_FAIL") { return (nil, []) }
        return (path, parse(text, gnu: gnu))
    }
}