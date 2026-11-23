import AppKit
import Observation
import StorageCore
import DiskNotchUI
import WidgetKit
@preconcurrency import UserNotifications

/// Ajustes de alerta e faixas de ocupação, guardados no UserDefaults (o widget lê as mesmas chaves).
@MainActor
@Observable
final class AlertSettings {
    private let defaults = UserDefaults.standard
    private typealias Keys = ThresholdPreferences

    var enabled: Bool { didSet { defaults.set(enabled, forKey: "alertsEnabled") } }

    /// Resultado do último teste de notificação (mostrado nos Ajustes).
    var testMessage: String?

    /// Como as faixas são definidas: porcentagem, espaço livre em GB ou os dois.
    var mode: AlertThresholds.Mode { didSet { save(mode.rawValue, Keys.modeKey) } }

    /// Porcentagem livre abaixo da qual o volume fica em "atenção" e "crítico".
    /// "Crítico" sempre fica abaixo de "atenção" (os ajustes empurram um ao mudar o outro).
    var warningPercent: Int {
        didSet {
            save(warningPercent, Keys.warningPercentKey)
            if criticalPercent >= warningPercent { criticalPercent = max(1, warningPercent - 1) }
        }
    }
    var criticalPercent: Int {
        didSet {
            save(criticalPercent, Keys.criticalPercentKey)
            if warningPercent <= criticalPercent { warningPercent = criticalPercent + 1 }
        }
    }

    /// Espaço livre, em GB, abaixo do qual o volume fica em "atenção" e "crítico".
    var warningGB: Int {
        didSet {
            save(warningGB, Keys.warningGBKey)
            if criticalGB >= warningGB { criticalGB = max(1, warningGB - 1) }
        }
    }
    var criticalGB: Int {
        didSet {
            save(criticalGB, Keys.criticalGBKey)
            if warningGB <= criticalGB { warningGB = criticalGB + 1 }
        }
    }

    static let percentRange = 1...90
    static let gbRange = 1...2000

    init() {
        enabled = defaults.object(forKey: "alertsEnabled") as? Bool ?? true
        let saved = ThresholdPreferences.thresholds(from: defaults)
        mode = saved.mode
        warningPercent = Int((saved.warningFraction * 100).rounded())
        criticalPercent = Int((saved.criticalFraction * 100).rounded())
        warningGB = Int(saved.warningBytes / 1_000_000_000)
        criticalGB = Int(saved.criticalBytes / 1_000_000_000)
    }

    /// Calculado das propriedades observáveis: as telas se redesenham quando uma faixa muda.
    var thresholds: AlertThresholds {
        AlertThresholds(mode: mode,
                        warningFraction: Double(warningPercent) / 100, criticalFraction: Double(criticalPercent) / 100,
                        warningBytes: Int64(warningGB) * 1_000_000_000, criticalBytes: Int64(criticalGB) * 1_000_000_000)
    }

    func resetToDefaults() {
        mode = .percent
        warningPercent = Keys.defaultWarningPercent
        criticalPercent = Keys.defaultCriticalPercent
        warningGB = Keys.defaultWarningGB
        criticalGB = Keys.defaultCriticalGB
    }

    private func save(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// Envia notificações do macOS quando um volume entra em atenção ou em nível crítico.
@MainActor
final class AlertCenter: NSObject {
    private let center = UNUserNotificationCenter.current()
    private let recordsKey = "alertRecords"
    private var records: [String: AlertRecord]
    /// Só avalia depois da permissão; senão um alerta seria registrado como enviado sem aparecer.
    private var isAuthorized = false
    /// Chamado quando a permissão é concedida, para avaliar os volumes na hora.
    var onAuthorized: (() -> Void)?

    override init() {
        if let data = UserDefaults.standard.data(forKey: recordsKey),
           let saved = try? JSONDecoder().decode([String: AlertRecord].self, from: data) {
            records = saved
        } else {
            records = [:]
        }
        super.init()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            Self.log("permissão de notificação: \(granted ? "concedida" : "negada")\(error.map { " (\($0.localizedDescription))" } ?? "")")
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isAuthorized = granted
                if granted { self.onAuthorized?() }
            }
        }
    }

