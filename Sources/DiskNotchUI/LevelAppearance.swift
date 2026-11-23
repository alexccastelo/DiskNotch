import AppKit
import Observation
import StorageCore
import SwiftUI

/// Cores de cada nível (tudo certo, atenção, crítico), escolhidas pelo usuário.
///
/// Ficam nas preferências do app (`id.nexum.disknotch`), que o widget também lê.
/// É observável: quem usa `StorageLevel.color` é redesenhado quando a cor muda.
@Observable
public final class LevelAppearance {
    /// Usado por `StorageLevel.color`. Só é alterado na thread principal (ajustes) ou
    /// uma vez por linha do tempo no widget.
    nonisolated(unsafe) public static let shared = LevelAppearance(defaults: .standard)

    public static let defaults: [StorageLevel: Color] = [
        .ok: Color(red: 0.30, green: 0.85, blue: 0.48),
        .warning: Color(red: 1.00, green: 0.72, blue: 0.20),
        .critical: Color(red: 1.00, green: 0.32, blue: 0.30),
    ]

    private static func key(_ level: StorageLevel) -> String {
        switch level {
        case .ok: "levelColorOK"
        case .warning: "levelColorWarning"
        case .critical: "levelColorCritical"
        }
    }

    public var ok: Color { didSet { save(.ok, ok) } }
    public var warning: Color { didSet { save(.warning, warning) } }
    public var critical: Color { didSet { save(.critical, critical) } }

    @ObservationIgnored private var store: UserDefaults
    /// Ao reler as preferências, não grava nada de volta.
    @ObservationIgnored private var isLoading = false

    public init(defaults: UserDefaults) {
        store = defaults
        ok = Self.load(.ok, from: defaults)
        warning = Self.load(.warning, from: defaults)
        critical = Self.load(.critical, from: defaults)
    }

    public func color(for level: StorageLevel) -> Color {
        switch level {
        case .ok: ok
        case .warning: warning
        case .critical: critical
        }
    }

    public func set(_ color: Color, for level: StorageLevel) {
        switch level {
        case .ok: ok = color
        case .warning: warning = color
        case .critical: critical = color
        }
    }

    public var isDefault: Bool {
        StorageLevel.allCases.allSatisfy { store.string(forKey: Self.key($0)) == nil }
    }

    public func resetToDefaults() {
        for level in StorageLevel.allCases { store.removeObject(forKey: Self.key(level)) }
        reload(from: store)
    }

    /// Relê as cores de outras preferências (o widget usa as do app).
    public func reload(from defaults: UserDefaults) {
        store = defaults
        isLoading = true
        defer { isLoading = false }
        ok = Self.load(.ok, from: defaults)
        warning = Self.load(.warning, from: defaults)
        critical = Self.load(.critical, from: defaults)
    }

    private func save(_ level: StorageLevel, _ color: Color) {
        guard !isLoading else { return }
        store.set(Self.hex(color), forKey: Self.key(level))
    }

    private static func load(_ level: StorageLevel, from defaults: UserDefaults) -> Color {
        defaults.string(forKey: key(level)).flatMap(color(hex:)) ?? Self.defaults[level]!
    }

    // MARK: Hexadecimal

    public static func hex(_ color: Color) -> String {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        return String(format: "#%02X%02X%02X", Int((ns.redComponent * 255).rounded()),
                      Int((ns.greenComponent * 255).rounded()), Int((ns.blueComponent * 255).rounded()))
    }

    public static func color(hex: String) -> Color? {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        return Color(red: Double((value >> 16) & 0xFF) / 255,
                     green: Double((value >> 8) & 0xFF) / 255,
                     blue: Double(value & 0xFF) / 255)
    }
}
