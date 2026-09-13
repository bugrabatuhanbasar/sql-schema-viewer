import XCTest
import Foundation

/// End-to-end tests that shell out to the built `schema-viewer` binary.
/// Skipped when the binary hasn't been built yet (fresh clone before
/// `swift build`).
final class CLIIntegrationTests: XCTestCase {

    private var binaryURL: URL? {
        let root = Self.repoRoot()
        for config in ["debug", "release"] {
            let url = root.appendingPathComponent(".build/\(config)/schema-viewer")
            if FileManager.default.isExecutableFile(atPath: url.path) { return url }
        }
        return nil
    }

    private func fixture() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("schema-viewer-cli-\(UUID().uuidString).sql")
        try """
        CREATE TABLE users (
          id BIGSERIAL PRIMARY KEY,
          email TEXT NOT NULL UNIQUE
        );
        CREATE TABLE posts (
          id BIGSERIAL PRIMARY KEY,
          user_id BIGINT REFERENCES users(id),
          title TEXT NOT NULL
        );
        """.write(to: tmp, atomically: true, encoding: .utf8)
        return tmp
    }

    private func run(_ args: [String]) throws -> (exit: Int32, stdout: String, stderr: String) {
        guard let bin = binaryURL else {
            throw XCTSkip("schema-viewer binary not built yet")
        }
        let proc = Process()
        proc.executableURL = bin
        proc.arguments = args
        let outPipe = Pipe(), errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        try proc.run()
        proc.waitUntilExit()
        let out = String(decoding: outPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        let err = String(decoding: errPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        return (proc.terminationStatus, out, err)
    }

    func testInspectSummary() throws {
        let path = try fixture()
        let (code, out, _) = try run(["inspect", path.path])
        XCTAssertEqual(code, 0)
        XCTAssertTrue(out.contains("Found 2 tables"))
        XCTAssertTrue(out.contains("PostgreSQL"))
    }

    func testCheckFlagsUnindexedFK() throws {
        let path = try fixture()
        let (code, out, _) = try run(["check", path.path])
        XCTAssertEqual(code, 1) // warnings present
        XCTAssertTrue(out.contains("W0012"))
    }

    func testRenderSVG() throws {
        let path = try fixture()
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("out-\(UUID().uuidString).svg")
        let (code, _, _) = try run(["render", path.path, "--output", out.path])
        XCTAssertEqual(code, 0)
        let data = try Data(contentsOf: out)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("<svg"))
    }

    func testExportMermaid() throws {
        let path = try fixture()
        let (code, out, _) = try run(["export", path.path, "--format", "mermaid"])
        XCTAssertEqual(code, 0)
        XCTAssertTrue(out.hasPrefix("erDiagram"))
    }

    private static func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // CLIIntegrationTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
    }
}
