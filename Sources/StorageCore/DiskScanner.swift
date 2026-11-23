import Foundation

/// Um item (pasta ou arquivo) com o espaço que ocupa no disco.
public struct ScanEntry: Codable, Hashable, Sendable {
    public var path: String
    public var bytes: Int64
    public var isDirectory: Bool

    public init(path: String, bytes: Int64, isDirectory: Bool) {
        self.path = path
        self.bytes = bytes
        self.isDirectory = isDirectory
    }

    public var name: String { (path as NSString).lastPathComponent }
}

/// Pasta gerada por ferramenta de desenvolvimento dentro de um projeto (pode ser recriada).
public struct ProjectArtifact: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case nodeModules, pythonVenv, swiftBuild, rustTarget

        public var label: String {
            switch self {
            case .nodeModules: "node_modules"
            case .pythonVenv: "Ambiente Python (.venv)"
            case .swiftBuild: "Build do Swift (.build)"
            case .rustTarget: "Build do Rust (target)"
            }
        }

        /// Comando que recria a pasta, mostrado ao usuário.
        public var recreateHint: String {
            switch self {
            case .nodeModules: "npm install (ou pnpm/yarn/bun install)"
            case .pythonVenv: "python3 -m venv .venv e reinstalar as dependências"
            case .swiftBuild: "swift build"
            case .rustTarget: "cargo build"
            }
        }
    }

    public var kind: Kind
    public var path: String
    public var bytes: Int64
    public var modified: Date?

    public init(kind: Kind, path: String, bytes: Int64, modified: Date? = nil) {
        self.kind = kind
        self.path = path
        self.bytes = bytes
        self.modified = modified
    }

    public var id: String { path }
    public var projectPath: String { (path as NSString).deletingLastPathComponent }
    public var projectName: String { (projectPath as NSString).lastPathComponent }
}

/// Resultado de uma varredura.
public struct ScanReport: Codable, Sendable {
    public var date: Date
    public var duration: TimeInterval
    /// Tamanho total de cada raiz varrida.
    public var roots: [String: Int64]
    public var fileCount: Int
    /// Pastas que não puderam ser lidas (em geral por falta de Acesso Total ao Disco).
    public var unreadableCount: Int
    public var unreadableSamples: [String]
    /// Tamanho dos caminhos pedidos em `ScanOptions.measure` que existem.
    public var measured: [String: Int64]
    /// Filhos (maiores primeiro) de cada pasta acima de `ScanOptions.treeThreshold`.
    public var children: [String: [ScanEntry]]
    public var topFiles: [ScanEntry]
    public var artifacts: [ProjectArtifact]
    public var fullDiskAccess: Bool
    /// Pastas puladas: de serviços de nuvem (CloudStorage) e sem cópia local (dataless).
    public var skipped: [String]

    public init(date: Date = .now, duration: TimeInterval = 0, roots: [String: Int64] = [:], fileCount: Int = 0,
                unreadableCount: Int = 0, unreadableSamples: [String] = [], measured: [String: Int64] = [:],
                children: [String: [ScanEntry]] = [:], topFiles: [ScanEntry] = [], artifacts: [ProjectArtifact] = [],
                fullDiskAccess: Bool = false, skipped: [String] = []) {
        self.skipped = skipped
        self.date = date
        self.duration = duration
        self.roots = roots
        self.fileCount = fileCount
        self.unreadableCount = unreadableCount
        self.unreadableSamples = unreadableSamples
        self.measured = measured
        self.children = children
        self.topFiles = topFiles
        self.artifacts = artifacts
        self.fullDiskAccess = fullDiskAccess
    }

    /// Tamanho de um caminho: medido diretamente, raiz, ou entrada da árvore.
    public func size(of path: String) -> Int64? {
        if let bytes = measured[path] ?? roots[path] { return bytes }
        let parent = (path as NSString).deletingLastPathComponent
        return children[parent]?.first { $0.path == path }?.bytes
    }
}

