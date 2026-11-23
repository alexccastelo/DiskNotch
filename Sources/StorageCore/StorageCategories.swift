import Foundation

/// Categorias de ocupação, no estilo dos Ajustes de Armazenamento.
public struct StorageCategory: Sendable, Identifiable, Hashable {
    public var id: String
    public var name: String
    public var symbol: String
    /// Relativos à pasta pessoal, ou absolutos quando começam com "/".
    public var paths: [String]
    /// Só pode ser medida por inteiro com Acesso Total ao Disco.
    public var needsFullDiskAccess: Bool

    public func absolutePaths(home: String) -> [String] {
        paths.map { $0.hasPrefix("/") ? $0 : (home as NSString).appendingPathComponent($0) }
    }

    /// Ordem de atribuição: dos caminhos mais específicos para os mais gerais.
    /// "Desenvolvimento" vem antes de tudo e é montada à parte (catálogo + pastas de projeto).
    public static let all: [StorageCategory] = [
        .init(id: "apps", name: "Aplicativos", symbol: "app.badge", paths: ["/Applications", "Applications"], needsFullDiskAccess: false),
        .init(id: "mail", name: "Mail", symbol: "envelope", paths: ["Library/Mail"], needsFullDiskAccess: true),
        .init(id: "messages", name: "Mensagens", symbol: "message", paths: ["Library/Messages"], needsFullDiskAccess: true),
        .init(id: "icloud", name: "iCloud Drive (local)", symbol: "icloud", paths: ["Library/Mobile Documents"], needsFullDiskAccess: false),
        .init(id: "caches", name: "Caches", symbol: "archivebox", paths: ["Library/Caches"], needsFullDiskAccess: false),
        .init(id: "trash", name: "Lixo", symbol: "trash", paths: [".Trash"], needsFullDiskAccess: true),
        .init(id: "documents", name: "Documentos", symbol: "doc", paths: ["Documents"], needsFullDiskAccess: false),
        .init(id: "desktop", name: "Mesa", symbol: "menubar.dock.rectangle", paths: ["Desktop"], needsFullDiskAccess: false),
        .init(id: "downloads", name: "Downloads", symbol: "arrow.down.circle", paths: ["Downloads"], needsFullDiskAccess: false),
        .init(id: "photos", name: "Fotos e imagens", symbol: "photo", paths: ["Pictures"], needsFullDiskAccess: false),
        .init(id: "movies", name: "Filmes", symbol: "film", paths: ["Movies"], needsFullDiskAccess: false),
        .init(id: "music", name: "Música", symbol: "music.note", paths: ["Music"], needsFullDiskAccess: false),
        .init(id: "library", name: "Biblioteca (outros)", symbol: "books.vertical", paths: ["Library"], needsFullDiskAccess: true),
        .init(id: "home", name: "Outros na pasta pessoal", symbol: "house", paths: [""], needsFullDiskAccess: false),
    ]

    public static let developmentID = "development"
    public static let systemID = "system"

    /// Caminhos que a varredura precisa medir para montar as categorias.
    public static func measurePaths(home: String) -> Set<String> {
        var paths = Set(all.flatMap { $0.absolutePaths(home: home) })
        paths.formUnion(DevCatalog.allPaths(home: home))
        return paths
    }
}

/// Divisão do disco por categoria, sem contar nenhum byte duas vezes.
public struct CategoryBreakdown: Sendable {
    public struct Slice: Sendable, Identifiable {
        public var id: String
        public var name: String
        public var symbol: String
        public var bytes: Int64
        /// Medida incompleta por falta de Acesso Total ao Disco.
        public var partial: Bool
    }

    public var slices: [Slice]

