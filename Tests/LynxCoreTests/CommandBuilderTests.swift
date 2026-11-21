import XCTest
@testable import LynxCore

final class CommandBuilderTests: XCTestCase {

    func makeServer(auth: AuthMethod) -> ServerHost {
        ServerHost(name: "web", host: "1.2.3.4", port: 2222, user: "deploy",
                   auth: auth, keyPath: "~/.ssh/id_ed25519", jump: "bastion:22")
    }

    func testSocketPathShort() {
        let id = UUID()
        let path = SSHCommandBuilder.socketPath(for: id, tempDirectory: "/var/folders/ab/cdefghijklmnopqrstuvwxyz0123456789/T/")
        XCTAssertLessThan(path.utf8.count, 104) // sun_path 上限
        XCTAssertTrue(path.hasSuffix(".sock"))
        XCTAssertTrue(path.contains("lynx-"))
    }

    func testMasterArgsKey() {
        let b = SSHCommandBuilder(server: makeServer(auth: .key), socketPath: "/tmp/x.sock")
        let args = b.masterArgs(hostKeyPolicy: .acceptNew)
        XCTAssertTrue(args.contains("-N"))
        XCTAssertTrue(args.contains("-M"))
        XCTAssertTrue(args.contains("StrictHostKeyChecking=accept-new"))
        XCTAssertTrue(args.contains("IdentitiesOnly=yes"))
        XCTAssertTrue(args.contains("-i"))
        XCTAssertTrue(args.contains(PathUtils.expandTilde("~/.ssh/id_ed25519")))
        XCTAssertTrue(args.contains("-J"))
        XCTAssertTrue(args.contains("bastion:22"))
        XCTAssertTrue(args.contains("2222"))
        XCTAssertEqual(args.last, "1.2.3.4")
    }

    func testMasterArgsPassword() {
        let b = SSHCommandBuilder(server: makeServer(auth: .password), socketPath: "/tmp/x.sock")
        let args = b.masterArgs(hostKeyPolicy: .strict)
        XCTAssertTrue(args.contains("StrictHostKeyChecking=yes"))
        XCTAssertTrue(args.contains("PubkeyAuthentication=no"))
        XCTAssertTrue(args.contains("PreferredAuthentications=password,keyboard-interactive"))
        XCTAssertFalse(args.contains("IdentitiesOnly=yes"))
    }

    func testExecArgsNoDoubleDash() {
        let b = SSHCommandBuilder(server: makeServer(auth: .agent), socketPath: "/tmp/x.sock")
        let args = b.execArgs(remoteCommand: "sh -s")
        XCTAssertEqual(args.suffix(2), ["1.2.3.4", "sh -s"])
        XCTAssertFalse(args.contains("--")) // ssh 会把 -- 当远端命令的一部分
        XCTAssertTrue(args.contains("ControlMaster=no"))
    }

    func testForwardSpecs() {
        let server = makeServer(auth: .agent)
        let b = SSHCommandBuilder(server: server, socketPath: "/tmp/x.sock")

        let local = ForwardRule(serverID: server.id, kind: .local, bindHost: "127.0.0.1",
                                bindPort: 8080, destHost: "127.0.0.1", destPort: 80)
        XCTAssertEqual(local.spec, "127.0.0.1:8080:127.0.0.1:80")
        XCTAssertEqual(b.forwardArgs(rule: local, cancel: false),
                       ["-S", "/tmp/x.sock", "-O", "forward", "-L", "127.0.0.1:8080:127.0.0.1:80", "1.2.3.4"])
        XCTAssertEqual(b.forwardArgs(rule: local, cancel: true)[3], "cancel")

        let dynamic = ForwardRule(serverID: server.id, kind: .dynamic, bindPort: 1080)
        XCTAssertEqual(dynamic.spec, "127.0.0.1:1080")
        XCTAssertTrue(b.forwardArgs(rule: dynamic, cancel: false).contains("-D"))

        let remote = ForwardRule(serverID: server.id, kind: .remote, bindPort: 9000,
                                 destHost: "127.0.0.1", destPort: 3000)
        XCTAssertTrue(b.forwardArgs(rule: remote, cancel: false).contains("-R"))
    }

    func testControlArgs() {
        let b = SSHCommandBuilder(server: makeServer(auth: .agent), socketPath: "/tmp/x.sock")
        XCTAssertEqual(b.controlArgs("check"), ["-S", "/tmp/x.sock", "-O", "check", "1.2.3.4"])
        XCTAssertEqual(b.controlArgs("exit"), ["-S", "/tmp/x.sock", "-O", "exit", "1.2.3.4"])
    }

    func testFileStoreRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lynx-test-\(UUID().uuidString)")
        let store = FileStore(fileURL: dir.appendingPathComponent("data.json"))
        var data = PersistedData()
        data.servers = [makeServer(auth: .key)]
        data.groups = [ServerGroup(name: "生产")]
        data.snippets = [Snippet(name: "磁盘", command: "df -h")]
        try store.save(data)
        let loaded = store.load()
        XCTAssertEqual(loaded.servers.count, 1)
        XCTAssertEqual(loaded.servers[0].host, "1.2.3.4")
        XCTAssertEqual(loaded.groups[0].name, "生产")
        XCTAssertEqual(loaded.snippets[0].command, "df -h")
        try? FileManager.default.removeItem(at: dir)
    }

    func testFileStoreCorruptRecovery() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lynx-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("data.json")
        try Data("{broken".utf8).write(to: file)
        let store = FileStore(fileURL: file)
        let loaded = store.load()
        XCTAssertTrue(loaded.servers.isEmpty)
        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertTrue(backups.contains { $0.contains("corrupt-") })
        try? FileManager.default.removeItem(at: dir)
    }
}