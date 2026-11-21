import AppKit
import Charts
import Observation
import StorageCore
import DiskNotchUI
import SwiftUI

// MARK: - Cartão do notch

/// Mini gráfico das últimas 24 h, variação e previsão.
struct HistoryCard: View {
    var samples: [StorageSample]
    var forecast: Forecast?
    var level: StorageLevel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Livre · 24 h").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                if let delta {
                    Text(delta.text)
                        .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(delta.bytes < 0 ? level.color : Color.secondary)
                }
            }

            if samples.count >= 2 {
                Chart(samples, id: \.date) { s in
                    AreaMark(x: .value("Hora", s.date), y: .value("Livre", Double(s.freeBytes) / 1e9))
                        .foregroundStyle(level.color.opacity(0.18).gradient)
                    LineMark(x: .value("Hora", s.date), y: .value("Livre", Double(s.freeBytes) / 1e9))
                        .foregroundStyle(level.color)
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: yDomain)
                .chartPlotStyle { $0.clipped() }
                .frame(height: 44)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.white.opacity(0.06))
                    .overlay(Text("O gráfico aparece após 2 amostras").font(.system(size: 9)).foregroundStyle(.tertiary))
                    .frame(height: 44)
            }

            Text(forecast?.summary() ?? "Coletando dados")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isFillingUp ? level.color : Color.secondary)
                .lineLimit(1)
        }
        .padding(8)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
    }

    private var isFillingUp: Bool {
        if case .fullAt = forecast?.outcome { return true }
        return false
    }

    private var delta: (bytes: Int64, text: String)? {
        guard let first = samples.first, let last = samples.last, samples.count >= 2 else { return nil }
        let bytes = last.freeBytes - first.freeBytes
        let sign = bytes < 0 ? "−" : "+"
        return (bytes, "\(sign)\(ByteFormat.compact(abs(bytes)))")
    }

    /// Escala ajustada aos dados, com folga, para a variação ficar visível.
    private var yDomain: ClosedRange<Double> {
        let values = samples.map { Double($0.freeBytes) / 1e9 }
        guard let lo = values.min(), let hi = values.max() else { return 0...1 }
        let pad = max(0.5, (hi - lo) * 0.25)
        return max(0, lo - pad)...(hi + pad)
    }
}

// MARK: - Janela de histórico

enum HistoryRange: String, CaseIterable, Identifiable {
    case day, week, month, year
    var id: Self { self }
    var label: String {
        switch self {
        case .day: "24 h"
        case .week: "7 dias"
        case .month: "30 dias"
        case .year: "1 ano"
        }
    }
    var duration: TimeInterval {
        switch self {
        case .day: 86_400
        case .week: 7 * 86_400
        case .month: 30 * 86_400
        case .year: 365 * 86_400
        }
    }
}

@MainActor
@Observable
final class HistoryViewState {
    var range: HistoryRange = .week { didSet { reload() } }
    var volumeID: String? { didSet { reload() } }
    private(set) var samples: [StorageSample] = []
    private(set) var forecast: Forecast?
    @ObservationIgnored let model: StorageModel

    init(model: StorageModel) {
        self.model = model
        volumeID = model.root?.id
        reload()
    }

    var volume: VolumeInfo? {
        model.localVolumes.first { $0.id == volumeID } ?? model.root
    }

    func reload() {
        guard let volume else { samples = []; forecast = nil; return }
        let now = Date.now
        samples = model.samples(for: volume, since: now.addingTimeInterval(-range.duration))
        let recent = model.samples(for: volume, since: now.addingTimeInterval(-Forecast.window))
        forecast = Forecast.compute(samples: recent, now: now)
    }
}

struct HistoryView: View {
    @Bindable var state: HistoryViewState
    /// Troca os controles do AppKit por texto, que o `ImageRenderer` consegue desenhar (imagens do README).
    var forSnapshot = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if forSnapshot { snapshotHeader } else { controls }

            if let volume = state.volume {
                stats(volume)
                chart(volume)
            }

            Text("Amostras a cada 5 min nas últimas 48 h, médias por hora até 60 dias e por dia depois disso. A previsão usa as últimas 2 semanas.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 440)
    }

