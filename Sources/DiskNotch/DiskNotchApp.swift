import SwiftUI
import StorageCore

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
    let model = StorageModel()
    private(set) lazy var notch = NotchPanelController(model: model, openSettings: { [weak self] in
        self?.openSettings()
    })
    @Published var notchEnabled = UserDefaults.standard.object(forKey: "notchEnabled") as? Bool ?? true

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Sem ícone no Dock mesmo quando rodado fora de um .app.
        NSApp.setActivationPolicy(.accessory)
        if notchEnabled { notch.show() }
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
                  systemImage: root.level == .ok ? "internaldrive" : "exclamationmark.triangle.fill")
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
                            .foregroundStyle(v.level == .ok ? Color.secondary : v.level.color)
                    }
                    UsageBar(volume: v)
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
            HStack {
                Button("Atualizar") { model.refresh() }
                Spacer()
                Button("Sair") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 300)
    }
}