    /// Avalia todos os volumes locais e notifica o que for preciso.
    func check(_ volumes: [VolumeInfo], settings: AlertSettings, now: Date = .now) {
        guard settings.enabled, isAuthorized else { return }
        var changed = false
        for volume in volumes where volume.isLocal {
            let decision = AlertPolicy.evaluate(freeBytes: volume.freeBytes, totalBytes: volume.totalBytes,
                                                thresholds: settings.thresholds,
                                                previous: records[volume.id],
                                                now: now)
            if records[volume.id] != decision.record {
                records[volume.id] = decision.record
                changed = true
            }
            if let level = decision.notify {
                send(level: level, volume: volume)
            }
        }
        if changed, let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: recordsKey)
        }
    }

    /// Notificação de teste com os dados atuais do volume. Devolve o que aconteceu, para o painel mostrar.
    func sendTest(for volume: VolumeInfo, settings: AlertSettings) async -> String {
        let current = await center.notificationSettings()
        switch current.authorizationStatus {
        case .denied, .notDetermined:
            return "O macOS não está deixando o DiskNotch notificar. Libere em Ajustes do Sistema › Notificações › DiskNotch."
        default: break
        }
        if current.alertStyle == .none {
            return "As notificações do DiskNotch estão sem banner. Em Ajustes do Sistema › Notificações › DiskNotch, escolha o estilo \"Faixas\" ou \"Alertas\"."
        }
        let level = StorageLevel(volume: volume, thresholds: settings.thresholds)
        send(level: level == .ok ? .warning : level, volume: volume, isTest: true)
        return "Enviada às \(Date.now.formatted(date: .omitted, time: .shortened)). Se o banner não apareceu, um Foco (como Não Perturbe) deve estar ativo: com ele, o macOS manda a notificação direto para a Central de Notificações (clique na data e hora da barra de menus). Para os alertas passarem pelo Foco, inclua o DiskNotch nos apps permitidos do Foco."
    }

    private func send(level: StorageLevel, volume: VolumeInfo, isTest: Bool = false) {
        let percent = Int((volume.freeFraction * 100).rounded())
        let content = UNMutableNotificationContent()
        content.title = level == .critical
            ? "Espaço crítico em \(volume.name)"
            : "Pouco espaço em \(volume.name)"
        content.body = "Restam \(ByteFormat.string(volume.freeBytes)) livres (\(percent)%)."
            + (volume.purgeableBytes > 1_000_000_000
               ? " O macOS ainda pode liberar \(ByteFormat.string(volume.purgeableBytes)) sozinho."
               : "")
            + (isTest ? " (teste)" : "")
        content.sound = level == .critical ? .defaultCritical : .default
        content.threadIdentifier = volume.id

        // O teste tem identificador próprio, para não substituir um alerta real na Central de Notificações.
        let identifier = isTest ? "teste-\(UUID().uuidString)" : "\(volume.id)-\(level)"
        let request = UNNotificationRequest(identifier: identifier,
                                            content: content, trigger: nil)
        center.add(request) { error in
            Self.log("notificação \(level) para \(volume.name): \(error.map { "erro: \($0.localizedDescription)" } ?? "enviada")")
        }
    }

    /// Vai para o stderr, que o LaunchAgent grava em ~/Library/Logs/DiskNotch-start.log.
    nonisolated static func log(_ message: String) {
        FileHandle.standardError.write(Data("\(Date.now.formatted(date: .numeric, time: .standard)) [alertas] \(message)\n".utf8))
    }
}

extension AlertCenter: UNUserNotificationCenterDelegate {
    /// O app não tem janela ativa; mostra o banner mesmo assim.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// Clique na notificação: abre os Ajustes de Armazenamento.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        await MainActor.run {
            if let url = URL(string: "x-apple.systempreferences:com.apple.settings.Storage") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