    private var snapshotHeader: some View {
        HStack {
            Text(state.volume?.name ?? "").font(.title3.weight(.semibold))
            Spacer()
            HStack(spacing: 2) {
                ForEach(HistoryRange.allCases) { range in
                    Text(range.label)
                        .font(.callout)
                        .padding(.horizontal, 12).padding(.vertical, 4)
                        .background(range == state.range ? Color.white.opacity(0.18) : .clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(2)
            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var controls: some View {
            HStack {
                if state.model.localVolumes.count > 1 {
                    Picker("Volume", selection: $state.volumeID) {
                        ForEach(state.model.localVolumes) { Text($0.name).tag(Optional($0.id)) }
                    }
                    .fixedSize()
                } else if let volume = state.volume {
                    Text(volume.name).font(.title3.weight(.semibold))
                }
                Spacer()
                Picker("Período", selection: $state.range) {
                    ForEach(HistoryRange.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Button { state.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .help("Atualizar")
            }
    }

    @ViewBuilder
    private func stats(_ volume: VolumeInfo) -> some View {
        let level = state.model.level(of: volume)
        HStack(spacing: 12) {
            stat("Livre agora", ByteFormat.string(volume.freeBytes), color: level.color)
            stat("Variação no período", periodDelta ?? "—")
            stat("Ritmo (2 semanas)", state.forecast.map { $0.outcome == .stable || isCollecting ? "—" : $0.rateText } ?? "—")
            stat("Previsão", state.forecast?.summary() ?? "—")
        }
    }

    private var isCollecting: Bool {
        if case .collecting = state.forecast?.outcome { return true }
        return false
    }

    private var periodDelta: String? {
        guard let first = state.samples.first, let last = state.samples.last, state.samples.count >= 2 else { return nil }
        let bytes = last.freeBytes - first.freeBytes
        return "\(bytes < 0 ? "−" : "+")\(ByteFormat.string(abs(bytes)))"
    }

    private func stat(_ title: String, _ value: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).monospacedDigit().foregroundStyle(color).lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func chart(_ volume: VolumeInfo) -> some View {
        let level = state.model.level(of: volume)
        let thresholds = state.model.alertSettings.thresholds
        let totalGB = Double(volume.totalBytes) / 1e9

        if state.samples.count < 2 {
            ContentUnavailableView("Ainda sem histórico suficiente",
                                   systemImage: "chart.xyaxis.line",
                                   description: Text("O DiskNotch grava uma amostra a cada 5 minutos. O gráfico aparece a partir da segunda."))
                .frame(maxHeight: .infinity)
        } else {
            Chart {
                ForEach(state.samples, id: \.date) { s in
                    AreaMark(x: .value("Data", s.date), y: .value("Livre (GB)", Double(s.freeBytes) / 1e9))
                        .foregroundStyle(level.color.opacity(0.15).gradient)
                    LineMark(x: .value("Data", s.date), y: .value("Livre (GB)", Double(s.freeBytes) / 1e9))
                        .foregroundStyle(level.color)
                        .interpolationMethod(.monotone)
                }
                ForEach(projection, id: \.date) { p in
                    LineMark(x: .value("Data", p.date), y: .value("Livre (GB)", p.gb), series: .value("Série", "previsão"))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                }
                RuleMark(y: .value("Atenção", totalGB * thresholds.warningBelow))
                    .foregroundStyle(StorageLevel.warning.color.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("atenção").font(.caption2).foregroundStyle(StorageLevel.warning.color)
                    }
                RuleMark(y: .value("Crítico", totalGB * thresholds.criticalBelow))
                    .foregroundStyle(StorageLevel.critical.color.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("crítico").font(.caption2).foregroundStyle(StorageLevel.critical.color)
                    }
            }
            .chartYAxisLabel("GB livres")
            .chartYScale(domain: 0...yMax(totalGB: totalGB, warning: thresholds.warningBelow))
            .frame(maxHeight: .infinity)
        }
    }

    /// Linha tracejada da tendência, do último ponto até um quarto do período à frente.
    private var projection: [(date: Date, gb: Double)] {
        guard let forecast = state.forecast, forecast.bytesPerDay < 0,
              case .fullAt = forecast.outcome, let last = state.samples.last else { return [] }
        let ahead = state.range.duration / 4
        let end = last.date.addingTimeInterval(ahead)
        let endGB = max(0, (Double(last.freeBytes) + forecast.bytesPerDay * ahead / 86_400) / 1e9)
        return [(last.date, Double(last.freeBytes) / 1e9), (end, endGB)]
    }

    private func yMax(totalGB: Double, warning: Double) -> Double {
        let dataMax = state.samples.map { Double($0.freeBytes) / 1e9 }.max() ?? 0
        return max(dataMax, totalGB * warning) * 1.15
    }
}

/// Janela comum (não é painel), aberta pelo notch ou pelo menu.
@MainActor
final class HistoryWindowController {
    static let shared = HistoryWindowController()
    private var window: NSWindow?
    private var state: HistoryViewState?

    func show(model: StorageModel) {
        if let window, let state {
            state.reload()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let state = HistoryViewState(model: model)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 480),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        window.title = "Histórico de armazenamento"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: HistoryView(state: state))
        window.center()
        window.setFrameAutosaveName("DiskNotchHistory")
        self.window = window
        self.state = state
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
