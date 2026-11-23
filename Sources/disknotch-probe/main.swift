import Foundation
import StorageCore

// Ferramenta de linha de comando para conferir a leitura dos volumes
// e, com --testar-alertas, a regra de quando notificar.

if CommandLine.arguments.contains("--testar-alertas") {
    exit(AlertPolicySelfTest.run() ? 0 : 1)
}
if CommandLine.arguments.contains("--testar-historico") {
    exit(HistorySelfTest.run() ? 0 : 1)
}
if CommandLine.arguments.contains("--testar-limpeza") {
    exit(CleanupSelfTest.run() ? 0 : 1)
}
if CommandLine.arguments.contains("--testar-analise") {
    exit(await AnalysisSelfTest.run() ? 0 : 1)
}
if CommandLine.arguments.contains("--analisar") {
    await RealAnalysis.run()
    exit(0)
}
if CommandLine.arguments.contains("--historico") {
    // Resumo do histórico real gravado pelo app.
    let store = try HistoryStore()
    print("amostras no banco: \(try store.count())  (\(HistoryStore.defaultURL.path))")
    if let root = VolumeService.rootVolume() {
        let samples = try store.samples(volumeID: root.id, since: .now.addingTimeInterval(-Forecast.window))
        let forecast = Forecast.compute(samples: samples)
        print("\(root.name): \(samples.count) amostras em 14 dias — \(forecast.summary()) · \(forecast.rateText)")
    }
    exit(0)
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

enum HistorySelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            if !ok { failures += 1 }
            print("\(ok ? "ok  " : "FALHA") \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        }

        let gb: Int64 = 1_000_000_000
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("disknotch-teste-\(UUID().uuidString).sqlite")
        defer {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: url.path + suffix)
            }
        }

        do {
            // 70 dias de amostras a cada 5 min, com o livre caindo 1 GB por dia.
            let store = try HistoryStore(url: url)
            var t = now.addingTimeInterval(-70 * 86_400)
            while t <= now {
                let daysAgo = now.timeIntervalSince(t) / 86_400
                let free = 50 * gb + Int64(daysAgo * Double(gb))
                try store.insert(StorageSample(date: t, totalBytes: 245 * gb, freeBytes: free, purgeableBytes: gb),
                                 volumeID: "teste")
                t = t.addingTimeInterval(300)
            }
            let before = try store.count()
            try store.compact(now: now)
            let after = try store.count()
            try store.compact(now: now)
            let again = try store.count()

            let raw = try store.samples(volumeID: "teste", since: now.addingTimeInterval(-HistoryStore.rawRetention + 1))
            let hourly = try store.samples(volumeID: "teste",
                                           since: now.addingTimeInterval(-HistoryStore.hourlyRetention + 1),
                                           until: now.addingTimeInterval(-HistoryStore.rawRetention - 1))
            let daily = try store.samples(volumeID: "teste", since: .distantPast,
                                          until: now.addingTimeInterval(-HistoryStore.hourlyRetention - 1))

            check("compactação reduz o banco", after < before, "\(before) → \(after) amostras")
            check("compactar de novo não muda nada", again == after)
            check("últimas 48 h ficam a cada 5 min", (570...578).contains(raw.count), "\(raw.count) amostras")
            check("de 48 h a 60 dias viram médias por hora", (1385...1395).contains(hourly.count), "\(hourly.count) amostras")
            check("mais de 60 dias viram médias por dia", (9...12).contains(daily.count), "\(daily.count) amostras")
            check("médias por hora caem em horas cheias",
                  hourly.allSatisfy { Int64($0.date.timeIntervalSince1970) % 3600 == 0 })

            // Previsão com o histórico compactado: 50 GB livres caindo 1 GB/dia → ~50 dias.
            let all = try store.samples(volumeID: "teste", since: .distantPast)
            let f = Forecast.compute(samples: all, now: now)
            if case .fullAt(let date) = f.outcome {
                let days = date.timeIntervalSince(now) / 86_400
                check("previsão com queda de 1 GB/dia", abs(days - 50) < 1.5,
                      "\(f.summary(now: now)) · \(f.rateText)")
            } else {
                check("previsão com queda de 1 GB/dia", false, "\(f.outcome)")
            }
        } catch {
            check("banco SQLite", false, "\(error)")
        }

        // Previsões sem banco.
        func series(hours: Double, every minutes: Double, free: (Double) -> Double) -> [StorageSample] {
            stride(from: hours * 3600, through: 0, by: -minutes * 60).map { secondsAgo in
                StorageSample(date: now.addingTimeInterval(-secondsAgo), totalBytes: 245 * gb,
                              freeBytes: Int64(free(secondsAgo / 86_400)), purgeableBytes: 0)
            }
        }
        let short = Forecast.compute(samples: series(hours: 2, every: 5) { _ in 20e9 }, now: now)
        check("menos de 6 h de dados: coletando", { if case .collecting = short.outcome { true } else { false } }(),
              short.summary(now: now))
        let flat = Forecast.compute(samples: series(hours: 48, every: 5) { _ in 20e9 }, now: now)
        check("espaço parado: estável", flat.outcome == .stable, flat.summary(now: now))
        let growing = Forecast.compute(samples: series(hours: 48, every: 5) { d in 20e9 - d * 2e9 }, now: now)
        check("espaço aumentando: estável", growing.outcome == .stable, growing.rateText)
        let fast = Forecast.compute(samples: series(hours: 24, every: 5) { d in 20e9 + d * 5e9 }, now: now)
        if case .fullAt(let date) = fast.outcome {
            check("queda de 5 GB/dia com 20 GB livres", abs(date.timeIntervalSince(now) / 86_400 - 4) < 0.2,
                  "\(fast.summary(now: now)) · \(fast.rateText)")
        } else {
            check("queda de 5 GB/dia com 20 GB livres", false, "\(fast.outcome)")
        }

        print(failures == 0 ? "\nTodos os casos passaram." : "\n\(failures) caso(s) falharam.")
        return failures == 0
    }
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
