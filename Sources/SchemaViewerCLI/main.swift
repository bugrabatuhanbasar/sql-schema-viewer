import Foundation
import SchemaKit

// MARK: option parsing

struct CLIOptions {
    var dialect: Dialect?
    var output: String?
    var format: String?
    var positional: [String] = []
}

func parseOptions(_ args: [String]) -> CLIOptions {
    var opts = CLIOptions()
    var i = 0
    while i < args.count {
        let a = args[i]
        switch a {
        case "--dialect", "-d":
            i += 1
            if i < args.count, let d = Dialect(rawValue: args[i].lowercased()) { opts.dialect = d }
        case "--output", "-o":
            i += 1
            if i < args.count { opts.output = args[i] }
        case "--format", "-f":
            i += 1
            if i < args.count { opts.format = args[i].lowercased() }
        default:
            opts.positional.append(a)
        }
        i += 1
    }
    return opts
}

// MARK: helpers

func printUsage() {
    let usage = """
    schema-viewer 1.0.0 — Mac SQL Schema Viewer CLI

    Usage:
      schema-viewer inspect <path> [--dialect <dialect>]
        Parse the file and print an analysis summary.

      schema-viewer check <path> [--dialect <dialect>]
        Run schema-quality checks and print warnings. Exits 1 if any
        warnings surface, 2 if the parser reports errors.

      schema-viewer render <path> --output <file> [--format svg|png|pdf]
        Render the diagram to a local file. When --format is omitted the
        format is inferred from the output file extension.

      schema-viewer export <path> --format dbml|mermaid|svg|png|pdf [--output <file>]
        Export the parsed schema. dbml and mermaid go to stdout when
        --output is omitted.

      schema-viewer version
      schema-viewer help

    Common options:
      --dialect, -d   postgres | mysql | mariadb | sqlite | oracle | dbml
      --output, -o    Local file path
      --format, -f    Explicit format override

    All processing is local. No network access. No SQL is executed.
    """
    print(usage)
}

func die(_ message: String, code: Int32 = 64) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(code)
}

func loadSchema(path: String, dialect: Dialect?) -> ParseResult<Schema> {
    let url = URL(fileURLWithPath: path)
    do {
        return try SchemaKit.analyzeFile(at: url, dialectOverride: dialect)
    } catch {
        die("failed to read \(path): \(error)", code: 74)
    }
}

func formatFromExtension(_ path: String) -> String? {
    let ext = (path as NSString).pathExtension.lowercased()
    switch ext {
    case "svg": return "svg"
    case "png": return "png"
    case "pdf": return "pdf"
    case "dbml": return "dbml"
    case "mmd", "mermaid": return "mermaid"
    default: return nil
    }
}

func writeOutput(_ data: Data, to path: String) {
    do { try data.write(to: URL(fileURLWithPath: path)) }
    catch { die("failed to write \(path): \(error)", code: 74) }
}

func writeString(_ s: String, to path: String?) {
    if let path { writeOutput(Data(s.utf8), to: path) }
    else { print(s) }
}

// MARK: commands

func cmdInspect(_ opts: CLIOptions) -> Never {
    guard let path = opts.positional.first else { die("inspect requires a path") }
    let result = loadSchema(path: path, dialect: opts.dialect)
    print("File:    \(path)")
    print("Dialect: \(result.value.dialect.displayName)")
    print(result.value.summarySentence)
    let errors = result.value.diagnostics.filter { $0.severity == .error }.count
    let warnings = result.value.diagnostics.filter { $0.severity == .warning }.count
    if warnings > 0 { print("Warnings: \(warnings)") }
    if errors > 0 { print("Errors:   \(errors)") }
    exit(errors == 0 ? 0 : 2)
}

func cmdCheck(_ opts: CLIOptions) -> Never {
    guard let path = opts.positional.first else { die("check requires a path") }
    let result = loadSchema(path: path, dialect: opts.dialect)
    let warnings = result.value.diagnostics.filter { $0.severity == .warning || $0.severity == .error }
    if warnings.isEmpty {
        print("No warnings.")
        exit(0)
    }
    for d in warnings {
        let loc = d.source.startLine > 0 ? " (line \(d.source.startLine))" : ""
        print("[\(d.severity.rawValue)][\(d.code)] \(d.message)\(loc)")
    }
    let hasError = warnings.contains { $0.severity == .error }
    exit(hasError ? 2 : 1)
}

func cmdRender(_ opts: CLIOptions) -> Never {
    guard let path = opts.positional.first else { die("render requires a path") }
    guard let out = opts.output else { die("render requires --output") }
    let format = opts.format ?? formatFromExtension(out) ?? "svg"
    let result = loadSchema(path: path, dialect: opts.dialect)
    switch format {
    case "svg":
        writeOutput(Data(SchemaKit.svg(from: result.value).utf8), to: out)
    #if canImport(AppKit)
    case "png":
        guard let png = SchemaKit.png(from: result.value) else { die("PNG generation failed", code: 74) }
        writeOutput(png, to: out)
    case "pdf":
        guard let pdf = SchemaKit.pdf(from: result.value) else { die("PDF generation failed", code: 74) }
        writeOutput(pdf, to: out)
    #endif
    default:
        die("unknown format '\(format)'; use svg, png, or pdf")
    }
    print("Wrote \(out)")
    exit(0)
}

func cmdExport(_ opts: CLIOptions) -> Never {
    guard let path = opts.positional.first else { die("export requires a path") }
    guard let fmt = opts.format ?? opts.output.flatMap(formatFromExtension)
    else { die("export requires --format (dbml|mermaid|svg|png|pdf)") }
    let result = loadSchema(path: path, dialect: opts.dialect)
    switch fmt {
    case "dbml":
        writeString(SchemaKit.dbml(from: result.value), to: opts.output)
    case "mermaid":
        writeString(SchemaKit.mermaid(from: result.value), to: opts.output)
    case "svg":
        writeString(SchemaKit.svg(from: result.value), to: opts.output)
    #if canImport(AppKit)
    case "png":
        guard let png = SchemaKit.png(from: result.value) else { die("PNG generation failed", code: 74) }
        guard let out = opts.output else { die("png requires --output") }
        writeOutput(png, to: out)
    case "pdf":
        guard let pdf = SchemaKit.pdf(from: result.value) else { die("PDF generation failed", code: 74) }
        guard let out = opts.output else { die("pdf requires --output") }
        writeOutput(pdf, to: out)
    #endif
    default:
        die("unknown format '\(fmt)'")
    }
    exit(0)
}

// MARK: entrypoint

let args = Array(CommandLine.arguments.dropFirst())
if args.isEmpty || args.contains("--help") || args.contains("-h") || args.first == "help" {
    printUsage()
    exit(args.isEmpty ? 64 : 0)
}

let command = args[0]
let opts = parseOptions(Array(args.dropFirst()))
switch command {
case "inspect":  cmdInspect(opts)
case "check":    cmdCheck(opts)
case "render":   cmdRender(opts)
case "export":   cmdExport(opts)
case "version":  print("schema-viewer 1.0.0"); exit(0)
default:
    die("unknown subcommand '\(command)' — run 'schema-viewer help' for usage")
}
