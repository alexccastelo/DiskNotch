import AppKit
import DiskNotchUI
import StorageCore
import SwiftUI
import WidgetKit

/// Seção "Ajustes": faixas de ocupação, cores de cada nível e alertas.
struct SettingsPage: View {
    var model: StorageModel

    var body: some View {
        PageScroll {
            VStack(alignment: .leading, spacing: 22) {
                Text("Ajustes").font(.title2.weight(.semibold))
                RangesSection(settings: model.alertSettings, volumes: model.localVolumes, model: model)
                ColorsSection(appearance: LevelAppearance.shared, model: model)
                AlertsSection(settings: model.alertSettings, sendTest: model.sendTestAlert)
            }
            .padding(22)
        }
    }
}

private struct SectionCard<Content: View>: View {
    var title: String
    var subtitle: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Faixas

private struct RangesSection: View {
    @Bindable var settings: AlertSettings
    var volumes: [VolumeInfo]
    var model: StorageModel

    var body: some View {
        SectionCard(title: "Faixas de ocupação",
                    subtitle: "Quando um disco passa a \"espaço baixo\" e a \"espaço crítico\". As faixas definem as cores do notch, do menu, do painel e dos widgets, e os alertas.") {
            Picker("Definir por", selection: $settings.mode) {
                ForEach(AlertThresholds.Mode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .fixedSize()

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                if settings.mode != .bytes {
                    GridRow {
                        Text("Porcentagem livre").foregroundStyle(.secondary)
                        stepper(.warning, value: $settings.warningPercent, range: AlertSettings.percentRange, unit: "%")
                        stepper(.critical, value: $settings.criticalPercent, range: AlertSettings.percentRange, unit: "%")
                    }
                }
                if settings.mode != .percent {
                    GridRow {
                        Text("Espaço livre").foregroundStyle(.secondary)
                        stepper(.warning, value: $settings.warningGB, range: AlertSettings.gbRange, unit: " GB", step: 5)
                        stepper(.critical, value: $settings.criticalGB, range: AlertSettings.gbRange, unit: " GB", step: 5)
                    }
                }
            }
            if settings.mode == .both {
                Text("Com os dois, vale o que disparar primeiro: o maior espaço livre entre a porcentagem e os GB.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Divider()
            Text("Como fica nos seus discos").font(.subheadline.weight(.medium))
            ForEach(volumes) { volume in preview(volume) }

            Button("Restaurar padrão (20% e 10%)") { settings.resetToDefaults() }
                .buttonStyle(.link)
        }
    }

    private func stepper(_ level: StorageLevel, value: Binding<Int>, range: ClosedRange<Int>, unit: String, step: Int = 1) -> some View {
        HStack(spacing: 8) {
            Circle().fill(level.color).frame(width: 9, height: 9)
            Text(level == .warning ? "Atenção abaixo de" : "Crítico abaixo de")
            Stepper(value: value, in: range, step: step) {
                Text("\(value.wrappedValue)\(unit)").monospacedDigit().frame(minWidth: 56, alignment: .trailing)
            }
        }
    }

    private func preview(_ volume: VolumeInfo) -> some View {
        let thresholds = settings.thresholds
        let level = model.level(of: volume)
        let warning = thresholds.limit(.warning, totalBytes: volume.totalBytes)
        let critical = thresholds.limit(.critical, totalBytes: volume.totalBytes)
        return HStack(spacing: 12) {
            UsageRing(fraction: volume.usedFraction, level: level, lineWidth: 4).frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("\(volume.name) (\(ByteFormat.string(volume.totalBytes)))").font(.callout.weight(.medium))
                    Text(level.label).font(.caption.weight(.semibold)).foregroundStyle(level.color)
                }
                Text("Atenção abaixo de \(ByteFormat.string(warning)) livres · crítico abaixo de \(ByteFormat.string(critical)) · agora: \(ByteFormat.string(volume.freeBytes)) livres")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }
}

// MARK: - Cores

private struct ColorsSection: View {
    @Bindable var appearance: LevelAppearance
    var model: StorageModel

    var body: some View {
        SectionCard(title: "Cores", subtitle: "A cor de cada nível no anel, nas barras, no texto do notch e nos widgets.") {
            HStack(spacing: 28) {
                picker("Tudo certo", $appearance.ok, level: .ok)
                picker("Espaço baixo", $appearance.warning, level: .warning)
                picker("Espaço crítico", $appearance.critical, level: .critical)
            }
            HStack(spacing: 18) {
                ForEach(StorageLevel.allCases, id: \.self) { level in
                    HStack(spacing: 8) {
                        UsageRing(fraction: level == .ok ? 0.55 : level == .warning ? 0.85 : 0.95, level: level, lineWidth: 5)
                            .frame(width: 28, height: 28)
                        Text(level.label).font(.caption.weight(.semibold)).foregroundStyle(level.color)
                    }
                }
            }
            .padding(10)
            .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
            .environment(\.colorScheme, .dark)

            Button("Restaurar cores padrão") { appearance.resetToDefaults(); WidgetCenter.shared.reloadAllTimelines() }
                .buttonStyle(.link)
                .disabled(appearance.isDefault)
        }
        .onChange(of: LevelAppearance.hex(appearance.ok) + LevelAppearance.hex(appearance.warning) + LevelAppearance.hex(appearance.critical)) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func picker(_ title: String, _ color: Binding<Color>, level: StorageLevel) -> some View {
        ColorPicker(selection: color, supportsOpacity: false) {
            Text(title)
        }
        .fixedSize()
    }
}

// MARK: - Alertas

private struct AlertsSection: View {
    @Bindable var settings: AlertSettings
    var sendTest: () -> Void

    var body: some View {
        SectionCard(title: "Alertas", subtitle: "Notificação do macOS quando um disco local entra em \"espaço baixo\" ou \"espaço crítico\". Avisa uma vez por piora e, em nível crítico, lembra uma vez por dia.") {
            Toggle("Avisar quando houver pouco espaço", isOn: $settings.enabled)
            HStack {
                Button("Enviar notificação de teste", action: sendTest).disabled(!settings.enabled)
                Button("Ajustes de notificação do macOS") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=id.nexum.disknotch") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(.link)
            }
            if let message = settings.testMessage {
                Label(message, systemImage: "bell.badge").font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