public struct ScanOptions: Sendable {
    /// Caminhos absolutos cujo tamanho deve ser guardado.
    public var measure: Set<String>
    /// Pastas a partir desse tamanho guardam a lista de filhos (para navegar sem varrer de novo).
    public var treeThreshold: Int64
    /// Arquivos a partir desse tamanho entram na lista dos maiores.
    public var topFileMinimum: Int64
    public var topFileLimit: Int
    public var childrenLimit: Int
    /// Caminhos que não são percorridos.
    public var excluded: Set<String>
    /// Quantas pastas de primeiro nível são varridas ao mesmo tempo.
    public var concurrency: Int
    /// Não abre pastas sem cópia local (de serviços de nuvem): abri-las força o download da listagem.
    public var skipDataless: Bool
    /// Raízes onde procurar pastas de projeto (vazio: todas). Fora da pasta pessoal, node_modules
    /// são de apps e pacotes globais, não de projetos.
    public var artifactRoots: Set<String> = []

    public init(measure: Set<String> = [], treeThreshold: Int64 = 100_000_000, topFileMinimum: Int64 = 100_000_000,
                topFileLimit: Int = 50, childrenLimit: Int = 40, excluded: Set<String> = [], concurrency: Int = 4, skipDataless: Bool = true) {
        self.skipDataless = skipDataless
        self.measure = measure
        self.treeThreshold = treeThreshold
        self.topFileMinimum = topFileMinimum
        self.topFileLimit = topFileLimit
        self.childrenLimit = childrenLimit
        self.excluded = excluded
        self.concurrency = concurrency
    }
}

/// Progresso compartilhado entre a varredura e a interface.
public final class ScanProgress: @unchecked Sendable {
    public struct Snapshot: Sendable {
        public var fileCount: Int
        public var bytes: Int64
        public var currentPath: String
    }

    private let lock = NSLock()
    private var fileCount = 0
    private var bytes: Int64 = 0
    private var currentPath = ""

    public init() {}

    func add(files: Int, bytes: Int64, at path: String) {
        lock.lock()
        fileCount += files
        self.bytes += bytes
        currentPath = path
        lock.unlock()
    }

    public func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(fileCount: fileCount, bytes: bytes, currentPath: currentPath)
    }
}

/// Mede o espaço ocupado (alocado no disco, como o Finder) de árvores de pastas.
///
/// Não segue links simbólicos, não entra em outros volumes e trata pacotes (apps,
/// bibliotecas de Fotos) como pastas comuns, para somar tudo o que ocupam.
public enum DiskScanner {
    public static func scan(roots: [URL], options: ScanOptions, progress: ScanProgress? = nil) async throws -> ScanReport {
        let start = Date()
        let collector = Collector(options: options, progress: progress)
        var rootSizes: [String: Int64] = [:]

        for root in roots {
            let path = root.standardizedFileURL.path
            guard FileManager.default.fileExists(atPath: path) else { continue }
            rootSizes[path] = try await scanRoot(root.standardizedFileURL, collector: collector, options: options)
        }

        return collector.report(date: start, duration: Date().timeIntervalSince(start), roots: rootSizes)
    }

    /// A raiz é dividida entre tarefas paralelas; cada pasta de primeiro nível é varrida por uma.
    private static func scanRoot(_ root: URL, collector: Collector, options: ScanOptions) async throws -> Int64 {
        let rootPath = root.path
        guard let listing = Walker.list(root, path: rootPath, collector: collector) else { return 0 }
        let volume = VolumeID(object: try? root.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? NSObject)

        var total: Int64 = 0
        var entries: [ScanEntry] = []
        var directories: [(URL, String, ArtifactContext)] = []

        for item in listing.items {
            if let fileBytes = item.fileBytes {
                total += fileBytes
                entries.append(ScanEntry(path: item.path, bytes: fileBytes, isDirectory: false))
                collector.file(item.path, bytes: fileBytes)
            } else if item.isDirectory, options.excluded.contains(item.path) || (options.skipDataless && isDataless(item.path)) {
                collector.skip(item.path)
            } else if item.isDirectory {
                // Pastas de projeto só são procuradas fora da Biblioteca e de pastas ocultas (~/.npm,
                // ~/.cache…): ali, node_modules e afins são caches de ferramentas, não projetos.
                let name = item.url.lastPathComponent
                let toolArea = name == "Library" || name.hasPrefix(".")
                    || !(options.artifactRoots.isEmpty || options.artifactRoots.contains(rootPath))
                directories.append((item.url, item.path, toolArea ? ArtifactContext(kind: nil, disabled: true) : listing.artifactContext(for: item.url)))
            }
        }

        try await withThrowingTaskGroup(of: (String, Int64).self) { group in
            var running = 0
            for (url, path, context) in directories {
                if running >= options.concurrency {
                    if let (path, bytes) = try await group.next() {
                        total += bytes
                        entries.append(ScanEntry(path: path, bytes: bytes, isDirectory: true))
                        running -= 1
                    }
                }
                group.addTask {
                    let walker = Walker(collector: collector, options: options, volume: volume)
                    return (path, try walker.size(of: url, path: path, artifact: context, insideArtifact: context.disabled))
                }
                running += 1
            }
            for try await (path, bytes) in group {
                total += bytes
                entries.append(ScanEntry(path: path, bytes: bytes, isDirectory: true))
            }
        }

        collector.directory(rootPath, total: total, children: entries)
        return total
    }
}

