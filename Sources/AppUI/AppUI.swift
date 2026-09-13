import Foundation
import SchemaKit

#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import AppKit

/// The main three-pane document window: object list on the left, diagram in
/// the center, details on the right, diagnostics along the bottom.
public struct SchemaViewerRootView: SwiftUI.View {
    @ObservedObject var document: SchemaDocument
    @State private var selectedObject: Identifier?
    @State private var searchText: String = ""
    @State private var showOrphansOnly: Bool = false

    public init(document: SchemaDocument) {
        self.document = document
    }

    public var body: some SwiftUI.View {
        NavigationSplitView {
            ObjectListView(
                schema: document.schema,
                search: $searchText,
                showOrphansOnly: $showOrphansOnly,
                selected: $selectedObject
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 340)
        } content: {
            VStack(spacing: 0) {
                DiagramCanvasView(
                    scene: scene,
                    selection: selectedObject,
                    highlights: highlights,
                    onSelect: { selectedObject = $0 }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                DiagnosticsBar(diagnostics: document.diagnostics, summary: document.schema.summarySentence)
            }
            .navigationSplitViewColumnWidth(min: 560, ideal: 900, max: .infinity)
        } detail: {
            DetailsPanel(schema: document.schema, selected: selectedObject)
                .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: 420)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("Dialect", selection: dialectBinding) {
                    Text("Auto").tag(Dialect?.none)
                    ForEach(Dialect.allCases.filter { $0 != .unknown }, id: \.self) { d in
                        Text(d.displayName).tag(Optional(d))
                    }
                }
                .pickerStyle(.menu)
                Button {
                    document.analyze()
                } label: { Label("Refresh", systemImage: "arrow.clockwise") }
            }
        }
    }

    private var dialectBinding: Binding<Dialect?> {
        Binding(get: { document.dialectOverride }, set: {
            document.dialectOverride = $0
            document.analyze()
        })
    }

    private var scene: DiagramScene {
        let layout = SchemaKit.layout(document.schema)
        return DiagramRenderer.buildScene(document.schema, layout: layout)
    }

    private var highlights: Set<Identifier> {
        guard let sel = selectedObject, let t = document.schema.tables[sel] else { return [] }
        var out: Set<Identifier> = [sel]
        for fk in t.foreignKeys { out.insert(fk.referencedTable) }
        for (_, other) in document.schema.tables where other.foreignKeys.contains(where: { $0.referencedTable == sel }) {
            out.insert(other.name)
        }
        return out
    }
}

/// Left sidebar: search + filter + object list.
struct ObjectListView: SwiftUI.View {
    let schema: Schema
    @Binding var search: String
    @Binding var showOrphansOnly: Bool
    @Binding var selected: Identifier?

