import Foundation

/// Tendência do espaço livre e estimativa de quando o disco enche.
public struct Forecast: Equatable, Sendable {
    public enum Outcome: Equatable, Sendable {
        /// Ainda não há dados suficientes. `needed` é quanto tempo de histórico falta.
        case collecting(needed: TimeInterval)
        /// O espaço livre está estável ou aumentando.
        case stable
        /// No ritmo atual, o espaço livre acaba nessa data.
        case fullAt(Date)
    }

    public var outcome: Outcome
    /// Variação do espaço livre por dia (negativa quando o disco está enchendo).
    public var bytesPerDay: Double
    /// Período de histórico usado no cálculo.
    public var span: TimeInterval

    /// Histórico mínimo para arriscar uma previsão.
    public static let minimumSpan: TimeInterval = 6 * 3600
    /// Janela usada no cálculo: as últimas duas semanas.
    public static let window: TimeInterval = 14 * 86_400
    /// Abaixo dessa perda diária, o disco é considerado estável (100 MB/dia).
    public static let stableBelowBytesPerDay: Double = 100_000_000

    /// Regressão linear do espaço livre sobre o tempo, nas últimas duas semanas.
    public static func compute(samples: [StorageSample], now: Date = .now) -> Forecast {
        let recent = samples.filter { $0.date >= now.addingTimeInterval(-window) && $0.date <= now }
        guard let first = recent.first, let last = recent.last else {
            return Forecast(outcome: .collecting(needed: minimumSpan), bytesPerDay: 0, span: 0)
        }
        let span = last.date.timeIntervalSince(first.date)
        guard span >= minimumSpan, recent.count >= 6 else {
            return Forecast(outcome: .collecting(needed: max(0, minimumSpan - span)), bytesPerDay: 0, span: span)
        }

        // Tempo em dias a partir da primeira amostra, para manter os números pequenos.
        let xs = recent.map { $0.date.timeIntervalSince(first.date) / 86_400 }
        let ys = recent.map { Double($0.freeBytes) }
        let n = Double(xs.count)
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n
        var sxy = 0.0, sxx = 0.0
        for (x, y) in zip(xs, ys) {
            sxy += (x - meanX) * (y - meanY)
            sxx += (x - meanX) * (x - meanX)
        }
        let slope = sxx > 0 ? sxy / sxx : 0   // bytes por dia

        guard slope < -stableBelowBytesPerDay else {
            return Forecast(outcome: .stable, bytesPerDay: slope, span: span)
        }
        // Parte do espaço livre atual (última amostra), não do valor ajustado.
        let daysLeft = Double(last.freeBytes) / -slope
        let fullDate = last.date.addingTimeInterval(daysLeft * 86_400)
        return Forecast(outcome: .fullAt(fullDate), bytesPerDay: slope, span: span)
    }

    /// Texto curto para o notch e o menu.
    public func summary(now: Date = .now) -> String {
        switch outcome {
        case .collecting(let needed):
            let hours = Int((needed / 3600).rounded(.up))
            return hours > 0 ? "Coletando dados (faltam ~\(hours) h)" : "Coletando dados"
        case .stable:
            return "Espaço estável"
        case .fullAt(let date):
            let days = date.timeIntervalSince(now) / 86_400
            if days < 1 { return "Disco cheio em menos de 1 dia" }
            if days > 365 { return "Disco cheio em mais de 1 ano" }
            let rounded = Int(days.rounded())
            return "Disco cheio em ~\(rounded) \(rounded == 1 ? "dia" : "dias")"
        }
    }

    /// "−1,2 GB/dia" ou "+300 MB/dia".
    public var rateText: String {
        if abs(bytesPerDay) < 1_000_000 { return "sem variação" }
        let sign = bytesPerDay < 0 ? "−" : "+"
        return "\(sign)\(ByteFormat.string(Int64(abs(bytesPerDay))))/dia"
    }
}
