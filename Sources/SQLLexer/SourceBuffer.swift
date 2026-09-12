import Foundation
import SchemaModel

/// A UTF-8 backed source buffer that tracks byte offsets and 1-based
/// line/column positions. All lexer positions are byte-accurate so that
/// SourceRange values remain stable across editors.
public struct SourceBuffer: Sendable {
    public let file: URL?
    public let bytes: [UInt8]

    public init(_ text: String, file: URL? = nil) {
        self.file = file
        self.bytes = Array(text.utf8)
    }

    public init(bytes: [UInt8], file: URL? = nil) {
        self.file = file
        self.bytes = bytes
    }

    public var count: Int { bytes.count }

    /// Compute 1-based (line, column) for a byte offset by scanning newlines
    /// from the buffer start. O(n) — callers that need many lookups should
    /// use `LineIndex`.
    public func position(atByteOffset offset: Int) -> (line: Int, column: Int) {
        var line = 1
        var col = 1
        let end = min(offset, bytes.count)
        var i = 0
        while i < end {
            if bytes[i] == 0x0A {
                line += 1
                col = 1
            } else {
                col += 1
            }
            i += 1
        }
        return (line, col)
    }
}

/// Precomputed newline offsets for fast (line, column) lookups.
public struct LineIndex: Sendable {
    public let lineStarts: [Int]

    public init(_ buffer: SourceBuffer) {
        var starts: [Int] = [0]
        for (i, b) in buffer.bytes.enumerated() where b == 0x0A {
            starts.append(i + 1)
        }
        self.lineStarts = starts
    }

    public func position(atByteOffset offset: Int) -> (line: Int, column: Int) {
        // Binary search
        var lo = 0
        var hi = lineStarts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) >> 1
            if lineStarts[mid] <= offset { lo = mid } else { hi = mid - 1 }
        }
        return (lo + 1, offset - lineStarts[lo] + 1)
    }
}
