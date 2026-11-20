import Foundation

/// Limites de alerta, em fração livre do volume (0,20 = 20% livre).
public struct AlertThresholds: Codable, Equatable, Sendable {
    public var warningBelow: Double
    public var criticalBelow: Double

    public init(warningBelow: Double = 0.20, criticalBelow: Double = 0.10) {
        self.warningBelow = warningBelow
        self.criticalBelow = min(criticalBelow, warningBelow)
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

    public static func evaluate(freeFraction: Double,
                                thresholds: AlertThresholds,
                                previous: AlertRecord?,
                                now: Date) -> Decision {
        let level = StorageLevel(freeFraction: freeFraction, thresholds: thresholds)

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
            let limit = previous.level == .critical ? thresholds.criticalBelow : thresholds.warningBelow
            guard freeFraction >= limit + hysteresis else {
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
