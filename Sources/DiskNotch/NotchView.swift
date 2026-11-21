import SwiftUI
import StorageCore

/// Lado do notch onde fica a informação no estado recolhido.
enum NotchSide: String, CaseIterable {
    case left, right
    var label: String { self == .left ? "Esquerda" : "Direita" }
}

/// Geometria do notch da tela atual, calculada pelo controlador.
struct NotchGeometry: Equatable {
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var hasNotch: Bool
    var side: NotchSide = .left

    /// "Orelhas" côncavas que fundem a forma com a moldura (igual a `NotchShape.topRadius`).
    static let ear: CGFloat = 6
    /// Largura que a informação ocupa além do notch, só de um lado.
    static let wing: CGFloat = 78
    static let expandedSize = CGSize(width: 560, height: 210)

    /// Recolhido: notch + informação de um lado só. O outro lado não passa da borda do notch,
    /// para não cobrir os ícones da barra de menus.
    var collapsedSize: CGSize {
        CGSize(width: notchWidth + Self.wing + 2 * Self.ear, height: notchHeight)
    }

    /// Deslocamento horizontal da forma recolhida em relação ao centro do notch.
    var collapsedOffsetX: CGFloat { side == .left ? -Self.wing / 2 : Self.wing / 2 }
}

@MainActor
@Observable
final class NotchState {
    var isExpanded = false
    var geometry: NotchGeometry
    // Guardado aqui (e não em @State) porque as Command Line Tools não trazem o plugin de macros do SwiftUI.
    @ObservationIgnored var collapseTask: Task<Void, Never>?
    init(geometry: NotchGeometry) { self.geometry = geometry }
}

struct NotchView: View {
    @Bindable var state: NotchState
    var model: StorageModel
    var openSettings: () -> Void

    var body: some View {
        let geo = state.geometry
        let size = state.isExpanded ? NotchGeometry.expandedSize : geo.collapsedSize

        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                NotchShape(bottomRadius: state.isExpanded ? 24 : 10)
                    .fill(.black)

                if state.isExpanded {
                    ExpandedContent(model: model, topInset: geo.notchHeight, openSettings: openSettings)
                        .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                } else {
                    CollapsedContent(model: model, geometry: geo)
                        .transition(.opacity)
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(NotchShape(bottomRadius: 24))
            .onHover(perform: hover)
            .onTapGesture { setExpanded(!state.isExpanded) }
            .shadow(color: .black.opacity(state.isExpanded ? 0.35 : 0), radius: 12, y: 4)
            .offset(x: state.isExpanded ? 0 : geo.collapsedOffsetX)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func hover(_ inside: Bool) {
        state.collapseTask?.cancel()
        if inside {
            setExpanded(true)
        } else {
            // Pequeno atraso para não fechar quando o mouse passa pela borda.
            state.collapseTask = Task {
                try? await Task.sleep(for: .milliseconds(350))
                if !Task.isCancelled { setExpanded(false) }
            }
        }
    }

    private func setExpanded(_ value: Bool) {
        guard value != state.isExpanded else { return }
        if value { model.refresh() }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.78)) {
            state.isExpanded = value
        }
    }
}

// MARK: - Recolhido

private struct CollapsedContent: View {
    var model: StorageModel
    var geometry: NotchGeometry

    var body: some View {
        if let root = model.root {
            let ring = UsageRing(fraction: root.usedFraction, level: model.level(of: root), lineWidth: 3)
                .frame(width: 14, height: 14)
            let text = Text(ByteFormat.compact(root.freeBytes))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .foregroundStyle(model.level(of: root) == .ok ? .white : model.level(of: root).color)

            HStack(spacing: 0) {
                if geometry.side == .left {
                    HStack(spacing: 6) { ring; text; Spacer(minLength: 0) }
                        .padding(.leading, 10)
                        .frame(width: NotchGeometry.wing)
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 0)
                    HStack(spacing: 6) { Spacer(minLength: 0); text; ring }
                        .padding(.trailing, 10)
                        .frame(width: NotchGeometry.wing)
                }
            }
            .padding(.horizontal, NotchGeometry.ear)
            .frame(height: geometry.notchHeight)
        }
    }
}

// MARK: - Expandido

private struct ExpandedContent: View {
    var model: StorageModel
    var topInset: CGFloat
    var openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let root = model.root {
                HStack(alignment: .center, spacing: 18) {
                    ZStack {
                        UsageRing(fraction: root.usedFraction, level: model.level(of: root), lineWidth: 8)
                        VStack(spacing: 0) {
                            Text("\(Int((root.usedFraction * 100).rounded()))%")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                            Text("usado").font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 84, height: 84)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text(root.name).font(.system(size: 13, weight: .semibold))
                            Text(model.level(of: root).label)
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(model.level(of: root).color.opacity(0.2), in: Capsule())
                                .foregroundStyle(model.level(of: root).color)
                        }
                        UsageBar(volume: root, level: model.level(of: root))
                        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 3) {
                            row("Livre", root.freeBytes, color: .white)
                            row("Purgável", root.purgeableBytes, color: model.level(of: root).color.opacity(0.6))
                            row("Usado", root.usedBytes, color: model.level(of: root).color)
                            row("Total", root.totalBytes, color: .white.opacity(0.4))
                        }
                    }

                    HistoryCard(samples: model.rootLast24h, forecast: model.rootForecast,
                                level: model.level(of: root))
                        .frame(width: 176)
                        .onTapGesture { HistoryWindowController.shared.show(model: model) }
                        .help("Abrir o histórico")
                }
            }

            if !model.externalVolumes.isEmpty {
                Divider().overlay(.white.opacity(0.15))
                VStack(spacing: 6) {
                    ForEach(model.externalVolumes) { v in
                        HStack(spacing: 8) {
                            Image(systemName: v.isLocal ? "externaldrive.fill" : "server.rack")
                                .foregroundStyle(.secondary)
                            Text(v.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            UsageBar(volume: v, level: model.level(of: v)).frame(width: 120)
                            Text("\(ByteFormat.compact(v.freeBytes)) livres")
                                .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                            Spacer()
                            if v.isEjectable {
                                Button { model.eject(v) } label: { Image(systemName: "eject.fill") }
                                    .buttonStyle(.plain).help("Ejetar \(v.name)")
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            HStack {
                if let date = model.lastUpdated {
                    Text("Atualizado \(date.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                Spacer()
                Button { model.refresh() } label: { Label("Atualizar", systemImage: "arrow.clockwise") }
                Button { HistoryWindowController.shared.show(model: model) } label: {
                    Label("Histórico", systemImage: "chart.xyaxis.line")
                }
                Button { if let r = model.root { model.revealInFinder(r) } } label: {
                    Label("Finder", systemImage: "folder")
                }
                Button(action: openSettings) { Label("Ajustes", systemImage: "gearshape") }
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
        }
        .foregroundStyle(.white)
        .padding(.top, topInset + 10)
        .padding(.horizontal, 26)
        .padding(.bottom, 14)
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private func row(_ title: String, _ bytes: Int64, color: Color) -> some View {
        GridRow {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Text(ByteFormat.string(bytes)).font(.system(size: 11, weight: .medium)).monospacedDigit()
        }
    }
}