    var body: some SwiftUI.View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                TextField("Search", text: $search)
                    .textFieldStyle(.roundedBorder)
            }.padding(8)
            Toggle("Only tables without FKs", isOn: $showOrphansOnly).padding(.horizontal, 8)
            List(selection: $selected) {
                Section("Tables (\(filteredTables.count))") {
                    ForEach(filteredTables, id: \.self) { name in
                        let table = schema.tables[name]!
                        HStack {
                            Image(systemName: "tablecells")
                            Text(table.name.raw)
                        }.tag(Optional(name))
                    }
                }
                if !schema.views.isEmpty {
                    Section("Views (\(schema.views.count))") {
                        ForEach(sortedNames(schema.views.keys), id: \.self) { name in
                            let v = schema.views[name]!
                            HStack {
                                Image(systemName: v.materialized ? "square.stack.3d.up" : "eye")
                                Text(v.name.raw)
                            }.tag(Optional(name))
                        }
                    }
                }
                if !schema.routines.isEmpty {
                    Section("Routines (\(schema.routines.count))") {
                        ForEach(sortedNames(schema.routines.keys), id: \.self) { name in
                            let r = schema.routines[name]!
                            HStack {
                                Image(systemName: r.kind == .procedure ? "gearshape.2" : "function")
                                Text(r.name.raw)
                            }.tag(Optional(name))
                        }
                    }
                }
                if !schema.triggers.isEmpty {
                    Section("Triggers (\(schema.triggers.count))") {
                        ForEach(sortedNames(schema.triggers.keys), id: \.self) { name in
                            let tr = schema.triggers[name]!
                            HStack {
                                Image(systemName: "bolt")
                                Text(tr.name.raw)
                            }.tag(Optional(name))
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
    }

    private var filteredTables: [Identifier] {
        var arr = Array(schema.tables.values).sorted { $0.name.normalized < $1.name.normalized }
        if !search.isEmpty {
            let q = search.lowercased()
            arr = arr.filter { t in
                t.name.normalized.contains(q) || t.columns.contains { $0.name.normalized.contains(q) }
            }
        }
        if showOrphansOnly {
            let referenced = Set(schema.tables.values.flatMap { $0.foreignKeys.map(\.referencedTable) })
            arr = arr.filter { $0.foreignKeys.isEmpty && !referenced.contains($0.name) }
        }
        return arr.map(\.name)
    }

    private func sortedNames<C: Collection>(_ keys: C) -> [Identifier] where C.Element == Identifier {
        Array(keys).sorted { $0.normalized < $1.normalized }
    }
}

/// Right sidebar: details of the selected object.
struct DetailsPanel: SwiftUI.View {
    let schema: Schema
    let selected: Identifier?

    var body: some SwiftUI.View {
        ScrollView {
            if let selected {
                if let t = schema.tables[selected] {
                    tableDetails(t)
                } else if let v = schema.views[selected] {
                    viewDetails(v)
                } else if let r = schema.routines[selected] {
                    routineDetails(r)
                } else if let tr = schema.triggers[selected] {
                    triggerDetails(tr)
                } else {
                    Text("No details").foregroundStyle(.secondary).padding()
                }
            } else {
                Text("Select an object").foregroundStyle(.secondary).padding()
            }
        }
    }

    private func tableDetails(_ t: SchemaModel.Table) -> some SwiftUI.View {
        VStack(alignment: .leading, spacing: 12) {
            header(t.name.raw, subtitle: "Table")
            section("Columns") {
                ForEach(t.columns, id: \.name) { c in
                    HStack(alignment: .top) {
                        Image(systemName: t.primaryKeyColumns.contains(c.name) ? "key.fill" : "circle")
                            .foregroundStyle(t.primaryKeyColumns.contains(c.name) ? .yellow : .secondary)
                        VStack(alignment: .leading) {
                            Text(c.name.raw).font(.system(.body, design: .monospaced))
                            Text(c.type.displayName).font(.caption).foregroundStyle(.secondary)
                            if !c.nullable { Text("NOT NULL").font(.caption2).foregroundStyle(.orange) }
                        }
                    }
                }
            }
            if !t.foreignKeys.isEmpty {
                section("Foreign Keys") {
                    ForEach(Array(t.foreignKeys.enumerated()), id: \.offset) { _, fk in
                        Text("\(fk.localColumns.map(\.raw).joined(separator: ", ")) → \(fk.referencedTable.raw)(\(fk.referencedColumns.map(\.raw).joined(separator: ", ")))")
                            .font(.system(.caption, design: .monospaced))
                    }
                }
            }
            if !t.indexes.isEmpty {
                section("Indexes") {
                    ForEach(Array(t.indexes.enumerated()), id: \.offset) { _, idx in
                        Text("\(idx.unique ? "UNIQUE " : "")\(idx.name?.raw ?? "(anonymous)") (\(idx.columns.map { $0.column.raw }.joined(separator: ", ")))")
                            .font(.system(.caption, design: .monospaced))
                    }
                }
            }
            sourceInfo(t.source)
        }.padding()
    }

    private func viewDetails(_ v: SchemaModel.View) -> some SwiftUI.View {
        VStack(alignment: .leading, spacing: 12) {
            header(v.name.raw, subtitle: v.materialized ? "Materialized View" : "View")
            section("Definition") {
                Text(v.definitionSQL).font(.system(.caption, design: .monospaced))
            }
            sourceInfo(v.source)
        }.padding()
    }

    private func routineDetails(_ r: Routine) -> some SwiftUI.View {
        VStack(alignment: .leading, spacing: 12) {
            header(r.name.raw, subtitle: r.kind == .procedure ? "Procedure" : "Function")
            section("Body") {
                Text(r.bodySQL).font(.system(.caption, design: .monospaced))
            }
            sourceInfo(r.source)
        }.padding()
    }

    private func triggerDetails(_ t: Trigger) -> some SwiftUI.View {
        VStack(alignment: .leading, spacing: 12) {
            header(t.name.raw, subtitle: "Trigger on \(t.table.raw)")
            section("Body") { Text(t.bodySQL).font(.system(.caption, design: .monospaced)) }
            sourceInfo(t.source)
        }.padding()
    }

    private func header(_ title: String, subtitle: String) -> some SwiftUI.View {
        VStack(alignment: .leading) {
            Text(title).font(.title2).bold()
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some SwiftUI.View) -> some SwiftUI.View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content()
        }
    }

    private func sourceInfo(_ src: SourceRange) -> some SwiftUI.View {
        Group {
            if src.startLine > 0 {
                Text("Line \(src.startLine)").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

/// Bottom: parser diagnostics + one-line summary.
struct DiagnosticsBar: SwiftUI.View {
    let diagnostics: [Diagnostic]
    let summary: String

    var body: some SwiftUI.View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            Text(summary).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 8)
            if !diagnostics.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(Array(diagnostics.prefix(50).enumerated()), id: \.offset) { _, d in
                            HStack(spacing: 4) {
                                Image(systemName: iconFor(d.severity))
                                    .foregroundStyle(colorFor(d.severity))
                                Text("[\(d.code)]").font(.caption2).foregroundStyle(.secondary)
                                Text(d.message).font(.caption2)
                                if d.source.startLine > 0 {
                                    Text("(:\(d.source.startLine))").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }.padding(.horizontal, 8)
                }
            }
        }
        .frame(maxHeight: 90)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func iconFor(_ s: DiagnosticSeverity) -> String {
        switch s {
        case .error: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle"
        }
    }
    private func colorFor(_ s: DiagnosticSeverity) -> Color {
        switch s {
        case .error: return .red
        case .warning: return .orange
        case .info: return .secondary
        }
    }
}

/// Public entrypoint the Xcode app target constructs its DocumentGroup with.
public struct SchemaViewerApp {
    public static func makeScene() -> some Scene {
        DocumentGroup(newDocument: { SchemaDocument() }) { config in
            SchemaViewerRootView(document: config.document)
                .onAppear {
                    if config.document.sourceText.isEmpty == false {
                        config.document.analyze()
                    }
                }
        }
    }
}
#endif
