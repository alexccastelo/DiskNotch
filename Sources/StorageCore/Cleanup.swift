import Foundation

/// Uma forma de liberar espaço, sempre com confirmação do usuário.
public struct CleanupOption: Sendable, Identifiable, Hashable {
    public enum Method: Sendable, Hashable {
        /// Move os caminhos para o Lixo (dá para devolver pelo Finder).
        case trash
        /// Roda o comando oficial da ferramenta, que não pede confirmação interativa.
        case command(String, tool: String)
    }

    public enum Source: Sendable, Hashable {
        case devItem(String)
        case artifact(ProjectArtifact.Kind)
    }

    public var id: String
    public var title: String
    public var detail: String
    /// Quanto ocupa hoje (o comando pode liberar menos).
    public var bytes: Int64
    /// Caminhos movidos para o Lixo, ou medidos de novo depois do comando.
    public var paths: [String]
    public var method: Method
    public var source: Source
    public var safety: DevItem.Safety
    public var modified: Date?
    /// Entra na lista de sugestões (caches, pastas de projeto paradas).
    public var suggested: Bool
}

/// Decide o que pode ser oferecido para liberar. Não toca em nada.
public enum CleanupPlanner {
    /// Comandos oficiais que rodam sem perguntar nada (nenhum deles apaga dados do usuário).
    /// A chave é o `id` do item no catálogo.
    public static let commands: [String: (command: String, tool: String)] = [
        "npm": ("npm cache clean --force", "npm"),
        "pnpm": ("pnpm store prune", "pnpm"),
        "yarn": ("yarn cache clean", "yarn"),
        "bun": ("bun pm cache rm", "bun"),
        "pip": ("pip3 cache purge", "pip3"),
        "uv": ("uv cache clean", "uv"),
        "conda": ("conda clean --all --yes", "conda"),
        "go": ("go clean -cache -modcache", "go"),
        "homebrew-cache": ("brew cleanup --prune=all", "brew"),
        "simulators": ("xcrun simctl delete unavailable", "xcrun"),
        "cocoapods": ("pod cache clean --all", "pod"),
    ]

    /// Ferramentas a procurar no PATH do usuário.
    public static var tools: Set<String> { Set(commands.values.map(\.tool)) }

    /// Pastas de projeto sem mudanças há mais tempo que isso entram nas sugestões.
    public static let staleAfter: TimeInterval = 30 * 86_400

    /// Abaixo disso não vale sugerir.
    public static let minimumBytes: Int64 = 50_000_000

    public static func options(for summary: DevSummary, availableTools: Set<String>, now: Date = .now) -> [CleanupOption] {
        var result: [CleanupOption] = []

        for row in summary.items {
            let item = row.item
            if let entry = commands[item.id], availableTools.contains(entry.tool) {
                result.append(CleanupOption(
                    id: "dev:\(item.id)", title: item.name, detail: item.detail, bytes: row.bytes,
                    paths: row.foundPaths, method: .command(entry.command, tool: entry.tool),
                    source: .devItem(item.id), safety: item.safety, modified: nil,
                    suggested: item.safety == .cache && row.bytes >= minimumBytes))
            } else if item.safety != .review {
                // Cache ou recriável sem comando: vai para o Lixo.
                result.append(CleanupOption(
                    id: "dev:\(item.id)", title: item.name, detail: item.detail, bytes: row.bytes,
                    paths: row.foundPaths, method: .trash, source: .devItem(item.id),
                    safety: item.safety, modified: nil,
                    suggested: item.safety == .cache && row.bytes >= minimumBytes))
            }
            // "Revisar antes de apagar" (Docker, modelos, Archives…): sem ação, só o comando para copiar.
        }

        for artifact in summary.artifacts {
            let stale = artifact.modified.map { now.timeIntervalSince($0) > staleAfter } ?? false
            result.append(CleanupOption(
                id: "artifact:\(artifact.path)", title: "\(artifact.projectName) · \(artifact.kind.label)",
                detail: "Recriar com: \(artifact.kind.recreateHint)", bytes: artifact.bytes,
                paths: [artifact.path], method: .trash, source: .artifact(artifact.kind),
                safety: .rebuildable, modified: artifact.modified,
                suggested: stale && artifact.bytes >= minimumBytes))
        }
        return result.sorted { $0.bytes > $1.bytes }
    }

    /// Caminhos que podem ir para o Lixo: só os do catálogo e as pastas de projeto detectadas.
    public static func allowedPaths(for options: [CleanupOption]) -> Set<String> {
        Set(options.filter { $0.method == .trash }.flatMap(\.paths))
    }
}

/// Última barreira antes de mover algo para o Lixo.
public enum CleanupSafety {
    public enum Refusal: Error, Equatable, CustomStringConvertible {
        case notAllowed(String)
        case outsideHome(String)
        case protected(String)
        case missing(String)
        case symbolicLink(String)

        public var description: String {
            switch self {
            case .notAllowed(let p): "não está entre os itens que o DiskNotch pode liberar: \(p)"
            case .outsideHome(let p): "fora da pasta pessoal: \(p)"
            case .protected(let p): "pasta protegida: \(p)"
            case .missing(let p): "não existe mais: \(p)"
            case .symbolicLink(let p): "é um link simbólico: \(p)"
            }
        }
    }

    /// Pastas que nunca vão para o Lixo, mesmo que alguém as coloque na lista permitida.
    public static func protectedPaths(home: String) -> Set<String> {
        let names = ["", "Library", "Library/Caches", "Library/Application Support", "Library/Containers",
                     "Library/Developer", "Library/Mobile Documents", "Documents", "Desktop", "Downloads",
                     "Pictures", "Movies", "Music", "Applications", ".Trash", ".cache", ".local", ".config", ".ssh"]
        return Set(names.map { (home as NSString).appendingPathComponent($0) })
    }

    public static func validate(_ rawPath: String, home rawHome: String, allowed: Set<String>) throws {
        let path = (rawPath as NSString).standardizingPath
        let home = (rawHome as NSString).standardizingPath
        guard allowed.contains(path) || allowed.contains(rawPath) else { throw Refusal.notAllowed(path) }
        guard path.hasPrefix(home + "/") else { throw Refusal.outsideHome(path) }
        guard !protectedPaths(home: home).contains(path) else { throw Refusal.protected(path) }
        var st = stat()
        guard lstat(path, &st) == 0 else { throw Refusal.missing(path) }
        guard (st.st_mode & S_IFMT) != S_IFLNK else { throw Refusal.symbolicLink(path) }
    }
}

/// Registro do que foi liberado.
public struct CleanupRecord: Codable, Sendable, Identifiable {
    public var id: UUID
    public var date: Date
    public var title: String
    /// "Lixo" ou o comando que rodou.
    public var method: String
    public var freedBytes: Int64

    public init(date: Date = .now, title: String, method: String, freedBytes: Int64) {
        id = UUID()
        self.date = date
        self.title = title
        self.method = method
        self.freedBytes = freedBytes
    }
}
