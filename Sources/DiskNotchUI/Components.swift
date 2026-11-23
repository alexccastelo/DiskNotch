import SwiftUI
import StorageCore

extension StorageLevel {
    /// Cor do nível, escolhida pelo usuário nos ajustes (ver `LevelAppearance`).
    public var color: Color { LevelAppearance.shared.color(for: self) }

    public var label: String {
        switch self {
        case .ok: "Tudo certo"
        case .warning: "Espaço baixo"
        case .critical: "Espaço crítico"
        }
    }
}

/// Anel de ocupação do disco.
public struct UsageRing: View {
    public var fraction: Double
    public var level: StorageLevel
    public var lineWidth: CGFloat = 3

    public init(fraction: Double, level: StorageLevel, lineWidth: CGFloat = 3) {
        self.fraction = fraction
        self.level = level
        self.lineWidth = lineWidth
    }

    public var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, fraction)))
                .stroke(level.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.easeOut(duration: 0.4), value: fraction)
    }
}

/// Barra horizontal empilhada: usado | purgável | livre.
public struct UsageBar: View {
    public var volume: VolumeInfo
    public var level: StorageLevel

    public init(volume: VolumeInfo, level: StorageLevel) {
        self.volume = volume
        self.level = level
    }

    public var body: some View {
        GeometryReader { geo in
            let total = max(1, Double(volume.totalBytes))
            let usedW = geo.size.width * Double(volume.usedBytes) / total
            let purgeW = geo.size.width * Double(volume.purgeableBytes) / total
            HStack(spacing: 0) {
                Rectangle().fill(level.color).frame(width: usedW)
                Rectangle().fill(level.color.opacity(0.35)).frame(width: purgeW)
                Rectangle().fill(.white.opacity(0.12))
            }
            .clipShape(Capsule())
        }
        .frame(height: 6)
    }
}

/// Formato do notch: topo reto, cantos inferiores arredondados
/// e "orelhas" côncavas no topo para fundir com a moldura da tela.
public struct NotchShape: Shape {
    public var bottomRadius: CGFloat
    public var topRadius: CGFloat = 6

    public init(bottomRadius: CGFloat, topRadius: CGFloat = 6) {
        self.bottomRadius = bottomRadius
        self.topRadius = topRadius
    }

    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(bottomRadius, topRadius) }
        set { bottomRadius = newValue.first; topRadius = newValue.second }
    }

    public func path(in rect: CGRect) -> Path {
        var p = Path()
        let t = topRadius
        let b = min(bottomRadius, rect.height / 2, (rect.width - 2 * t) / 2)
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY + t),
                       control: CGPoint(x: rect.minX + t, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t + b, y: rect.maxY),
                       control: CGPoint(x: rect.minX + t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b),
                       control: CGPoint(x: rect.maxX - t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.maxX - t, y: rect.minY))
        p.closeSubpath()
        return p
    }
}
