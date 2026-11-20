import Foundation
import StorageCore

// Ferramenta de linha de comando para conferir a leitura dos volumes
// e, com --testar-alertas, a regra de quando notificar.

if CommandLine.arguments.contains("--testar-alertas") {
    exit(AlertPolicySelfTest.run() ? 0 : 1)
}

for v in VolumeService.mountedVolumes() {
    let tag = v.isRoot ? " (inicialização)" : (v.isEjectable ? " (ejetável)" : "")
    print("\(v.name)\(tag) — \(v.url.path)")
    print("  total:    \(ByteFormat.string(v.totalBytes))")
    print("  usado:    \(ByteFormat.string(v.usedBytes))  (\(Int(v.usedFraction * 100))%)")
    print("  livre:    \(ByteFormat.string(v.freeBytes))  [compacto: \(ByteFormat.compact(v.freeBytes))]")
    print("  purgável: \(ByteFormat.string(v.purgeableBytes))")
    print("  nível:    \(v.level)")
}

enum AlertPolicySelfTest {
    static func run() -> Bool {
        let t = AlertThresholds(warningBelow: 0.20, criticalBelow: 0.10)
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        var failures = 0

        func check(_ name: String, _ free: Double, _ prev: AlertRecord?, at now: Date = t0,
                   notify: StorageLevel?, keeps: StorageLevel?) {
            let d = AlertPolicy.evaluate(freeFraction: free, thresholds: t, previous: prev, now: now)
            let ok = d.notify == notify && d.record?.level == keeps
            if !ok { failures += 1 }
            print("\(ok ? "ok  " : "FALHA") \(name) → avisa: \(d.notify.map { "\($0)" } ?? "não"), guarda: \(d.record.map { "\($0.level)" } ?? "nada")")
        }

        let warn = AlertRecord(level: .warning, date: t0)
        let crit = AlertRecord(level: .critical, date: t0)

        check("espaço folgado, sem histórico", 0.50, nil, notify: nil, keeps: nil)
        check("primeira leitura em atenção", 0.15, nil, notify: .warning, keeps: .warning)
        check("primeira leitura crítica", 0.05, nil, notify: .critical, keeps: .critical)
        check("continua em atenção", 0.15, warn, notify: nil, keeps: .warning)
        check("piora de atenção para crítico", 0.08, warn, notify: .critical, keeps: .critical)
        check("crítico há 2 h: não repete", 0.05, crit, at: t0 + 2 * 3600, notify: nil, keeps: .critical)
        check("crítico há 24 h: lembra", 0.05, crit, at: t0 + 24 * 3600, notify: .critical, keeps: .critical)
        check("sobe para 10,5%: ainda dentro da folga", 0.105, crit, notify: nil, keeps: .critical)
        check("sobe para 12%: rebaixa para atenção", 0.12, crit, notify: nil, keeps: .warning)
        check("volta a 20,5%: ainda dentro da folga", 0.205, warn, notify: nil, keeps: .warning)
        check("volta a 25%: esquece o alerta", 0.25, warn, notify: nil, keeps: nil)

        print(failures == 0 ? "\nTodos os casos passaram." : "\n\(failures) caso(s) falharam.")
        return failures == 0
    }
}