// MARK: - Percurso

/// Pasta de serviço de nuvem sem cópia local (flag SF_DATALESS). Listar o conteúdo dela faz o
/// serviço buscar a listagem na internet, o que é lento e pode travar a varredura.
func isDataless(_ path: String) -> Bool {
    var st = stat()
    guard lstat(path, &st) == 0 else { return false }
    return st.st_flags & UInt32(SF_DATALESS) != 0
}

/// Identificador do volume da raiz. Só é lido depois de criado, então pode ir entre tarefas.
struct VolumeID: @unchecked Sendable {
    let object: NSObject?
}

/// Como uma pasta pode ser um artefato de projeto, decidido pelo que existe ao lado dela.
struct ArtifactContext: Sendable {
    var kind: ProjectArtifact.Kind?
    /// Não procura pastas de projeto dentro desta (Biblioteca, pastas ocultas).
    var disabled = false
}

private struct Listing {
    struct Item {
        var url: URL
        /// Caminho montado a partir do caminho pedido (sem resolver links como /var → /private/var).
        var path: String
        var isDirectory: Bool
        /// Bytes alocados, se for arquivo ou link.
        var fileBytes: Int64?
        var volume: NSObject?
        var modified: Date?
    }

    var items: [Item]
    var names: Set<String>

    func artifactContext(for url: URL) -> ArtifactContext {
        switch url.lastPathComponent {
        case "node_modules" where names.contains("package.json"): ArtifactContext(kind: .nodeModules)
        case ".venv", "venv": ArtifactContext(kind: FileManager.default.fileExists(atPath: url.appendingPathComponent("pyvenv.cfg").path) ? .pythonVenv : nil)
        case ".build" where names.contains("Package.swift"): ArtifactContext(kind: .swiftBuild)
        case "target" where names.contains("Cargo.toml"): ArtifactContext(kind: .rustTarget)
        default: ArtifactContext(kind: nil)
        }
    }
}

private struct Walker {
    let collector: Collector
    let options: ScanOptions
    let volume: VolumeID

    static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
        .volumeIdentifierKey, .contentModificationDateKey,
    ]

    static func list(_ dir: URL, path: String, collector: Collector) -> Listing? {
        let urls: [URL]
        do {
            urls = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys, options: [])
        } catch {
            collector.unreadable(path)
            return nil
        }
        var items: [Listing.Item] = []
        items.reserveCapacity(urls.count)
        for url in urls {
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            let allocated = Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
            if v.isSymbolicLink == true || v.isDirectory != true {
                items.append(.init(url: url, path: path + "/" + url.lastPathComponent, isDirectory: false, fileBytes: allocated, volume: nil, modified: v.contentModificationDate))
            } else {
                items.append(.init(url: url, path: path + "/" + url.lastPathComponent, isDirectory: true, fileBytes: nil,
                                   volume: v.volumeIdentifier as? NSObject, modified: v.contentModificationDate))
            }
        }
        return Listing(items: items, names: Set(urls.map(\.lastPathComponent)))
    }

    /// Tamanho de uma pasta (recursivo). Registra árvore, maiores arquivos e artefatos.
    func size(of dir: URL, path dirPath: String, artifact: ArtifactContext, insideArtifact: Bool) throws -> Int64 {
        try Task.checkCancellation()
        guard let listing = Self.list(dir, path: dirPath, collector: collector) else { return 0 }

        let isArtifact = !insideArtifact && artifact.kind != nil
        var total: Int64 = 0
        var files = 0
        var fileBytesHere: Int64 = 0
        var entries: [ScanEntry] = []

        for item in listing.items {
            if let bytes = item.fileBytes {
                total += bytes
                fileBytesHere += bytes
                files += 1
                if bytes >= options.topFileMinimum { collector.file(item.path, bytes: bytes) }
                entries.append(ScanEntry(path: item.path, bytes: bytes, isDirectory: false))
            } else {
                let path = item.path
                if options.excluded.contains(path) || (options.skipDataless && isDataless(path)) {
                    collector.skip(path)
                    continue
                }
                // Outro volume montado dentro da árvore: não entra.
                if let root = volume.object, let itemVolume = item.volume, !root.isEqual(itemVolume) { continue }
                var context = (insideArtifact || isArtifact) ? ArtifactContext(kind: nil) : listing.artifactContext(for: item.url)
                // Pasta oculta que não é artefato (ex.: ~/projeto/.cache): o que há dentro é de ferramenta.
                if context.kind == nil, item.url.lastPathComponent.hasPrefix(".") { context.disabled = true }
                let bytes = try size(of: item.url, path: path, artifact: context,
                                     insideArtifact: insideArtifact || isArtifact || context.disabled)
                total += bytes
                entries.append(ScanEntry(path: path, bytes: bytes, isDirectory: true))
            }
        }

        collector.progress?.add(files: files, bytes: fileBytesHere, at: dirPath)
        collector.directory(dirPath, total: total, children: entries)
        if isArtifact, let kind = artifact.kind {
            let modified = try? dir.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            collector.artifact(ProjectArtifact(kind: kind, path: dirPath, bytes: total, modified: modified))
        }
        return total
    }
}

