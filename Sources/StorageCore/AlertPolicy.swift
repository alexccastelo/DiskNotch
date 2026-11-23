import Foundation

/// Faixas de ocupação: quando o volume entra em "atenção" e em "crítico".
///
/// Os limites podem ser em porcentagem livre, em espaço livre absoluto (bytes) ou nos dois.
/// Com os dois, vale o limite maior, ou seja, o que dispara primeiro.
public struct AlertThresholds: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, Sendable, CaseIterable {
        case percent, bytes, both

        public var label: String {
            switch self {
            case .percent: "Porcentagem livre"
            case .bytes: "Espaço livre (GB)"
            case .both: "Os dois (o que vier primeiro)"
            }
        }
    }

    public var mode: Mode
    /// Fração livre (0,20 = 20% livre).
    public var warningFraction: Double
    public var criticalFraction: Double
    /// Espaço livre em bytes.
    public var warningBytes: Int64
    public var criticalBytes: Int64

    public static let defaultWarningBytes: Int64 = 50_000_000_000
    public static let defaultCriticalBytes: Int64 = 20_000_000_000

    /// Só porcentagem (o padrão: 20% e 10% livres).
    public init(warningBelow: Double = 0.20, criticalBelow: Double = 0.10) {
        self.init(mode: .percent, warningFraction: warningBelow, criticalFraction: criticalBelow,
                  warningBytes: Self.defaultWarningBytes, criticalBytes: Self.defaultCriticalBytes)
    }

    public init(mode: Mode, warningFraction: Double, criticalFraction: Double, warningBytes: Int64, criticalBytes: Int64) {
        self.mode = mode
        self.warningFraction = warningFraction
        self.criticalFraction = criticalFraction
        self.warningBytes = warningBytes
        self.criticalBytes = criticalBytes
    }

    /// Espaço livre abaixo do qual o volume entra no nível (0 para `.ok`).
    /// O limite de "crítico" nunca passa do de "atenção".
    public func limit(_ level: StorageLevel, totalBytes: Int64) -> Int64 {
        func percent(_ fraction: Double) -> Int64 { Int64(Double(totalBytes) * fraction) }
        let warning: Int64
        let critical: Int64
        switch mode {
        case .percent: (warning, critical) = (percent(warningFraction), percent(criticalFraction))
        case .bytes: (warning, critical) = (warningBytes, criticalBytes)
        case .both: (warning, critical) = (max(percent(warningFraction), warningBytes),
                                           max(percent(criticalFraction), criticalBytes))
        }
        switch level {
        case .ok: return 0
        case .warning: return warning
        case .critical: return min(critical, warning)
        }
    }

    public func level(freeBytes: Int64, totalBytes: Int64) -> StorageLevel {
        if freeBytes < limit(.critical, totalBytes: totalBytes) { return .critical }
        if freeBytes < limit(.warning, totalBytes: totalBytes) { return .warning }
        return .ok
    }
}

/// Último alerta enviado para um volume.
public struct AlertRecord: Codable, Equatable, Sendable {
    public var level: StorageLevel
    public var date: Date

    public init(level: StorageLevel, date: Date) {
        self.level = level
        self.date = date
    }
}

/// Decide quando notificar, sem repetir alertas à toa.
///
/// - Avisa quando o volume entra numa faixa pior que a do último alerta.
/// - Em nível crítico, lembra de novo a cada `reminderInterval`.
/// - Só "esquece" um alerta quando o espaço sobe além do limite mais uma folga
///   (`hysteresis`), para não avisar várias vezes quando o uso oscila em torno do limite.
public enum AlertPolicy {
    public static let hysteresis = 0.01
    public static let reminderInterval: TimeInterval = 24 * 60 * 60

    public struct Decision: Equatable, Sendable {
        /// Nível a notificar agora, ou `nil` para não notificar.
        public var notify: StorageLevel?
        /// Registro a guardar para a próxima avaliação (`nil` apaga).
        public var record: AlertRecord?
    }

    /// Atalho só com a fração livre (num disco nominal de 1 TB), usado pelos testes de porcentagem.
    public static func evaluate(freeFraction: Double, thresholds: AlertThresholds,
                                previous: AlertRecord?, now: Date) -> Decision {
        let total: Int64 = 1_000_000_000_000
        return evaluate(freeBytes: Int64(freeFraction * Double(total)), totalBytes: total,
                        thresholds: thresholds, previous: previous, now: now)
    }

    public static func evaluate(freeBytes: Int64, totalBytes: Int64,
                                thresholds: AlertThresholds,
                                previous: AlertRecord?,
                                now: Date) -> Decision {
        let level = thresholds.level(freeBytes: freeBytes, totalBytes: totalBytes)

        guard let previous else {
            return level == .ok
                ? Decision(notify: nil, record: nil)
                : Decision(notify: level, record: AlertRecord(level: level, date: now))
        }

        // Piorou: avisa.
        if level > previous.level {
            return Decision(notify: level, record: AlertRecord(level: level, date: now))
        }

        // Melhorou: só rebaixa o registro depois de passar o limite com folga.
        if level < previous.level {
            let limit = thresholds.limit(previous.level, totalBytes: totalBytes)
            let slack = Int64(Double(totalBytes) * hysteresis)
            guard freeBytes >= limit + slack else {
                return Decision(notify: nil, record: previous)
            }
            return Decision(notify: nil, record: level == .ok ? nil : AlertRecord(level: level, date: now))
        }

        // Mesmo nível: em crítico, lembra a cada 24 h.
        if level == .critical, now.timeIntervalSince(previous.date) >= reminderInterval {
            return Decision(notify: .critical, record: AlertRecord(level: .critical, date: now))
        }
        return Decision(notify: nil, record: previous)
    }
}

/// Onde as faixas ficam guardadas: nas preferências do app (`id.nexum.disknotch`), que o widget lê.
public enum ThresholdPreferences {
    public static let suite = "id.nexum.disknotch"
    public static let modeKey = "alertThresholdMode"
    public static let warningPercentKey = "alertWarningPercent"
    public static let criticalPercentKey = "alertCriticalPercent"
    public static let warningGBKey = "alertWarningGB"
    public static let criticalGBKey = "alertCriticalGB"

    public static let defaultWarningPercent = 20
    public static let defaultCriticalPercent = 10
    public static let defaultWarningGB = 50
    public static let defaultCriticalGB = 20

    public static func thresholds(from defaults: UserDefaults?) -> AlertThresholds {
        let mode = (defaults?.string(forKey: modeKey)).flatMap(AlertThresholds.Mode.init(rawValue:)) ?? .percent
        let warningPercent = defaults?.object(forKey: warningPercentKey) as? Int ?? defaultWarningPercent
        let criticalPercent = defaults?.object(forKey: criticalPercentKey) as? Int ?? defaultCriticalPercent
        let warningGB = defaults?.object(forKey: warningGBKey) as? Int ?? defaultWarningGB
        let criticalGB = defaults?.object(forKey: criticalGBKey) as? Int ?? defaultCriticalGB
        return AlertThresholds(mode: mode,
                               warningFraction: Double(warningPercent) / 100,
                               criticalFraction: Double(criticalPercent) / 100,
                               warningBytes: Int64(warningGB) * 1_000_000_000,
                               criticalBytes: Int64(criticalGB) * 1_000_000_000)
    }
}
