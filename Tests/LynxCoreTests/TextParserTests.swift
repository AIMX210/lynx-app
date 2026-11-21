import XCTest
@testable import LynxCore

final class TextParserTests: XCTestCase {

    func testPSParser() {
        let text = """
          PID  PPID USER      %CPU %MEM   RSS     ELAPSED COMMAND
         1866     1 deploy    10.8  2.1 366592  3-04:05:06 swiftserver-web
         1903     1 deploy     9.8  2.6 443392       05:06 nginx: worker process
            1     0 root       0.0  0.1  10240  100-00:00:00 systemd
        """
        let rows = PSParser.parse(text)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].pid, 1866)
        XCTAssertEqual(rows[0].cpu, 10.8)
        XCTAssertEqual(rows[0].rssKB, 366592)
        XCTAssertEqual(rows[0].command, "swiftserver-web")
        XCTAssertEqual(rows[1].command, "nginx: worker process") // comm 含空格
        XCTAssertEqual(rows[2].ppid, 0)
    }

    func testDockerParser() {
        let text = """
        ---CONTAINERS---
        abc123|web|nginx:latest|running|Up 2 hours|0.0.0.0:80->80/tcp
        def456|db|postgres:16|exited|Exited (0) 3 days ago|
        ---STATS---
        web|1.25%|50MiB / 1GiB|4.88%|1MB / 2MB|0B / 0B
        ---IMAGES---
        img1|nginx:latest|187MB|2 weeks ago
        ---INFO---
        27.3.1|1|1|5
        ---END---
        """
        let o = DockerParser.parse(text)
        XCTAssertTrue(o.available)
        XCTAssertEqual(o.containers.count, 2)
        XCTAssertEqual(o.containers[0].cpu, 1.25)
        XCTAssertEqual(o.containers[0].memUsage, "50MiB / 1GiB")
        XCTAssertTrue(o.containers[0].isRunning)
        XCTAssertFalse(o.containers[1].isRunning)
        XCTAssertNil(o.containers[1].cpu)
        XCTAssertEqual(o.images.count, 1)
        XCTAssertEqual(o.serverVersion, "27.3.1")
        XCTAssertEqual(o.running, 1)
        XCTAssertEqual(o.stopped, 1)
    }

    func testDockerUnavailable() {
        let o = DockerParser.parse("NO_DOCKER\n")
        XCTAssertFalse(o.available)
    }

    func testLSParserGNU() {
        let text = """
        PWD /var/www
        MODE gnu
        total 24
        drwxr-xr-x 2 root root 4096 1700000000 html
        -rw-r--r-- 1 root root 1234 1700000100 index.html
        lrwxrwxrwx 1 root root    9 1700000200 link -> html/a.txt
        -rw------- 1 deploy deploy 0 1700000300 my file.txt
        """
        let (path, files) = LSParser.parseListing(text)
        XCTAssertEqual(path, "/var/www")
        XCTAssertEqual(files.count, 4)
        XCTAssertTrue(files[0].isDir)
        XCTAssertEqual(files[1].size, 1234)
        XCTAssertEqual(files[1].mtime, Date(timeIntervalSince1970: 1700000100))
        XCTAssertTrue(files[2].isLink)
        XCTAssertEqual(files[2].name, "link")
        XCTAssertEqual(files[2].linkTarget, "html/a.txt")
        XCTAssertEqual(files[3].name, "my file.txt") // 文件名含空格
        XCTAssertEqual(files[3].owner, "deploy")
    }

    func testLSParserBSD() {
        let text = """
        PWD /Users/me
        MODE bsd
        total 8
        drwxr-xr-x   3 me  staff    96 Nov 20 10:00 Documents
        -rw-r--r--   1 me  staff  1024 Nov 19 09:30 notes.txt
        """
        let (_, files) = LSParser.parseListing(text)
        XCTAssertEqual(files.count, 2)
        XCTAssertTrue(files[0].isDir)
        XCTAssertEqual(files[1].size, 1024)
        XCTAssertEqual(files[1].name, "notes.txt")
    }

    func testLSFail() {
        let (path, files) = LSParser.parseListing("CD_FAIL\n")
        XCTAssertNil(path)
        XCTAssertTrue(files.isEmpty)
    }

    func testShellQuote() {
        XCTAssertEqual(ShellQuote.quote("plain"), "'plain'")
        XCTAssertEqual(ShellQuote.quote("a b"), "'a b'")
        XCTAssertEqual(ShellQuote.quote("it's"), "'it'\\''s'")
        XCTAssertEqual(ShellQuote.quote("$(rm -rf /)"), "'$(rm -rf /)'")
    }

    func testPathUtils() {
        XCTAssertEqual(PathUtils.join("/", "etc"), "/etc")
        XCTAssertEqual(PathUtils.join("/var/", "log"), "/var/log")
        XCTAssertEqual(PathUtils.join("/var", "log"), "/var/log")
        XCTAssertEqual(PathUtils.parent("/var/log"), "/var")
        XCTAssertEqual(PathUtils.parent("/"), "/")
        XCTAssertEqual(PathUtils.displayName("/var/log"), "log")
    }
}