    /// - Parameters:
    ///   - usedBytes: espaço usado do volume (o que sobra vira "Sistema e outros").
    public init(report: ScanReport, home: String, usedBytes: Int64?) {
        let homePath = (home as NSString).standardizingPath
        var assigned: [(path: String, bytes: Int64)] = []
        var slices: [Slice] = []

        /// Soma os caminhos e desconta o que já foi atribuído dentro deles.
        func exclusive(_ paths: [String]) -> Int64 {
            var total: Int64 = 0
            for path in paths {
                guard let bytes = report.measured[path] ?? report.roots[path] else { continue }
                total += bytes - Self.nestedBytes(in: path, assigned: assigned)
            }
            return max(0, total)
        }

        // 1. Desenvolvimento: catálogo + pastas de projeto.
        var devPaths: [(String, Int64)] = []
        for item in DevCatalog.items {
            for path in item.absolutePaths(home: homePath) {
                if let bytes = report.measured[path] { devPaths.append((path, bytes)) }
            }
        }
        devPaths += report.artifacts.map { ($0.path, $0.bytes) }
        // Um caminho do catálogo dentro de outro (ou artefato dentro de catálogo) conta só uma vez.
        let devTop = Self.outermost(devPaths)
        let devBytes = devTop.reduce(0) { $0 + $1.1 }
        assigned += devTop.map { (path: $0.0, bytes: $0.1) }
        slices.append(Slice(id: StorageCategory.developmentID, name: "Desenvolvimento",
                            symbol: "hammer", bytes: devBytes, partial: false))

        // 2. Demais categorias, das mais específicas para as mais gerais.
        for category in StorageCategory.all {
            let paths = category.absolutePaths(home: homePath).map { ($0 as NSString).standardizingPath }
            let bytes = exclusive(paths)
            for path in paths {
                if let measured = report.measured[path] ?? report.roots[path] {
                    // Registra o caminho inteiro; o que já estava atribuído dentro dele fica coberto.
                    assigned.removeAll { $0.path.hasPrefix(path + "/") }
                    assigned.append((path: path, bytes: measured))
                }
            }
            slices.append(Slice(id: category.id, name: category.name, symbol: category.symbol, bytes: bytes,
                                partial: category.needsFullDiskAccess && !report.fullDiskAccess))
        }

        // 3. O que sobra do volume: macOS, apps do sistema, memória virtual, outros usuários.
        if let usedBytes {
            let measured = slices.reduce(0) { $0 + $1.bytes }
            slices.append(Slice(id: StorageCategory.systemID, name: "Sistema e outros", symbol: "gearshape.2",
                                bytes: max(0, usedBytes - measured), partial: false))
        }
        self.slices = slices.filter { $0.bytes > 0 }.sorted { $0.bytes > $1.bytes }
    }

    public var totalBytes: Int64 { slices.reduce(0) { $0 + $1.bytes } }

    /// Soma dos caminhos atribuídos que estão dentro de `path` (os mais externos apenas).
    static func nestedBytes(in path: String, assigned: [(path: String, bytes: Int64)]) -> Int64 {
        let inside = assigned.filter { $0.path.hasPrefix(path + "/") || path.isEmpty }
        return outermost(inside.map { ($0.path, $0.bytes) }).reduce(0) { $0 + $1.1 }
    }

    /// Remove os caminhos que estão dentro de outro da lista.
    static func outermost(_ entries: [(String, Int64)]) -> [(String, Int64)] {
        let sorted = entries.sorted { $0.0.count < $1.0.count }
        var result: [(String, Int64)] = []
        for entry in sorted where !result.contains(where: { entry.0 == $0.0 || entry.0.hasPrefix($0.0 + "/") }) {
            result.append(entry)
        }
        return result
    }
}

/// O que a análise percorre, usado pelo app e pelo probe.
public enum AnalysisDefaults {
    public static func roots(home: String) -> [URL] {
        [home, "/Applications", "/opt/homebrew"].map { URL(fileURLWithPath: $0) }
    }

    /// Pastas de serviços de nuvem (Google Drive, Dropbox, OneDrive…) ficam de fora: percorrê-las
    /// obriga o serviço a buscar cada listagem na internet.
    public static func excluded(home: String) -> Set<String> {
        [(home as NSString).appendingPathComponent("Library/CloudStorage")]
    }

    public static func options(home: String) -> ScanOptions {
        var options = ScanOptions(measure: StorageCategory.measurePaths(home: home), excluded: excluded(home: home))
        options.artifactRoots = [home]
        return options
    }
}
