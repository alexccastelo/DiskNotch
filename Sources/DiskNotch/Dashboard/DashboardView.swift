import AppKit
import DiskNotchUI
import Observation
import StorageCore
import SwiftUI

enum DashboardSection: String, CaseIterable, Identifiable, Hashable {
    case overview, cleanup, development, categories, folders, history, volumes, settings
    var id: Self { self }

    var title: String {
        switch self {
        case .overview: "Visão geral"
        case .cleanup: "Limpeza"
        case .development: "Desenvolvimento"
        case .categories: "Categorias"
        case .folders: "Pastas e arquivos"
        case .history: "Histórico"
        case .volumes: "Volumes"
        case .settings: "Ajustes"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "chart.pie"
        case .cleanup: "sparkles"
        case .development: "hammer"
        case .categories: "square.grid.2x2"
        case .folders: "folder"
        case .history: "chart.xyaxis.line"
        case .volumes: "externaldrive"
        case .settings: "slider.horizontal.3"
        }
    }
}

@MainActor
@Observable
final class DashboardState {
    var section: DashboardSection = .overview
    /// Pasta aberta em "Pastas e arquivos".
    var folder: String?
    let history: HistoryViewState

    init(model: StorageModel) {
        history = HistoryViewState(model: model)
    }
}

/// Esconde botões e controles do AppKit nas imagens geradas para o README.
struct SnapshotModeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isSnapshot: Bool {
        get { self[SnapshotModeKey.self] }
        set { self[SnapshotModeKey.self] = newValue }
    }
}

struct DashboardView: View {
    var model: StorageModel
    @Bindable var state: DashboardState

    var body: some View {
        NavigationSplitView {
            List(DashboardSection.allCases, selection: $state.section) { section in
                Label(section.title, systemImage: section.symbol).tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            DashboardDetail(model: model, state: state)
        }
        .frame(minWidth: 860, minHeight: 560)
        .sheet(item: Bindable(model.cleanup).pending) { option in
            CleanupSheet(cleanup: model.cleanup, option: option)
        }
    }
}

/// Conteúdo da seção escolhida (também usado sozinho nas imagens do README).
struct DashboardDetail: View {
    var model: StorageModel
    var state: DashboardState

