import SwiftUI
import StorageCore
import DiskNotchUI

@main
struct DiskNotchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: delegate.model, notch: delegate)
        } label: {
            MenuLabel(model: delegate.model)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    let model = StorageModel(demo: StorageModel.demoRequested)
    private(set) lazy var notch = NotchPanelController(model: model, openSettings: { [weak self] in
        self?.openSettings()
    })
    @Published var notchEnabled = UserDefaults.standard.object(forKey: "notchEnabled") as? Bool ?? true

    /// Outra cópia do DiskNotch já estava aberta quando esta iniciou.
    private var isDuplicate = false
    private static let openURLNotification = Notification.Name("id.nexum.disknotch.open-url")

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard !CommandLine.arguments.contains("--render-readme-images") else { return }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        // Cópia aberta antes deste executável ser compilado é de uma versão antiga: ela sai e esta fica.
        let built = (try? Bundle.main.executableURL?.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
        let (outdated, current) = (others.filter { ($0.launchDate ?? .distantPast) < built },
                                   others.filter { ($0.launchDate ?? .distantPast) >= built })
        for old in outdated {
            AlertCenter.log("encerrando cópia de uma versão anterior (pid \(old.processIdentifier))")
            if !old.terminate() { old.forceTerminate() }
        }
        isDuplicate = !current.isEmpty
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // --render-readme-images <pasta>: gera as imagens do README e sai.
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render-readme-images") {
            let path = i + 1 < args.count ? args[i + 1] : "docs/design"
            exit(ReadmeRenderer.run(outputDirectory: URL(fileURLWithPath: path)) ? 0 : 1)
        }
        // Uma cópia só: esta repassa os links (abaixo) e fecha. Sair com código 0 não faz
        // o launchd reabrir (KeepAlive só reabre depois de travamento).
        if isDuplicate {
            AlertCenter.log("outra cópia já está aberta; esta fecha")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { exit(0) }
            return
        }
        DistributedNotificationCenter.default().addObserver(forName: Self.openURLNotification, object: nil, queue: .main) { [weak self] note in
            guard let string = note.object as? String, let url = URL(string: string) else { return }
            MainActor.assumeIsolated { self?.handle(url) }
        }
        // Sem ícone no Dock mesmo quando rodado fora de um .app.
        NSApp.setActivationPolicy(.accessory)
        if notchEnabled { notch.show() }
    }

    /// Links disknotch://painel e disknotch://historico, usados pelos widgets.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "disknotch" {
            if isDuplicate {
                DistributedNotificationCenter.default().postNotificationName(
                    Self.openURLNotification, object: url.absoluteString, userInfo: nil, deliverImmediately: true)
            } else {
                handle(url)
            }
        }
    }

    private func handle(_ url: URL) {
        switch url.host {
        case "historico": DashboardWindowController.shared.show(model: model, section: .history)
        default: DashboardWindowController.shared.show(model: model)
        }
    }

    func setNotchEnabled(_ enabled: Bool) {
        notchEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "notchEnabled")
        enabled ? notch.show() : notch.hide()
    }

    @Published var notchSide = NotchPanelController.side

    func setNotchSide(_ side: NotchSide) {
        notchSide = side
        notch.setSide(side)
    }

    func openSettings() {
        // Fase 0: abre os Ajustes de Armazenamento do sistema até termos a janela própria.
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.Storage") {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct MenuLabel: View {
    var model: StorageModel
    var body: some View {
        if let root = model.root {
            Label(ByteFormat.compact(root.freeBytes),
                  systemImage: model.level(of: root) == .ok ? "internaldrive" : "exclamationmark.triangle.fill")
        } else {
            Image(systemName: "internaldrive")
        }
    }
}

private struct MenuContent: View {
    var model: StorageModel
    @ObservedObject var notch: AppDelegate

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(model.volumes) { v in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(v.name).font(.headline)
                        Spacer()
                        Text("\(ByteFormat.string(v.freeBytes)) livres").monospacedDigit()
                            .foregroundStyle(model.level(of: v) == .ok ? Color.secondary : model.level(of: v).color)
                    }
                    UsageBar(volume: v, level: model.level(of: v))
                    Text("\(ByteFormat.string(v.usedBytes)) de \(ByteFormat.string(v.totalBytes)) usados · \(ByteFormat.string(v.purgeableBytes)) purgáveis")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            Toggle("Mostrar painel no notch", isOn: Binding(
                get: { notch.notchEnabled },
                set: { notch.setNotchEnabled($0) }
            ))
            Picker("Informação no notch", selection: Binding(
                get: { notch.notchSide },
                set: { notch.setNotchSide($0) }
            )) {
                ForEach(NotchSide.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .disabled(!notch.notchEnabled)
            Divider()
            AlertSettingsView(settings: model.alertSettings, sendTest: model.sendTestAlert)
            Divider()
            if let forecast = model.rootForecast {
                Label(forecast.summary(), systemImage: "chart.line.downtrend.xyaxis")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button("Atualizar") { model.refresh() }
                Button("Abrir painel…") { DashboardWindowController.shared.show(model: model) }
                Spacer()
                Button("Sair") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 300)
    }
}

/// Liga e desliga os alertas e ajusta os limites. Os limites também definem as cores.
private struct AlertSettingsView: View {
    @Bindable var settings: AlertSettings
    var sendTest: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Avisar quando houver pouco espaço", isOn: $settings.enabled)
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 6) {
                GridRow {
                    Label("Atenção abaixo de", systemImage: "circle.fill")
                        .foregroundStyle(StorageLevel.warning.color)
                    Picker("", selection: $settings.warningPercent) {
                        ForEach(AlertSettings.warningOptions, id: \.self) { Text("\($0)% livre").tag($0) }
                    }
                    .labelsHidden()
                }
                GridRow {
                    Label("Crítico abaixo de", systemImage: "circle.fill")
                        .foregroundStyle(StorageLevel.critical.color)
                    Picker("", selection: $settings.criticalPercent) {
                        ForEach(AlertSettings.criticalOptions, id: \.self) { Text("\($0)% livre").tag($0) }
                    }
                    .labelsHidden()
                }
            }
            .labelStyle(DotLabelStyle())
            .font(.callout)
            Button("Enviar notificação de teste", action: sendTest)
                .disabled(!settings.enabled)
        }
    }
}

private struct DotLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon.font(.system(size: 7))
            configuration.title.foregroundStyle(.primary)
        }
    }
}
