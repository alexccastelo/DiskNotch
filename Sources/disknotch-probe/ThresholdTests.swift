import Foundation
import StorageCore

/// Faixas por porcentagem, por espaço livre (GB) e pelas duas.
enum ThresholdSelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            if !ok { failures += 1 }
            print("\(ok ? "ok  " : "FALHA") \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        }
        let gb: Int64 = 1_000_000_000
        let total = 245 * gb
        func t(_ mode: AlertThresholds.Mode, _ wp: Double = 0.20, _ cp: Double = 0.10, _ wg: Int64 = 50, _ cg: Int64 = 20) -> AlertThresholds {
            AlertThresholds(mode: mode, warningFraction: wp, criticalFraction: cp, warningBytes: wg * gb, criticalBytes: cg * gb)
        }

        print("\nFaixas:")
        check("porcentagem: limite de atenção = 20% de 245 GB", t(.percent).limit(.warning, totalBytes: total) == 49 * gb)
        check("GB: limite de atenção = 50 GB, qualquer que seja o disco", t(.bytes).limit(.warning, totalBytes: total) == 50 * gb
              && t(.bytes).limit(.warning, totalBytes: 2_000 * gb) == 50 * gb)
        check("os dois: vale o maior (o que dispara primeiro)", t(.both).limit(.warning, totalBytes: total) == 50 * gb
              && t(.both).limit(.critical, totalBytes: total) == Int64(24.5 * Double(gb)))
        check("os dois num disco de 2 TB: a porcentagem dispara primeiro", t(.both).limit(.warning, totalBytes: 2_000 * gb) == 400 * gb)
        check("crítico nunca passa do de atenção", t(.both, 0.05, 0.40).limit(.critical, totalBytes: total) == t(.both, 0.05, 0.40).limit(.warning, totalBytes: total))

        check("GB: 30 GB livres = espaço baixo", t(.bytes).level(freeBytes: 30 * gb, totalBytes: total) == .warning)
        check("GB: 15 GB livres = crítico", t(.bytes).level(freeBytes: 15 * gb, totalBytes: total) == .critical)
        check("porcentagem: 30 GB livres de 245 (12%) = espaço baixo", t(.percent).level(freeBytes: 30 * gb, totalBytes: total) == .warning)
        check("os dois: 22 GB livres (9%) = crítico pelos dois", t(.both).level(freeBytes: 22 * gb, totalBytes: total) == .critical)
        check("GB: 60 GB livres = tudo certo", t(.bytes).level(freeBytes: 60 * gb, totalBytes: total) == .ok)

        let crit = AlertRecord(level: .critical, date: .now)
        let stay = AlertPolicy.evaluate(freeBytes: 21 * gb, totalBytes: total, thresholds: t(.bytes), previous: crit, now: .now)
        check("GB: 21 GB (limite 20 + folga de 1% = 22,45) ainda é crítico registrado", stay.record?.level == .critical)
        let leave = AlertPolicy.evaluate(freeBytes: 23 * gb, totalBytes: total, thresholds: t(.bytes), previous: crit, now: .now)
        check("GB: 23 GB sai do crítico", leave.record?.level == .warning && leave.notify == nil)

        let prefs = UserDefaults(suiteName: "disknotch-teste-\(UUID().uuidString)")!
        check("preferências vazias: padrão de 20% e 10%", ThresholdPreferences.thresholds(from: prefs) == AlertThresholds())
        prefs.set("both", forKey: ThresholdPreferences.modeKey)
        prefs.set(80, forKey: ThresholdPreferences.warningGBKey)
        let saved = ThresholdPreferences.thresholds(from: prefs)
        check("preferências gravadas são lidas", saved.mode == .both && saved.warningBytes == 80 * gb)

        print(failures == 0 ? "\nTodos os casos de faixas passaram." : "\n\(failures) caso(s) de faixas falharam.")
        return failures == 0
    }
}
