import Foundation

/// Caches e dados de ferramentas de desenvolvimento, em lugares conhecidos.
public struct DevItem: Sendable, Identifiable, Hashable {
    public enum Group: String, Sendable, CaseIterable {
        case apple = "Xcode e Swift"
        case javascript = "JavaScript"
        case python = "Python"
        case otherLanguages = "Outras linguagens"
        case packages = "Gerenciadores de pacotes"
        case containers = "Contêineres"
        case ai = "Modelos de IA locais"
    }

    /// Quão seguro é liberar o espaço.
    public enum Safety: String, Sendable {
        /// Cache que a ferramenta recria sozinha quando precisar.
        case cache
        /// Dá para liberar, mas algo precisa ser baixado ou recompilado de novo.
        case rebuildable
        /// Contém dados do usuário (imagens, modelos, simuladores): revisar antes.
        case review

        public var label: String {
            switch self {
            case .cache: "Cache, recriado sozinho"
            case .rebuildable: "Recriável, com novo download ou build"
            case .review: "Revisar antes de apagar"
            }
        }
    }

    public var id: String
    public var name: String
    public var group: Group
    public var detail: String
    /// Relativos à pasta pessoal, ou absolutos quando começam com "/".
    public var paths: [String]
    public var safety: Safety
    /// Comando oficial da ferramenta para liberar espaço, quando existe.
    public var cleanupCommand: String?

    public func absolutePaths(home: String) -> [String] {
        paths.map { $0.hasPrefix("/") ? $0 : (home as NSString).appendingPathComponent($0) }
    }
}

