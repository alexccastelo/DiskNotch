import AppKit
import Observation
import StorageCore

/// Estado observável compartilhado pelo notch e pela barra de menus.
@MainActor
@Observable
final class StorageModel {
    private(set) var root: VolumeInfo?
    private(set) var volumes: [VolumeInfo] = []
    private(set) var lastUpdated: Date?
    let alertSettings = AlertSettings()

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

    init(interval: TimeInterval = 60) {
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
    }

    private func reloadRootHistory(now: Date = .now) {
        guard let root else { return }
        let recent = samples(for: root, since: now.addingTimeInterval(-Forecast.window))
        rootForecast = Forecast.compute(samples: recent, now: now)
        rootLast24h = recent.filter { $0.date >= now.addingTimeInterval(-86_400) }
    }

    func samples(for volume: VolumeInfo, since: Date) -> [StorageSample] {
        (try? history?.samples(volumeID: volume.id, since: since)) ?? []
    }

    var localVolumes: [VolumeInfo] { volumes.filter(\.isLocal) }

    /// Nível do volume segundo os limites escolhidos pelo usuário.
    func level(of volume: VolumeInfo) -> StorageLevel {
        StorageLevel(freeFraction: volume.freeFraction, thresholds: alertSettings.thresholds)
    }

    var externalVolumes: [VolumeInfo] { volumes.filter { !$0.isRoot } }

    func sendTestAlert() {
        if let root { alerts.sendTest(for: root, settings: alertSettings) }
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
