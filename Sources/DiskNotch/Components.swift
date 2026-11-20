import SwiftUI
import StorageCore

extension StorageLevel {
    var color: Color {
        switch self {
        case .ok: Color(red: 0.30, green: 0.85, blue: 0.48)
        case .warning: Color(red: 1.00, green: 0.72, blue: 0.20)
        case .critical: Color(red: 1.00, green: 0.32, blue: 0.30)
        }
    }

    var label: String {
        switch self {
        case .ok: "Tudo certo"
        case .warning: "Espaço baixo"
        case .critical: "Espaço crítico"
        }
    }
}

/// Anel de ocupação do disco.
struct UsageRing: View {
    var fraction: Double
    var level: StorageLevel
    var lineWidth: CGFloat = 3

    var body: some View {
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
struct UsageBar: View {
    var volume: VolumeInfo
    var level: StorageLevel

    var body: some View {
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
struct NotchShape: Shape {
    var bottomRadius: CGFloat
    var topRadius: CGFloat = 6

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(bottomRadius, topRadius) }
        set { bottomRadius = newValue.first; topRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
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
