import AppKit
import Observation
import StorageCore

/// Análise do disco: varredura sob demanda, progresso e último resultado (salvo em disco).
@MainActor
@Observable
final class AnalysisModel {
    private(set) var report: ScanReport?
    private(set) var isScanning = false
    private(set) var progress: ScanProgress.Snapshot?
    private(set) var errorMessage: String?
    private(set) var fullDiskAccess = FullDiskAccess.isGranted

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private let isDemo: Bool

    let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path

    /// Onde a última análise fica salva.
    static var storeURL: URL {
        HistoryStore.defaultURL.deletingLastPathComponent().appendingPathComponent("analysis.json")
    }

    init(demo: Bool = false) {
        isDemo = demo
        if demo {
            report = Self.demoReport(home: home)
            fullDiskAccess = true
        } else {
            report = Self.load()
        }
    }

    // MARK: Resultados derivados

    func breakdown(usedBytes: Int64?) -> CategoryBreakdown? {
        report.map { CategoryBreakdown(report: $0, home: home, usedBytes: usedBytes) }
    }

    var dev: DevSummary? { report.map { DevSummary(report: $0, home: home) } }

    /// "~/Documents/x" em vez do caminho completo.
    func display(_ path: String) -> String {
        path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    // MARK: Varredura

    func refreshAccess() {
        guard !isDemo else { return }
        fullDiskAccess = FullDiskAccess.isGranted
    }

    func start() {
        guard !isScanning, !isDemo else { return }
        refreshAccess()
        isScanning = true
        errorMessage = nil
        let progress = ScanProgress()
        self.progress = progress.snapshot()
        let home = self.home
        let roots = AnalysisDefaults.roots(home: home)
        let options = AnalysisDefaults.options(home: home)

        ticker = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.progress = progress.snapshot() }
        }
        task = Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                try await DiskScanner.scan(roots: roots, options: options, progress: progress)
            }.result
            guard let self else { return }
            self.ticker?.invalidate()
            self.isScanning = false
            switch result {
            case .success(let report):
                self.report = report
                self.fullDiskAccess = report.fullDiskAccess
                Self.save(report)
                AlertCenter.log(String(format: "análise concluída em %.0f s (%d arquivos)", report.duration, report.fileCount))
            case .failure(is CancellationError):
                break
            case .failure(let error):
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func cancel() {
        task?.cancel()
    }

    // MARK: Persistência

    private static func load() -> ScanReport? {
        guard let data = try? Data(contentsOf: storeURL) else { return nil }
        return try? JSONDecoder().decode(ScanReport.self, from: data)
    }

    private static func save(_ report: ScanReport) {
        do {
            try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(report).write(to: storeURL, options: .atomic)
        } catch {
            AlertCenter.log("não salvou a análise: \(error)")
        }
    }

    // MARK: Demonstração

    /// Análise fictícia, coerente com o volume de demonstração (494 GB, 418 GB usados).
    static func demoReport(home: String) -> ScanReport {
        let gb: Double = 1_000_000_000
        func h(_ p: String) -> String { (home as NSString).appendingPathComponent(p) }
        func b(_ v: Double) -> Int64 { Int64(v * gb) }

        let measured: [String: Int64] = [
            "/Applications": b(38), h("Documents"): b(61), h("Desktop"): b(4), h("Downloads"): b(23),
            h("Pictures"): b(47), h("Movies"): b(18), h("Music"): b(6), h("Library"): b(120), h(".Trash"): b(3),
            h("Library/Caches"): b(14), h("Library/Mobile Documents"): b(9), h("Library/Mail"): b(5),
            h("Library/Messages"): b(7), h(""): b(320.2),
            h("Library/Developer/Xcode/DerivedData"): b(21), h("Library/Developer/CoreSimulator/Devices"): b(16),
            h("Library/Developer/Xcode/iOS DeviceSupport"): b(7), h("Library/Developer/Xcode/Archives"): b(2.5),
            h("Library/Containers/com.docker.docker"): b(19), h("Library/pnpm/store"): b(6),
            h(".npm"): b(4.2), h(".ollama/models"): b(23), h(".cache/huggingface"): b(5),
            h("Library/Caches/Homebrew"): b(3.4), h("Library/Caches/pip"): b(2.1), "/opt/homebrew": b(8),
        ]
        func entries(_ list: [(String, Double, Bool)], in parent: String) -> [ScanEntry] {
            list.map { ScanEntry(path: (parent as NSString).appendingPathComponent($0.0), bytes: b($0.1), isDirectory: $0.2) }
        }
        let children: [String: [ScanEntry]] = [
            home: entries([("Library", 120, true), ("Documents", 61, true), ("Pictures", 47, true), ("Downloads", 23, true),
                           (".ollama", 23, true), ("Movies", 18, true), ("Music", 6, true), (".cache", 5.4, true),
                           (".npm", 4.2, true), ("Desktop", 4, true), (".Trash", 3, true)], in: home),
            h("Library"): entries([("Developer", 46.5, true), ("Containers", 24, true), ("Caches", 14, true),
                                   ("Mobile Documents", 9, true), ("Messages", 7, true), ("pnpm", 6, true),
                                   ("Mail", 5, true), ("Application Support", 4.8, true)], in: h("Library")),
            h("Documents"): entries([("projetos", 31, true), ("Clientes", 17, true), ("Livros", 8, true),
                                     ("Notas fiscais.zip", 2.4, false)], in: h("Documents")),
            h("Library/Developer"): entries([("Xcode", 30.5, true), ("CoreSimulator", 16, true)], in: h("Library/Developer")),
        ]
        let artifacts: [ProjectArtifact] = [
            .init(kind: .rustTarget, path: h("Documents/projetos/cli/target"), bytes: b(3.1), modified: .now.addingTimeInterval(-40 * 86_400)),
            .init(kind: .swiftBuild, path: h("Documents/projetos/app-ios/.build"), bytes: b(2.4), modified: .now.addingTimeInterval(-3 * 86_400)),
            .init(kind: .nodeModules, path: h("Documents/projetos/loja/node_modules"), bytes: b(1.8), modified: .now.addingTimeInterval(-90 * 86_400)),
            .init(kind: .nodeModules, path: h("Documents/projetos/painel/node_modules"), bytes: b(1.2), modified: .now.addingTimeInterval(-1 * 86_400)),
            .init(kind: .pythonVenv, path: h("Documents/projetos/api/.venv"), bytes: b(0.9), modified: .now.addingTimeInterval(-12 * 86_400)),
        ]
        let topFiles: [ScanEntry] = [
            .init(path: h("Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"), bytes: b(18.6), isDirectory: false),
            .init(path: h("Downloads/Xcode_27.xip"), bytes: b(11), isDirectory: false),
            .init(path: h("Movies/viagem-2026.mov"), bytes: b(6.2), isDirectory: false),
            .init(path: h(".ollama/models/blobs/sha256-8eeb52dfb3bb"), bytes: b(4.7), isDirectory: false),
            .init(path: h("Downloads/ubuntu-26.04-desktop-arm64.iso"), bytes: b(3.1), isDirectory: false),
        ]
        return ScanReport(date: .now.addingTimeInterval(-25 * 60), duration: 84,
                          roots: [home: b(320.2), "/Applications": b(38), "/opt/homebrew": b(8)],
                          fileCount: 1_843_210, measured: measured, children: children, topFiles: topFiles,
                          artifacts: artifacts, fullDiskAccess: true)
    }
}
