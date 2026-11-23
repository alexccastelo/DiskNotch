import Charts
import DiskNotchUI
import StorageCore
import SwiftUI
import WidgetKit

// MARK: - Dados

struct DiskEntry: TimelineEntry {
    let date: Date
    let volume: VolumeInfo?
    let level: StorageLevel
    let last24h: [StorageSample]
    let forecast: Forecast?

    static let placeholder = DiskEntry(
        date: .now,
        volume: VolumeInfo(id: "placeholder", name: "Macintosh HD", url: URL(fileURLWithPath: "/"),
                           totalBytes: 245_000_000_000, availableBytes: 60_000_000_000,
                           availableImportantBytes: 62_000_000_000, isRoot: true, isInternal: true,
                           isEjectable: false, isLocal: true),
        level: .ok, last24h: [], forecast: nil)
}

struct DiskProvider: TimelineProvider {
    func placeholder(in context: Context) -> DiskEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (DiskEntry) -> Void) {
        completion(context.isPreview ? .placeholder : Self.currentEntry())
    }

    /// O app também pede atualização quando grava amostras; isto é só a garantia.
    func getTimeline(in context: Context, completion: @escaping (Timeline<DiskEntry>) -> Void) {
        let entry = Self.currentEntry()
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(15 * 60))))
    }

    static func currentEntry(now: Date = .now) -> DiskEntry {
        let volume = VolumeService.rootVolume()
        let thresholds = Self.thresholds()
        let level = volume.map { StorageLevel(volume: $0, thresholds: thresholds) } ?? .ok

        var last24h: [StorageSample] = []
        var forecast: Forecast?
        if let volume, let store = try? HistoryStore(url: HistoryStore.sharedURL, readOnly: true) {
            let recent = (try? store.samples(volumeID: volume.id,
                                             since: now.addingTimeInterval(-Forecast.window))) ?? []
            forecast = Forecast.compute(samples: recent, now: now)
            last24h = recent.filter { $0.date >= now.addingTimeInterval(-86_400) }
        }
        return DiskEntry(date: now, volume: volume, level: level, last24h: last24h, forecast: forecast)
    }

    /// Lê os limites escolhidos no app (permissão de leitura das preferências do app).
    /// Faixas e cores escolhidas no app (permissão de leitura das preferências do app).
    static func thresholds() -> AlertThresholds {
        let prefs = UserDefaults(suiteName: ThresholdPreferences.suite)
        if let prefs { LevelAppearance.shared.reload(from: prefs) }
        return ThresholdPreferences.thresholds(from: prefs)
    }
}

// MARK: - Visual

struct DiskWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: DiskEntry

    var body: some View {
        Group {
            if let volume = entry.volume {
                switch family {
                case .systemSmall: small(volume)
                case .systemMedium: medium(volume)
                default: large(volume)
                }
            } else {
                Text("Disco não encontrado").foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .containerBackground(for: .widget) { Color.black }
        .widgetURL(URL(string: "disknotch://painel"))
    }

    // Pequeno: anel, GB livres e situação.
    private func small(_ v: VolumeInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                ring(v, size: 46, line: 6)
                Spacer()
                Image(systemName: "internaldrive").foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text(ByteFormat.compact(v.freeBytes))
                .font(.system(size: 22, weight: .bold, design: .rounded)).monospacedDigit()
                .minimumScaleFactor(0.7)
            Text("livres · \(entry.level.label)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(entry.level == .ok ? Color.secondary : entry.level.color)
                .lineLimit(1)
        }
    }

    // Médio: anel + números à esquerda, gráfico de 24 h e previsão à direita.
    private func medium(_ v: VolumeInfo) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                ring(v, size: 52, line: 7)
                Spacer(minLength: 0)
                Text(ByteFormat.compact(v.freeBytes))
                    .font(.system(size: 20, weight: .bold, design: .rounded)).monospacedDigit()
                Text("livres de \(ByteFormat.compact(v.totalBytes))")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .frame(width: 104, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                header(v)
                sparkline.frame(maxHeight: .infinity)
                forecastLine
            }
        }
    }

    // Grande: médio + barra de uso e detalhes.
    private func large(_ v: VolumeInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                ring(v, size: 70, line: 9)
                VStack(alignment: .leading, spacing: 4) {
                    header(v)
                    Text(ByteFormat.string(v.freeBytes))
                        .font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
                    Text("livres de \(ByteFormat.string(v.totalBytes))")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            UsageBar(volume: v, level: entry.level)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                GridRow { stat("Usado", v.usedBytes); stat("Purgável", v.purgeableBytes) }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Espaço livre · últimas 24 h").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                sparkline.frame(maxHeight: .infinity)
            }
            forecastLine
        }
    }

    // MARK: Peças

    private func ring(_ v: VolumeInfo, size: CGFloat, line: CGFloat) -> some View {
        ZStack {
            UsageRing(fraction: v.usedFraction, level: entry.level, lineWidth: line)
            Text("\(Int((v.usedFraction * 100).rounded()))%")
                .font(.system(size: size * 0.26, weight: .bold, design: .rounded))
        }
        .frame(width: size, height: size)
    }

    private func header(_ v: VolumeInfo) -> some View {
        HStack(spacing: 6) {
            Text(v.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            Text(entry.level.label)
                .font(.system(size: 9, weight: .semibold))
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(entry.level.color.opacity(0.2), in: Capsule())
                .foregroundStyle(entry.level.color)
        }
    }

    private func stat(_ title: String, _ bytes: Int64) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(ByteFormat.string(bytes)).font(.system(size: 12, weight: .semibold)).monospacedDigit()
        }
    }

    @ViewBuilder
    private var sparkline: some View {
        let samples = entry.last24h
        if samples.count >= 2 {
            let values = samples.map { Double($0.freeBytes) / 1e9 }
            let lo = values.min() ?? 0, hi = values.max() ?? 1
            let pad = max(0.5, (hi - lo) * 0.25)
            Chart(samples, id: \.date) { s in
                AreaMark(x: .value("Hora", s.date), y: .value("Livre", Double(s.freeBytes) / 1e9))
                    .foregroundStyle(entry.level.color.opacity(0.18).gradient)
                LineMark(x: .value("Hora", s.date), y: .value("Livre", Double(s.freeBytes) / 1e9))
                    .foregroundStyle(entry.level.color)
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: max(0, lo - pad)...(hi + pad))
            .chartPlotStyle { $0.clipped() }
        } else {
            RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.06))
                .overlay(Text("Gráfico em breve").font(.system(size: 9)).foregroundStyle(.tertiary))
        }
    }

    private var forecastLine: some View {
        let filling: Bool = { if case .fullAt = entry.forecast?.outcome { true } else { false } }()
        return Label(entry.forecast?.summary(now: entry.date) ?? "Coletando dados",
                     systemImage: "chart.line.downtrend.xyaxis")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(filling ? entry.level.color : Color.secondary)
            .lineLimit(1)
    }
}

// MARK: - Widget

struct DiskWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DiskNotchDisk", provider: DiskProvider()) { entry in
            DiskWidgetView(entry: entry)
        }
        .configurationDisplayName("Armazenamento")
        .description("Espaço livre do disco de inicialização, tendência das últimas 24 h e previsão.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct DiskNotchWidgets: WidgetBundle {
    var body: some Widget { DiskWidget() }
}
