import XCTest
import Foundation
@testable import SchemaKit

/// Verifies at test time that our first-party modules do not import or
/// reference networking APIs. This is a source-level check that runs
/// offline; a stronger CI-level binary audit (`nm | grep`) lives in the
/// verification scripts.
///
/// The check scans every `.swift` file under `Sources/` for banned symbols.
/// Test-only fixtures may reference them in strings — hence the test target
/// itself is not scanned.
final class NetworkGuardTests: XCTestCase {

    static let bannedSymbols: [String] = [
        "URLSession",
        "URLRequest",
        "NSURLConnection",
        "NWConnection",
        "NWListener",
        "NWPathMonitor",
        "CFStreamCreatePairWithSocketToHost",
        "SCNetworkReachability",
        "SocketPort",
        "CFSocket",
    ]

    func testFirstPartySourcesDoNotReferenceNetworkingAPIs() throws {
        let sourcesDir = try Self.locateSourcesDirectory()
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: sourcesDir, includingPropertiesForKeys: nil) else {
            XCTFail("could not enumerate \(sourcesDir.path)"); return
        }
        var violations: [String] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "swift" else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            for symbol in Self.bannedSymbols where text.contains(symbol) {
                violations.append("\(url.lastPathComponent): references banned symbol \(symbol)")
            }
        }
        XCTAssertTrue(violations.isEmpty, "Banned networking symbols found in first-party sources:\n" + violations.joined(separator: "\n"))
    }

    func testSchemaKitFacadeExists() {
        // Guards that SchemaKit compiled and is reachable — a smoke check
        // paired with the source scan above.
        let empty = SchemaKit.mermaid(from: Schema())
        XCTAssertTrue(empty.hasPrefix("erDiagram"))
    }

    // MARK: helpers

    /// Walks up from the test bundle location to find the repository's
    /// Sources/ directory. Works both in `swift test` and Xcode runs.
    private static func locateSourcesDirectory() throws -> URL {
        // #filePath points at this test file; the repo root is three levels up.
        let thisFile = URL(fileURLWithPath: #filePath)
        let root = thisFile
            .deletingLastPathComponent() // NetworkGuardTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
        let sources = root.appendingPathComponent("Sources", isDirectory: true)
        guard FileManager.default.fileExists(atPath: sources.path) else {
            throw NSError(domain: "NetworkGuard", code: 1, userInfo: [NSLocalizedDescriptionKey: "Sources dir not found at \(sources.path)"])
        }
        return sources
    }
}