public enum DevCatalog {
    public static let items: [DevItem] = [
        // Xcode e Swift
        .init(id: "xcode-deriveddata", name: "Xcode · DerivedData", group: .apple,
              detail: "Builds intermediários e índices dos projetos.",
              paths: ["Library/Developer/Xcode/DerivedData"], safety: .cache, cleanupCommand: nil),
        .init(id: "xcode-archives", name: "Xcode · Archives", group: .apple,
              detail: "Versões arquivadas para distribuição. Guardam os símbolos de depuração de versões publicadas.",
              paths: ["Library/Developer/Xcode/Archives"], safety: .review, cleanupCommand: nil),
        .init(id: "xcode-devicesupport", name: "Xcode · suporte a dispositivos", group: .apple,
              detail: "Símbolos baixados para cada versão de iOS, watchOS e tvOS já conectada.",
              paths: ["Library/Developer/Xcode/iOS DeviceSupport", "Library/Developer/Xcode/watchOS DeviceSupport",
                      "Library/Developer/Xcode/tvOS DeviceSupport", "Library/Developer/Xcode/macOS DeviceSupport"],
              safety: .rebuildable, cleanupCommand: nil),
        .init(id: "simulators", name: "Simuladores", group: .apple,
              detail: "Aparelhos simulados e seus apps e dados.",
              paths: ["Library/Developer/CoreSimulator/Devices"], safety: .review,
              cleanupCommand: "xcrun simctl delete unavailable"),
        .init(id: "simulator-caches", name: "Simuladores · caches", group: .apple,
              detail: "Caches dos simuladores.",
              paths: ["Library/Developer/CoreSimulator/Caches"], safety: .cache, cleanupCommand: nil),
        .init(id: "swiftpm", name: "Swift Package Manager", group: .apple,
              detail: "Pacotes baixados e caches do SwiftPM.",
              paths: ["Library/Caches/org.swift.swiftpm", "Library/org.swift.swiftpm"], safety: .cache,
              cleanupCommand: "swift package purge-cache"),
        .init(id: "cocoapods", name: "CocoaPods", group: .apple,
              detail: "Cache de pods.", paths: ["Library/Caches/CocoaPods"], safety: .cache,
              cleanupCommand: "pod cache clean --all"),

        // JavaScript
        .init(id: "npm", name: "npm", group: .javascript, detail: "Cache de pacotes do npm.",
              paths: [".npm"], safety: .cache, cleanupCommand: "npm cache clean --force"),
        .init(id: "pnpm", name: "pnpm", group: .javascript, detail: "Store de pacotes do pnpm.",
              paths: ["Library/pnpm/store", ".pnpm-store", ".local/share/pnpm/store", "Library/Caches/pnpm"], safety: .rebuildable,
              cleanupCommand: "pnpm store prune"),
        .init(id: "yarn", name: "Yarn", group: .javascript, detail: "Cache de pacotes do Yarn.",
              paths: ["Library/Caches/Yarn", ".yarn/berry/cache"], safety: .cache, cleanupCommand: "yarn cache clean"),
        .init(id: "bun", name: "Bun", group: .javascript, detail: "Cache de instalação do Bun.",
              paths: [".bun/install/cache"], safety: .cache, cleanupCommand: "bun pm cache rm"),
        .init(id: "playwright", name: "Playwright", group: .javascript, detail: "Navegadores baixados para testes.",
              paths: ["Library/Caches/ms-playwright"], safety: .rebuildable, cleanupCommand: nil),

        // Python
        .init(id: "pip", name: "pip", group: .python, detail: "Cache de pacotes do pip.",
              paths: ["Library/Caches/pip"], safety: .cache, cleanupCommand: "pip cache purge"),
        .init(id: "uv", name: "uv", group: .python, detail: "Cache e Pythons instalados pelo uv.",
              paths: [".cache/uv", ".local/share/uv"], safety: .cache, cleanupCommand: "uv cache clean"),
        .init(id: "conda", name: "Conda", group: .python, detail: "Pacotes baixados do Conda.",
              paths: ["miniconda3/pkgs", "anaconda3/pkgs", "miniforge3/pkgs"], safety: .cache,
              cleanupCommand: "conda clean --all"),

        // Outras linguagens
        .init(id: "gradle", name: "Gradle", group: .otherLanguages, detail: "Caches de builds Java/Kotlin/Android.",
              paths: [".gradle/caches"], safety: .cache, cleanupCommand: nil),
        .init(id: "maven", name: "Maven", group: .otherLanguages, detail: "Repositório local de dependências.",
              paths: [".m2/repository"], safety: .rebuildable, cleanupCommand: nil),
        .init(id: "cargo", name: "Cargo (Rust)", group: .otherLanguages, detail: "Crates baixados.",
              paths: [".cargo/registry", ".cargo/git"], safety: .cache, cleanupCommand: nil),
        .init(id: "go", name: "Go", group: .otherLanguages, detail: "Módulos e cache de build do Go.",
              paths: ["go/pkg/mod", "Library/Caches/go-build"], safety: .cache, cleanupCommand: "go clean -cache -modcache"),

        // Gerenciadores de pacotes
        .init(id: "homebrew-cache", name: "Homebrew · downloads", group: .packages,
              detail: "Instaladores baixados pelo Homebrew.", paths: ["Library/Caches/Homebrew"], safety: .cache,
              cleanupCommand: "brew cleanup --prune=all"),
        .init(id: "homebrew", name: "Homebrew · pacotes instalados", group: .packages,
              detail: "Programas instalados pelo Homebrew. Só informativo.",
              paths: ["/opt/homebrew"], safety: .review, cleanupCommand: "brew autoremove"),

        // Contêineres
        .init(id: "docker", name: "Docker Desktop", group: .containers,
              detail: "Disco virtual com imagens, contêineres e volumes.",
              paths: ["Library/Containers/com.docker.docker"], safety: .review,
              cleanupCommand: "docker system prune"),
        .init(id: "orbstack", name: "OrbStack", group: .containers,
              detail: "Disco virtual com imagens, contêineres e máquinas.",
              paths: [".orbstack", "Library/Group Containers/HUAQ24HBR6.dev.orbstack"], safety: .review,
              cleanupCommand: "docker system prune"),

        // Modelos de IA
        .init(id: "ollama", name: "Ollama", group: .ai, detail: "Modelos baixados pelo Ollama.",
              paths: [".ollama/models"], safety: .review, cleanupCommand: "ollama rm <modelo>"),
        .init(id: "lmstudio", name: "LM Studio", group: .ai, detail: "Modelos baixados pelo LM Studio.",
              paths: [".lmstudio/models", ".cache/lm-studio/models"], safety: .review, cleanupCommand: nil),
        .init(id: "huggingface", name: "Hugging Face", group: .ai, detail: "Modelos e datasets em cache.",
              paths: [".cache/huggingface"], safety: .rebuildable, cleanupCommand: "huggingface-cli delete-cache"),
    ]

    /// Todos os caminhos absolutos do catálogo (para pedir à varredura).
    public static func allPaths(home: String) -> Set<String> {
        Set(items.flatMap { $0.absolutePaths(home: home) })
    }
}

/// Tamanho de cada item do catálogo e das pastas de projeto, a partir de uma varredura.
public struct DevSummary: Sendable {
    public struct ItemResult: Sendable, Identifiable {
        public var item: DevItem
        public var bytes: Int64
        public var foundPaths: [String]
        public var id: String { item.id }
    }

    public var items: [ItemResult]
    public var artifacts: [ProjectArtifact]

    public var itemsBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
    public var artifactsBytes: Int64 { artifacts.reduce(0) { $0 + $1.bytes } }
    public var totalBytes: Int64 { itemsBytes + artifactsBytes }
    /// Só o que é cache e se recria sozinho.
    public var cacheBytes: Int64 { items.filter { $0.item.safety == .cache }.reduce(0) { $0 + $1.bytes } }

    public init(report: ScanReport, home: String) {
        items = DevCatalog.items.compactMap { item in
            let found = item.absolutePaths(home: home).compactMap { path in report.measured[path].map { (path, $0) } }
            let bytes = found.reduce(0) { $0 + $1.1 }
            return bytes > 0 ? ItemResult(item: item, bytes: bytes, foundPaths: found.map(\.0)) : nil
        }
        .sorted { $0.bytes > $1.bytes }
        artifacts = report.artifacts
    }
}
