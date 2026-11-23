import AppKit
import Observation
import StorageCore
import DiskNotchUI
import WidgetKit

/// Estado observável compartilhado pelo notch e pela barra de menus.
@MainActor
@Observable
final class StorageModel {
    private(set) var root: VolumeInfo?
    private(set) var volumes: [VolumeInfo] = []
    private(set) var lastUpdated: Date?
    let alertSettings = AlertSettings()
    /// Análise do disco (categorias, desenvolvimento, pastas).
    @ObservationIgnored let analysis: AnalysisModel
    /// Limpeza assistida (sugestões, confirmação e registro).
    @ObservationIgnored let cleanup: CleanupModel

    /// Amostras das últimas 24 h do volume de inicialização (para o gráfico do notch).
    private(set) var rootLast24h: [StorageSample] = []
    /// Previsão para o volume de inicialização.
    private(set) var rootForecast: Forecast?

    @ObservationIgnored let alerts = AlertCenter()
    @ObservationIgnored let history: HistoryStore? = {
        do { return try HistoryStore() } catch {
            AlertCenter.log("histórico indisponível: \(error)")
            return nil
        }
    }()
    @ObservationIgnored private var lastSampleDate: Date?
    @ObservationIgnored private var lastCompaction: Date?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    /// Intervalo entre amostras gravadas no histórico.
    static let sampleInterval: TimeInterval = 5 * 60

    /// Modo demonstração: dados fixos, sem ler o disco nem gravar histórico.
    /// Ligado por `DISKNOTCH_DEMO=1` e usado para gerar as imagens do README.
    @ObservationIgnored private(set) var isDemo = false
    @ObservationIgnored private var demoSeries: [String: [StorageSample]] = [:]

    static var demoRequested: Bool { ProcessInfo.processInfo.environment["DISKNOTCH_DEMO"] == "1" }

    init(interval: TimeInterval = 60, demo: Bool = false) {
        analysis = AnalysisModel(demo: demo)
        cleanup = CleanupModel(analysis: analysis, demo: demo)
        if demo {
            loadDemoData()
            return
        }
        refresh()
        alerts.onAuthorized = { [weak self] in self?.refresh() }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }

