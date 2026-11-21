import Foundation

/// 本地持久化数据（不含任何机密；密码/口令只存 Keychain）
public struct PersistedData: Codable, Sendable {
    public var version: Int
    public var servers: [ServerHost]
    public var groups: [ServerGroup]
    public var snippets: [Snippet]
    public var rules: [ForwardRule]

    public init(version: Int = 1, servers: [ServerHost] = [], groups: [ServerGroup] = [],
                snippets: [Snippet] = [], rules: [ForwardRule] = []) {
        self.version = version
        self.servers = servers
        self.groups = groups
        self.snippets = snippets
    }
}

public final class FileStore {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() -> PersistedData {
        guard let data = try? Data(contentsOf: fileURL) else { return PersistedData() }
        do {
            return try JSONDecoder().decode(PersistedData.self, from: data)
        } catch {
            // 损坏时保留现场，避免静默丢数据
            let backup = fileURL.deletingPathExtension()
                .appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: fileURL, to: backup)
            return PersistedData()
        }
    }

    public func save(_ data: PersistedData) throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let encoded = try encoder.encode(data)
        try encoded.write(to: fileURL, options: .atomic)
    }

    /// 导入（合并策略：按 id 去重，导入方覆盖同 id）
    public static func merge(base: PersistedData, incoming: PersistedData) -> PersistedData {
        var result = base
        func mergeArray<T: Identifiable>(_ base: [T], _ new: [T]) -> [T] where T.ID: Hashable {
            var map: [T.ID: T] = [:]
            for item in base { map[item.id] = item }
            for item in new { map[item.id] = item }
            return Array(map.values)
        }
        result.servers = mergeArray(base.servers, incoming.servers)
        result.groups = mergeArray(base.groups, incoming.groups)
        result.snippets = mergeArray(base.snippets, incoming.snippets)
        result.rules = mergeArray(base.rules, incoming.rules)
        return result
    }
}