import Foundation

/// Fotografia de um volume montado.
public struct VolumeInfo: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let url: URL
    /// Capacidade total em bytes.
    public let totalBytes: Int64
    /// Livre "estrito": o que está livre agora, sem contar espaço purgável.
    public let availableBytes: Int64
    /// Livre para uso importante: inclui o que o macOS consegue purgar (caches, iCloud otimizado, snapshots).
    /// É o número que o Finder e os Ajustes do Sistema mostram como "disponível".
    public let availableImportantBytes: Int64
    public let isRoot: Bool
    public let isInternal: Bool
    public let isEjectable: Bool
    public let isLocal: Bool

    public init(id: String, name: String, url: URL, totalBytes: Int64, availableBytes: Int64,
                availableImportantBytes: Int64, isRoot: Bool, isInternal: Bool,
                isEjectable: Bool, isLocal: Bool) {
        self.id = id
        self.name = name
        self.url = url
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
        self.availableImportantBytes = availableImportantBytes
        self.isRoot = isRoot
        self.isInternal = isInternal
        self.isEjectable = isEjectable
        self.isLocal = isLocal
    }

    /// Espaço livre exibido ao usuário (igual ao Finder).
    public var freeBytes: Int64 { max(availableImportantBytes, availableBytes) }
    /// Parte do livre que só aparece depois que o macOS purgar.
    public var purgeableBytes: Int64 { max(0, availableImportantBytes - availableBytes) }
    public var usedBytes: Int64 { max(0, totalBytes - freeBytes) }

    public var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }

    public var freeFraction: Double { 1 - usedFraction }

    public var level: StorageLevel { StorageLevel(freeFraction: freeFraction) }
}

/// Faixa de alerta conforme a fração livre.
public enum StorageLevel: Sendable {
    case ok, warning, critical

    public init(freeFraction: Double, warningBelow: Double = 0.20, criticalBelow: Double = 0.10) {
        if freeFraction < criticalBelow { self = .critical }
        else if freeFraction < warningBelow { self = .warning }
        else { self = .ok }
    }
}

public enum ByteFormat {
    /// "142 GB", "1,2 TB" — base 10, como o Finder.
    public static func string(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useGB, .useTB, .useMB]
        return formatter.string(fromByteCount: bytes)
    }

    /// Versão compacta para o notch: "142 GB" sem casas decimais acima de 100.
    public static func compact(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_000_000_000
        if gb >= 1000 { return String(format: "%.1f TB", gb / 1000) }
        if gb >= 100 { return String(format: "%.0f GB", gb) }
        if gb >= 1 { return String(format: "%.1f GB", gb) }
        return String(format: "%.0f MB", gb * 1000)
    }
}