    var body: some View {
        switch state.section {
        case .overview: OverviewPage(model: model, state: state)
        case .cleanup: CleanupPage(model: model)
        case .development: DevelopmentPage(model: model)
        case .categories: CategoriesPage(model: model)
        case .folders: FoldersPage(model: model, state: state)
        case .history: HistoryView(state: state.history).padding(.top, -6)
        case .volumes: VolumesPage(model: model)
        case .settings: SettingsPage(model: model)
        }
    }
}

// MARK: - Peças comuns

/// Cabeçalho das páginas de análise: data da última análise, progresso e botão.
struct AnalysisHeader: View {
    var title: String
    var analysis: AnalysisModel
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title2.weight(.semibold))
            Spacer()
            if analysis.isScanning, let p = analysis.progress {
                ProgressView().controlSize(.small)
                Text("\(p.fileCount.formatted()) arquivos · \(ByteFormat.string(p.bytes))")
                    .font(.callout).monospacedDigit().foregroundStyle(.secondary)
                if !isSnapshot { Button("Parar") { analysis.cancel() } }
            } else {
                if let report = analysis.report {
                    Text("Analisado \(report.date.formatted(.relative(presentation: .named))) · \(Int(report.duration.rounded())) s")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if !isSnapshot {
                    Button(analysis.report == nil ? "Analisar o disco" : "Analisar de novo") { analysis.start() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

/// Aviso quando falta Acesso Total ao Disco.
struct AccessBanner: View {
    var analysis: AnalysisModel
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        if !analysis.fullDiskAccess {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lock.shield").font(.title2).foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Análise parcial: falta o Acesso Total ao Disco").font(.headline)
                    Text("Sem ele, o macOS não deixa ler Mail, Mensagens, a Lixeira e os dados de outros apps, então essas partes ficam de fora ou menores do que são. O DiskNotch só lê tamanhos; nunca abre o conteúdo dos arquivos.")
                        .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if !isSnapshot {
                        HStack {
                            Button("Abrir Ajustes do Sistema") { NSWorkspace.shared.open(FullDiskAccess.settingsURL) }
                            Button("Já liberei") { analysis.refreshAccess() }
                        }
                        .padding(.top, 4)
                    }
                    Text("Em Privacidade e Segurança › Acesso Total ao Disco, ligue o DiskNotch. Se ele não estiver na lista, use + e escolha build/DiskNotch.app.")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
            .padding(14)
            .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

struct EmptyAnalysis: View {
    var analysis: AnalysisModel

    var body: some View {
        ContentUnavailableView {
            Label(analysis.isScanning ? "Analisando o disco…" : "Ainda sem análise", systemImage: "magnifyingglass")
        } description: {
            Text(analysis.isScanning
                 ? "Percorrendo a pasta pessoal, os Aplicativos e o Homebrew. Pode levar alguns minutos."
                 : "A análise percorre a pasta pessoal, os Aplicativos e o Homebrew para descobrir o que ocupa o disco. Ela roda em segundo plano e o resultado fica salvo.")
        } actions: {
            if !analysis.isScanning { Button("Analisar o disco") { analysis.start() }.buttonStyle(.borderedProminent) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

func reveal(_ path: String) {
    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
}

func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

struct SizeBar: View {
    var fraction: Double
    var color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(color).frame(width: max(3, geo.size.width * min(1, fraction)))
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Visão geral

private struct OverviewPage: View {
    var model: StorageModel
    var state: DashboardState
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        let analysis = model.analysis
        PageScroll {
            VStack(alignment: .leading, spacing: 18) {
                AnalysisHeader(title: "Visão geral", analysis: analysis)
                AccessBanner(analysis: analysis)
                if let root = model.root {
                    volumeSummary(root)
                }
                if let breakdown = analysis.breakdown(usedBytes: model.root?.usedBytes) {
                    let items = breakdown.slices.map {
                        TreemapItem(id: $0.id, label: $0.name, bytes: $0.bytes, color: CategoryPalette.color(for: $0.id))
                    }
                    TreemapView(items: items) { item in
                        state.section = item.id == StorageCategory.developmentID ? .development : .categories
                    }
                    .frame(height: 300)
                    if let dev = analysis.dev, dev.totalBytes > 0 {
                        devCallout(dev)
                    }
                } else {
                    EmptyAnalysis(analysis: analysis).frame(height: 300)
                }
            }
            .padding(22)
        }
    }

    private func volumeSummary(_ root: VolumeInfo) -> some View {
        let level = model.level(of: root)
        return HStack(spacing: 18) {
            ZStack {
                UsageRing(fraction: root.usedFraction, level: level, lineWidth: 9)
                Text("\(Int((root.usedFraction * 100).rounded()))%").font(.system(size: 18, weight: .bold, design: .rounded))
            }
            .frame(width: 70, height: 70)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(root.name).font(.headline)
                    Text(level.label).font(.caption.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(level.color.opacity(0.18), in: Capsule()).foregroundStyle(level.color)
                }
                UsageBar(volume: root, level: level)
                Text("\(ByteFormat.string(root.freeBytes)) livres de \(ByteFormat.string(root.totalBytes)) · \(ByteFormat.string(root.purgeableBytes)) purgáveis"
                     + (model.rootForecast.map { " · \($0.summary())" } ?? ""))
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private func devCallout(_ dev: DevSummary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "hammer.fill").font(.title2).foregroundStyle(CategoryPalette.color(for: "development"))
            VStack(alignment: .leading, spacing: 2) {
                Text("Desenvolvimento ocupa \(ByteFormat.string(dev.totalBytes))").font(.headline)
                Text("\(ByteFormat.string(dev.cacheBytes)) são caches que as ferramentas recriam sozinhas, e \(ByteFormat.string(dev.artifactsBytes)) estão em pastas de projeto que podem ser recriadas.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if !isSnapshot { Button("Ver detalhes") { state.section = .development } }
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Desenvolvimento

private struct DevelopmentPage: View {
    var model: StorageModel
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        let analysis = model.analysis
        PageScroll {
            VStack(alignment: .leading, spacing: 18) {
                AnalysisHeader(title: "Desenvolvimento", analysis: analysis)
                if let dev = analysis.dev {
                    HStack(spacing: 12) {
                        stat("Total", dev.totalBytes)
                        stat("Caches recriáveis", dev.cacheBytes)
                        stat("Pastas de projeto", dev.artifactsBytes)
                    }
                    let maxBytes = max(dev.items.first?.bytes ?? 1, dev.artifacts.first?.bytes ?? 1)
                    ForEach(DevItem.Group.allCases, id: \.self) { group in
                        let rows = dev.items.filter { $0.item.group == group }
                        if !rows.isEmpty {
                            Text(group.rawValue).font(.headline).padding(.top, 4)
                            VStack(spacing: 0) {
                                ForEach(rows) { row in itemRow(row, maxBytes: maxBytes) }
                            }
                            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    if !dev.artifacts.isEmpty {
                        Text("Pastas de projeto").font(.headline).padding(.top, 4)
                        Text("Geradas por ferramentas dentro dos projetos. Podem ser apagadas e recriadas com o comando de instalação ou de build.")
                            .font(.callout).foregroundStyle(.secondary)
                        VStack(spacing: 0) {
                            ForEach(dev.artifacts.prefix(60)) { artifact in artifactRow(artifact, maxBytes: maxBytes) }
                        }
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                    }
                    if dev.items.isEmpty && dev.artifacts.isEmpty {
                        Text("Nenhum cache de desenvolvimento encontrado.").foregroundStyle(.secondary)
                    }
                } else {
                    EmptyAnalysis(analysis: analysis).frame(height: 360)
                }
            }
            .padding(22)
        }
    }

    private func stat(_ title: String, _ bytes: Int64) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(ByteFormat.string(bytes)).font(.title3.weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private func safetyColor(_ safety: DevItem.Safety) -> Color {
        switch safety {
        case .cache: .green
        case .rebuildable: .blue
        case .review: .orange
        }
    }

    private func itemRow(_ row: DevSummary.ItemResult, maxBytes: Int64) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(row.item.name).font(.body.weight(.medium))
                    Text(row.item.safety.label).font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(safetyColor(row.item.safety).opacity(0.15), in: Capsule())
                        .foregroundStyle(safetyColor(row.item.safety))
                }
                Text(row.item.detail).font(.caption).foregroundStyle(.secondary)
                if let command = row.item.cleanupCommand {
                    HStack(spacing: 6) {
                        Text(command).font(.caption.monospaced()).foregroundStyle(.secondary)
                        if !isSnapshot {
                            Button { copy(command) } label: { Image(systemName: "doc.on.doc") }
                                .buttonStyle(.plain).foregroundStyle(.secondary).help("Copiar o comando")
                        }
                    }
                }
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 5) {
                HStack(spacing: 8) {
                    Text(ByteFormat.string(row.bytes)).font(.body.weight(.semibold)).monospacedDigit()
                    if !isSnapshot, let option = model.cleanup.option(forDevItem: row.item.id) {
                        Button("Liberar…") { model.cleanup.ask(option) }.controlSize(.small)
                    }
                    if !isSnapshot, let path = row.foundPaths.first {
                        Button { reveal(path) } label: { Image(systemName: "magnifyingglass") }
                            .buttonStyle(.plain).foregroundStyle(.secondary).help("Mostrar no Finder")
                    }
                }
                SizeBar(fraction: Double(row.bytes) / Double(maxBytes), color: CategoryPalette.color(for: "development"))
                    .frame(width: 140)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
    }

    private func artifactRow(_ artifact: ProjectArtifact, maxBytes: Int64) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(artifact.projectName).font(.body.weight(.medium))
                    Text(artifact.kind.label).font(.caption).foregroundStyle(.secondary)
                }
                Text(model.analysis.display(artifact.projectPath)
                     + (artifact.modified.map { " · alterado \($0.formatted(.relative(presentation: .named)))" } ?? ""))
                    .font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 5) {
                HStack(spacing: 8) {
                    Text(ByteFormat.string(artifact.bytes)).font(.body.weight(.semibold)).monospacedDigit()
                    if !isSnapshot, let option = model.cleanup.option(forArtifact: artifact.path) {
                        Button("Liberar…") { model.cleanup.ask(option) }.controlSize(.small)
                    }
                    if !isSnapshot {
                        Button { reveal(artifact.path) } label: { Image(systemName: "magnifyingglass") }
                            .buttonStyle(.plain).foregroundStyle(.secondary).help("Mostrar no Finder")
                    }
                }
                SizeBar(fraction: Double(artifact.bytes) / Double(maxBytes), color: CategoryPalette.color(for: "development"))
                    .frame(width: 140)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .help("Recriar com: \(artifact.kind.recreateHint)")
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
    }
}

// MARK: - Categorias

private struct CategoriesPage: View {
    var model: StorageModel

    var body: some View {
        let analysis = model.analysis
        PageScroll {
            VStack(alignment: .leading, spacing: 16) {
                AnalysisHeader(title: "Categorias", analysis: analysis)
                AccessBanner(analysis: analysis)
                if let breakdown = analysis.breakdown(usedBytes: model.root?.usedBytes) {
                    let maxBytes = breakdown.slices.first?.bytes ?? 1
                    VStack(spacing: 0) {
                        ForEach(breakdown.slices) { slice in
                            HStack(spacing: 12) {
                                Image(systemName: slice.symbol).frame(width: 22)
                                    .foregroundStyle(CategoryPalette.color(for: slice.id))
                                Text(slice.name).font(.body.weight(.medium))
                                if slice.partial {
                                    Text("parcial").font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(.orange.opacity(0.15), in: Capsule()).foregroundStyle(.orange)
                                        .help("Medida incompleta: falta o Acesso Total ao Disco.")
                                }
                                Spacer()
                                SizeBar(fraction: Double(slice.bytes) / Double(maxBytes), color: CategoryPalette.color(for: slice.id))
                                    .frame(width: 220)
                                Text(ByteFormat.string(slice.bytes)).font(.body.weight(.semibold)).monospacedDigit()
                                    .frame(width: 90, alignment: .trailing)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 9)
                            .overlay(alignment: .bottom) { Divider().opacity(0.5) }
                        }
                    }
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                    Text("Cada arquivo conta em uma categoria só. \"Desenvolvimento\" reúne os caches e as pastas de projeto, mesmo quando ficam dentro de Caches ou Documentos. \"Sistema e outros\" é o que sobra do espaço usado: o próprio macOS, apps do sistema, memória virtual e arquivos de outros usuários.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let skipped = analysis.report?.skipped, !skipped.isEmpty {
                        Label {
                            Text("Não analisadas: " + skipped.prefix(4).map { analysis.display($0) }.joined(separator: ", ")
                                 + (skipped.count > 4 ? " e mais \(skipped.count - 4)" : "")
                                 + ". São pastas de serviços de nuvem ou sem cópia local; percorrê-las obrigaria o serviço a baixar as listagens da internet.")
                        } icon: { Image(systemName: "icloud.slash") }
                        .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    EmptyAnalysis(analysis: analysis).frame(height: 360)
                }
            }
            .padding(22)
        }
    }
}

// MARK: - Pastas e arquivos

private struct FoldersPage: View {
    var model: StorageModel
    var state: DashboardState
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        let analysis = model.analysis
        let current = state.folder ?? analysis.home
        PageScroll {
            VStack(alignment: .leading, spacing: 16) {
                AnalysisHeader(title: "Pastas e arquivos", analysis: analysis)
                if let report = analysis.report {
                    breadcrumb(current, home: analysis.home)
                    let entries = report.children[current] ?? []
                    if entries.isEmpty {
                        Text("Essa pasta é pequena demais para ter detalhes guardados (menos de 100 MB).")
                            .foregroundStyle(.secondary)
                    } else {
                        let items = entries.enumerated().map { index, entry in
                            TreemapItem(id: entry.path, label: entry.name + (entry.isDirectory ? "" : " ·"),
                                        bytes: entry.bytes, color: CategoryPalette.color(at: index))
                        }
                        TreemapView(items: items) { item in
                            if report.children[item.id] != nil { state.folder = item.id } else { reveal(item.id) }
                        }
                        .frame(height: 280)
                        Text("Clique num bloco para entrar na pasta. Blocos sem detalhes abrem no Finder.")
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                    if !report.topFiles.isEmpty {
                        Text("Maiores arquivos").font(.headline).padding(.top, 6)
                        VStack(spacing: 0) {
                            ForEach(report.topFiles.prefix(20), id: \.path) { file in
                                HStack {
                                    Image(systemName: "doc").foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(file.name).lineLimit(1)
                                        Text(analysis.display((file.path as NSString).deletingLastPathComponent))
                                            .font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                                    }
                                    Spacer()
                                    Text(ByteFormat.string(file.bytes)).font(.body.weight(.semibold)).monospacedDigit()
                                    if !isSnapshot {
                                        Button { reveal(file.path) } label: { Image(systemName: "magnifyingglass") }
                                            .buttonStyle(.plain).foregroundStyle(.secondary).help("Mostrar no Finder")
                                    }
                                }
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .overlay(alignment: .bottom) { Divider().opacity(0.5) }
                            }
                        }
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                    }
                } else {
                    EmptyAnalysis(analysis: analysis).frame(height: 360)
                }
            }
            .padding(22)
        }
    }

    private func breadcrumb(_ path: String, home: String) -> some View {
        var parts: [(String, String)] = [("Pasta pessoal", home)]
        if path.hasPrefix(home + "/") {
            var current = home
            for component in path.dropFirst(home.count + 1).split(separator: "/") {
                current += "/" + component
                parts.append((String(component), current))
            }
        } else if path != home {
            parts = [(path, path)]
        }
        return HStack(spacing: 4) {
            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                if index > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                Button(part.0) { state.folder = part.1 }
                    .buttonStyle(.plain)
                    .foregroundStyle(index == parts.count - 1 ? Color.primary : Color.accentColor)
            }
            Spacer()
            if let bytes = model.analysis.report?.size(of: path) {
                Text(ByteFormat.string(bytes)).font(.callout.weight(.semibold)).monospacedDigit()
            }
        }
        .font(.callout)
    }
}

// MARK: - Volumes

private struct VolumesPage: View {
    var model: StorageModel
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        PageScroll {
            VStack(alignment: .leading, spacing: 16) {
                Text("Volumes").font(.title2.weight(.semibold))
                ForEach(model.volumes) { volume in
                    let level = model.level(of: volume)
                    HStack(spacing: 14) {
                        Image(systemName: volume.isRoot ? "internaldrive" : (volume.isLocal ? "externaldrive" : "server.rack"))
                            .font(.title2).foregroundStyle(.secondary).frame(width: 28)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(volume.name).font(.headline)
                                Text(level.label).font(.caption.weight(.semibold)).foregroundStyle(level.color)
                                Spacer()
                                Text("\(ByteFormat.string(volume.freeBytes)) livres de \(ByteFormat.string(volume.totalBytes))")
                                    .monospacedDigit().foregroundStyle(.secondary)
                            }
                            UsageBar(volume: volume, level: level)
                            Text(volume.url.path).font(.caption).foregroundStyle(.tertiary)
                        }
                        if !isSnapshot, volume.isEjectable {
                            Button { model.eject(volume) } label: { Image(systemName: "eject") }.help("Ejetar")
                        }
                    }
                    .padding(14)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(22)
        }
    }
}

// MARK: - Janela

/// Janela do painel completo, aberta pelo notch, pelo menu ou por um widget.
@MainActor
final class DashboardWindowController {
    static let shared = DashboardWindowController()
    private var window: NSWindow?
    private var state: DashboardState?

    func show(model: StorageModel, section: DashboardSection? = nil) {
        if let window, let state {
            if let section { state.section = section }
            state.history.reload()
            model.analysis.refreshAccess()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let state = DashboardState(model: model)
        if let section { state.section = section }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 680),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "DiskNotch"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: DashboardView(model: model, state: state))
        window.center()
        window.setFrameAutosaveName("DiskNotchDashboard")
        self.window = window
        self.state = state
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

/// Rolagem da página; nas imagens do README (ImageRenderer não desenha NSScrollView) fica sem ela.
struct PageScroll<Content: View>: View {
    @Environment(\.isSnapshot) private var isSnapshot
    @ViewBuilder var content: () -> Content

    var body: some View {
        if isSnapshot {
            content().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            ScrollView { content() }
        }
    }
}