// MARK: - Coleta (thread-safe)

private final class Collector: @unchecked Sendable {
    let options: ScanOptions
    let progress: ScanProgress?
    private let lock = NSLock()
    private var measured: [String: Int64] = [:]
    private var children: [String: [ScanEntry]] = [:]
    private var topFiles: [ScanEntry] = []
    private var artifacts: [ProjectArtifact] = []
    private var unreadableCount = 0
    private var unreadableSamples: [String] = []
    private var skipped: [String] = []
    private var fileCount = 0

    init(options: ScanOptions, progress: ScanProgress?) {
        self.options = options
        self.progress = progress
    }

    func directory(_ path: String, total: Int64, children entries: [ScanEntry]) {
        let wantsMeasure = options.measure.contains(path)
        let wantsTree = total >= options.treeThreshold
        let fileCountHere = entries.lazy.filter { !$0.isDirectory }.count
        guard wantsMeasure || wantsTree || fileCountHere > 0 else { return }
        lock.lock()
        fileCount += fileCountHere
        if wantsMeasure { measured[path] = total }
        if wantsTree {
            children[path] = Array(entries.sorted { $0.bytes > $1.bytes }.prefix(options.childrenLimit))
        }
        lock.unlock()
    }

    func file(_ path: String, bytes: Int64) {
        guard bytes >= options.topFileMinimum else { return }
        lock.lock()
        defer { lock.unlock() }
        if topFiles.count >= options.topFileLimit, let smallest = topFiles.last, smallest.bytes >= bytes { return }
        topFiles.append(ScanEntry(path: path, bytes: bytes, isDirectory: false))
        topFiles.sort { $0.bytes > $1.bytes }
        if topFiles.count > options.topFileLimit { topFiles.removeLast() }
    }

    func artifact(_ artifact: ProjectArtifact) {
        lock.lock()
        artifacts.append(artifact)
        lock.unlock()
    }

    func skip(_ path: String) {
        lock.lock()
        if skipped.count < 200 { skipped.append(path) }
        lock.unlock()
    }

    func unreadable(_ path: String) {
        lock.lock()
        unreadableCount += 1
        if unreadableSamples.count < 20 { unreadableSamples.append(path) }
        lock.unlock()
    }

    func report(date: Date, duration: TimeInterval, roots: [String: Int64]) -> ScanReport {
        lock.lock()
        defer { lock.unlock() }
        var measured = self.measured
        for (path, bytes) in roots where options.measure.contains(path) { measured[path] = bytes }
        return ScanReport(date: date, duration: duration, roots: roots, fileCount: fileCount,
                          unreadableCount: unreadableCount, unreadableSamples: unreadableSamples,
                          measured: measured, children: children, topFiles: topFiles,
                          artifacts: artifacts.sorted { $0.bytes > $1.bytes },
                          fullDiskAccess: FullDiskAccess.isGranted, skipped: skipped.sorted())
    }
}
