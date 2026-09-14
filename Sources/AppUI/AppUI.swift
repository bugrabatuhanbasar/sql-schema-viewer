import Foundation
import SchemaKit

#if canImport(SwiftUI) && canImport(AppKit)
import SwiftUI
import AppKit

/// The main three-pane document window: object list on the left, diagram in
/// the center, details on the right, diagnostics along the bottom.
public struct SchemaViewerRootView: SwiftUI.View {
    @ObservedObject var document: SchemaDocument
    @State private var selectedObjects: Set<Identifier> = []
    @State private var searchText: String = ""
    @State private var showOrphansOnly: Bool = false
    /// Bumped every time the user hits "Reset Layout" — the diagram
    /// canvas watches this counter and snaps its drag offsets back to
    /// the layout engine's positions on every change.
    @State private var resetLayoutCounter: Int = 0
    /// Preserved across document sessions via UserDefaults so the app
    /// remembers whether the user prefers curved or orthogonal edges.
    @AppStorage("com.macsqlschemaviewer.edgeRouting")
    private var edgeRoutingRaw: String = EdgeRouting.orthogonal.rawValue

    public init(document: SchemaDocument) {
        self.document = document
    }

    /// A single-item view onto `selectedObjects` for the sidebar (which
    /// uses SwiftUI's `List(selection:)` with single-select semantics).
    /// Writing to it replaces the whole multi-selection with that one row;
    /// setting it to `nil` clears the selection.
    private var sidebarSelectionBinding: Binding<Identifier?> {
        Binding(
            get: { selectedObjects.count == 1 ? selectedObjects.first : nil },
            set: { new in
                if let new { selectedObjects = [new] }
                else { selectedObjects.removeAll() }
            }
        )
    }

    public var body: some SwiftUI.View {
        NavigationSplitView {
            ObjectListView(
                schema: document.schema,
                search: $searchText,
                showOrphansOnly: $showOrphansOnly,
                selected: sidebarSelectionBinding
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 340)
        } content: {
            VStack(spacing: 0) {
                DiagramCanvasView(
                    scene: scene,
                    selection: selectedObjects,
                    highlights: highlights,
                    resetTrigger: resetLayoutCounter,
                    onSelectionChanged: { selectedObjects = $0 }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                DiagnosticsBar(diagnostics: document.diagnostics, summary: document.schema.summarySentence)
            }
            .navigationSplitViewColumnWidth(min: 560, ideal: 900, max: .infinity)
        } detail: {
            DetailsPanel(schema: document.schema, selection: selectedObjects)
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
                Picker("Edge routing", selection: Binding(
                    get: { currentRouting },
                    set: { edgeRoutingRaw = $0.rawValue }
                )) {
                    Text("Curved").tag(EdgeRouting.curved)
                    Text("Orthogonal").tag(EdgeRouting.orthogonal)
                }
                .pickerStyle(.segmented)
                .help("Edge routing style — curved bezier vs. right-angle ERD-style")
                Button {
                    selectedObjects = Set(document.schema.tables.keys)
                } label: { Label("Select All Tables", systemImage: "square.stack.3d.up") }
                Button {
                    selectedObjects.removeAll()
                } label: { Label("Deselect", systemImage: "xmark.circle") }
                .disabled(selectedObjects.isEmpty)
                Button {
                    resetLayoutCounter &+= 1
                } label: { Label("Reset Layout", systemImage: "arrow.uturn.backward.circle") }
                .help("Undo every table drag and snap them back to the layout engine's positions")
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

    private var currentRouting: EdgeRouting {
        EdgeRouting(rawValue: edgeRoutingRaw) ?? .orthogonal
    }

    private var scene: DiagramScene {
        let layout = SchemaKit.layout(document.schema)
        return DiagramRenderer.buildScene(
            document.schema,
            layout: layout,
            routing: currentRouting
        )
    }

    /// The full "related" set for the selection: every selected table + all
    /// tables it references (out-edges) + all tables that reference it
    /// (in-edges). Used to tint neighbour nodes so the picked slice of the
    /// diagram stands out.
    private var highlights: Set<Identifier> {
        var out: Set<Identifier> = selectedObjects
        for sel in selectedObjects {
            guard let t = document.schema.tables[sel] else { continue }
            for fk in t.foreignKeys { out.insert(fk.referencedTable) }
        }
        for (_, other) in document.schema.tables {
            if other.foreignKeys.contains(where: { selectedObjects.contains($0.referencedTable) }) {
                out.insert(other.name)
            }
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

/// Right sidebar: details of the selection. A single selected object gets
/// its full detail card; a multi-selection collapses into a summary card
/// with counts (columns / FKs / indexes / relationships) across the picked
/// tables — useful when you're dragging a group around.
struct DetailsPanel: SwiftUI.View {
    let schema: Schema
    let selection: Set<Identifier>

    var body: some SwiftUI.View {
        ScrollView {
            if selection.count > 1 {
                multiSelectionSummary()
            } else if let selected = selection.first {
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

    private func multiSelectionSummary() -> some SwiftUI.View {
        let picked = selection.compactMap { schema.tables[$0] }
        let colCount   = picked.reduce(0) { $0 + $1.columns.count }
        let fkCount    = picked.reduce(0) { $0 + $1.foreignKeys.count }
        let idxCount   = picked.reduce(0) { $0 + $1.indexes.count }
        let names = picked.map(\.name.raw).sorted()
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading) {
                Text("\(selection.count) tables selected").font(.title2).bold()
                Text("Drag any selected table to move the whole group.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Totals").font(.headline)
                HStack { Text("Columns:"); Spacer(); Text("\(colCount)").font(.body.monospacedDigit()) }
                HStack { Text("Foreign keys:"); Spacer(); Text("\(fkCount)").font(.body.monospacedDigit()) }
                HStack { Text("Indexes:"); Spacer(); Text("\(idxCount)").font(.body.monospacedDigit()) }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Tables").font(.headline)
                ForEach(names, id: \.self) { name in
                    HStack(spacing: 6) {
                        Image(systemName: "tablecells").foregroundStyle(.secondary)
                        Text(name).font(.system(.body, design: .monospaced))
                    }
                }
            }
        }.padding()
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
