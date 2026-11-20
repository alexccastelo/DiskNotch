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

    @ObservationIgnored let alerts = AlertCenter()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

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
    }

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