        // Atualiza na hora ao montar, desmontar ou renomear volumes.
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification,
                     NSWorkspace.didRenameVolumeNotification, NSWorkspace.didWakeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
    }

    func refresh() {
        guard !isDemo else { lastUpdated = .now; return }
        volumes = VolumeService.mountedVolumes()
        root = volumes.first(where: \.isRoot) ?? VolumeService.rootVolume()
        lastUpdated = .now
        alerts.check(volumes, settings: alertSettings)
        recordHistoryIfDue()
    }

    // MARK: Histórico

    /// Grava uma amostra de cada volume local a cada 5 min e compacta o banco a cada 6 h.
    private func recordHistoryIfDue(now: Date = .now) {
        guard let history else { return }
        if let last = lastSampleDate, now.timeIntervalSince(last) < Self.sampleInterval - 10 { return }
        lastSampleDate = now
        do {
            for volume in volumes where volume.isLocal {
                try history.insert(StorageSample(volume: volume, date: now), volumeID: volume.id)
            }
            if lastCompaction == nil || now.timeIntervalSince(lastCompaction!) > 6 * 3600 {
                try history.compact(now: now)
                lastCompaction = now
            }
        } catch {
            AlertCenter.log("erro ao gravar histórico: \(error)")
        }
        reloadRootHistory(now: now)
        reloadWidgetsIfDue(now: now)
    }

    // MARK: Widgets

    @ObservationIgnored private var lastWidgetReload: Date?
    @ObservationIgnored private var lastWidgetLevel: StorageLevel?

    /// Pede aos widgets que se atualizem a cada 15 min ou quando o nível muda,
    /// para não gastar o limite diário de atualizações do WidgetKit.
    private func reloadWidgetsIfDue(now: Date) {
        guard let root else { return }
        let level = level(of: root)
        let due = lastWidgetReload.map { now.timeIntervalSince($0) >= 15 * 60 } ?? true
        guard due || level != lastWidgetLevel else { return }
        lastWidgetReload = now
        lastWidgetLevel = level
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func reloadRootHistory(now: Date = .now) {
        guard let root else { return }
        let recent = samples(for: root, since: now.addingTimeInterval(-Forecast.window))
        rootForecast = Forecast.compute(samples: recent, now: now)
        rootLast24h = recent.filter { $0.date >= now.addingTimeInterval(-86_400) }
    }

    func samples(for volume: VolumeInfo, since: Date) -> [StorageSample] {
        if isDemo { return (demoSeries[volume.id] ?? []).filter { $0.date >= since } }
        return (try? history?.samples(volumeID: volume.id, since: since)) ?? []
    }

    // MARK: Demonstração

    private func loadDemoData(now: Date = .now) {
        isDemo = true
        let gb: Int64 = 1_000_000_000
        let mac = VolumeInfo(id: "demo-mac", name: "Macintosh HD", url: URL(fileURLWithPath: "/"),
                             totalBytes: 494 * gb, availableBytes: 71 * gb, availableImportantBytes: 76 * gb,
                             isRoot: true, isInternal: true, isEjectable: false, isLocal: true)
        let backup = VolumeInfo(id: "demo-backup", name: "Backup", url: URL(fileURLWithPath: "/Volumes/Backup"),
                                totalBytes: 1_000 * gb, availableBytes: 412 * gb, availableImportantBytes: 412 * gb,
                                isRoot: false, isInternal: false, isEjectable: true, isLocal: true)
        volumes = [mac, backup]
        root = mac
        lastUpdated = now

        // 30 dias: médias por hora até 48 h atrás e amostras a cada 5 min depois.
        // O livre cai ~1,6 GB por dia, com oscilações de downloads e limpezas.
        func series(for volume: VolumeInfo, dailyLoss: Double) -> [StorageSample] {
            var samples: [StorageSample] = []
            var t = now.addingTimeInterval(-30 * 86_400)
            while t <= now {
                let daysAgo = now.timeIntervalSince(t) / 86_400
                let wave = sin(daysAgo * 2.1) * 1.4 + sin(daysAgo * 9.7) * 0.5
                let free = Double(volume.freeBytes) + (daysAgo * dailyLoss + wave) * 1e9
                samples.append(StorageSample(date: t, totalBytes: volume.totalBytes,
                                             freeBytes: Int64(free), purgeableBytes: volume.purgeableBytes))
                t = t.addingTimeInterval(daysAgo > 2 ? 3600 : 300)
            }
            return samples
        }
        demoSeries = [mac.id: series(for: mac, dailyLoss: 1.6), backup.id: series(for: backup, dailyLoss: 0.4)]

        let recent = samples(for: mac, since: now.addingTimeInterval(-Forecast.window))
        rootForecast = Forecast.compute(samples: recent, now: now)
        rootLast24h = recent.filter { $0.date >= now.addingTimeInterval(-86_400) }
    }

    var localVolumes: [VolumeInfo] { volumes.filter(\.isLocal) }

    /// Nível do volume segundo os limites escolhidos pelo usuário.
    func level(of volume: VolumeInfo) -> StorageLevel {
        StorageLevel(volume: volume, thresholds: alertSettings.thresholds)
    }

    var externalVolumes: [VolumeInfo] { volumes.filter { !$0.isRoot } }

    func sendTestAlert() {
        guard let root else { return }
        Task { alertSettings.testMessage = await alerts.sendTest(for: root, settings: alertSettings) }
    }

    func eject(_ volume: VolumeInfo) {
        do {
            try NSWorkspace.shared.unmountAndEjectDevice(at: volume.url)
        } catch {
            NSSound.beep()
        }
        refresh()
    }

    func revealInFinder(_ volume: VolumeInfo) {
        NSWorkspace.shared.activateFileViewerSelecting([volume.url])
    }
}
