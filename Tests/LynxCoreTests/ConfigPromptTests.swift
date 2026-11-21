import XCTest
@testable import LynxCore

final class ConfigPromptTests: XCTestCase {

    func testSSHConfigParse() {
        let config = """
        # 全局
        Host *
            ServerAliveInterval 60

        Host web-01
            HostName 10.0.0.5
            User deploy
            Port 2222
            IdentityFile ~/.ssh/id_ed25519
            ProxyJump bastion

        Host db web-02
            HostName db.internal
            User=root

        Host *.internal
            User admin
        """
        let hosts = SSHConfigParser.parse(config)
        XCTAssertEqual(hosts.count, 3) // web-01, db, web-02；通配符被跳过
        let web = hosts.first { $0.pattern == "web-01" }
        XCTAssertEqual(web?.hostName, "10.0.0.5")
        XCTAssertEqual(web?.user, "deploy")
        XCTAssertEqual(web?.port, 2222)
        XCTAssertEqual(web?.identityFile, PathUtils.expandTilde("~/.ssh/id_ed25519"))
        XCTAssertEqual(web?.proxyJump, "bastion")
        let db = hosts.first { $0.pattern == "db" }
        XCTAssertEqual(db?.user, "root") // key=value 形式
    }

    func testPromptPassword() {
        XCTAssertEqual(PromptDetector.detect(in: "deploy@1.2.3.4's password: "), .password)
        XCTAssertEqual(PromptDetector.detect(in: "Password:"), .password)
        XCTAssertEqual(PromptDetector.detect(in: "Enter passphrase for key '/Users/me/.ssh/id_ed25519': "), .passphrase)
    }

    func testPromptHostKey() {
        let text = """
        The authenticity of host '1.2.3.4 (1.2.3.4)' can't be established.
        ED25519 key fingerprint is SHA256:abcDEF123.
        Are you sure you want to continue connecting (yes/no/[fingerprint])?
        """
        if case .hostKeyConfirm(let fp)? = PromptDetector.detect(in: text) {
            XCTAssertTrue(fp.contains("SHA256:abcDEF123"))
        } else {
            XCTFail("应识别主机密钥确认")
        }
    }

    func testPromptInteractive() {
        XCTAssertEqual(PromptDetector.detect(in: "Verification code: "), .interactive(prompt: "Verification code:"))
    }

    func testPromptErrors() {
        XCTAssertEqual(PromptDetector.detect(in: "Permission denied (publickey,password)."), .authFailed)
        XCTAssertEqual(PromptDetector.detect(in: "Host key verification failed."), .hostKeyChanged)
        XCTAssertEqual(PromptDetector.detect(in: "ssh: connect to host 1.2.3.4 port 22: Connection refused"), .networkError("连接被拒绝"))
        XCTAssertEqual(PromptDetector.detect(in: "ssh: Could not resolve hostname foo: Name or service not known"), .networkError("无法解析主机名"))
    }

    func testPromptBannerIgnored() {
        XCTAssertNil(PromptDetector.detect(in: "Welcome to Ubuntu 22.04 LTS\nLast login: Fri Nov 20 10:00:00 2026"))
        XCTAssertNil(PromptDetector.detect(in: ""))
    }

    func testPromptCRLF() {
        XCTAssertEqual(PromptDetector.detect(in: "root@host's password:\r\n"), .password)
    }
}