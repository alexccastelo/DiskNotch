import StorageCore
import SwiftUI

/// Bloco de um treemap.
public struct TreemapItem: Identifiable, Sendable {
    public var id: String
    public var label: String
    public var bytes: Int64
    public var color: Color

    public init(id: String, label: String, bytes: Int64, color: Color) {
        self.id = id
        self.label = label
        self.bytes = bytes
        self.color = color
    }
}

/// Mapa visual: cada bloco tem área proporcional ao espaço que ocupa.
public struct TreemapView: View {
    var items: [TreemapItem]
    var onTap: ((TreemapItem) -> Void)?

    public init(items: [TreemapItem], onTap: ((TreemapItem) -> Void)? = nil) {
        self.items = items
        self.onTap = onTap
    }

    public var body: some View {
        GeometryReader { geo in
            let rects = Treemap.layout(items.map { Double($0.bytes) }, in: CGRect(origin: .zero, size: geo.size))
            ZStack(alignment: .topLeading) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    let rect = rects[index]
                    if rect.width > 1, rect.height > 1 {
                        block(item, size: rect.size)
                            .frame(width: rect.width, height: rect.height)
                            .offset(x: rect.minX, y: rect.minY)
                    }
                }
            }
        }
    }

    private func block(_ item: TreemapItem, size: CGSize) -> some View {
        let showLabel = size.width > 64 && size.height > 34
        return RoundedRectangle(cornerRadius: 6)
            .fill(item.color.gradient)
            .padding(1.5)
            .overlay(alignment: .topLeading) {
                if showLabel {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.label).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                        Text(ByteFormat.string(item.bytes)).font(.system(size: 10)).monospacedDigit().opacity(0.85)
                    }
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)
                    .padding(7)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onTap?(item) }
            .help("\(item.label) — \(ByteFormat.string(item.bytes))")
    }
}

/// Paleta das categorias, estável por identificador.
public enum CategoryPalette {
    public static func color(for id: String) -> Color {
        switch id {
        case "development": Color(red: 0.36, green: 0.42, blue: 0.95)
        case "apps": Color(red: 0.20, green: 0.62, blue: 0.95)
        case "documents": Color(red: 0.18, green: 0.72, blue: 0.62)
        case "photos": Color(red: 0.93, green: 0.45, blue: 0.55)
        case "movies": Color(red: 0.80, green: 0.36, blue: 0.80)
        case "music": Color(red: 0.98, green: 0.38, blue: 0.40)
        case "downloads": Color(red: 0.98, green: 0.62, blue: 0.20)
        case "desktop": Color(red: 0.55, green: 0.70, blue: 0.30)
        case "icloud": Color(red: 0.35, green: 0.75, blue: 0.95)
        case "mail": Color(red: 0.25, green: 0.55, blue: 0.85)
        case "messages": Color(red: 0.30, green: 0.80, blue: 0.40)
        case "caches": Color(red: 0.62, green: 0.55, blue: 0.45)
        case "trash": Color(red: 0.55, green: 0.55, blue: 0.58)
        case "library": Color(red: 0.50, green: 0.45, blue: 0.70)
        case "home": Color(red: 0.42, green: 0.55, blue: 0.62)
        case "system": Color(red: 0.40, green: 0.40, blue: 0.44)
        default: Color(red: 0.45, green: 0.50, blue: 0.60)
        }
    }

    /// Cores para listas sem identidade fixa (pastas).
    public static func color(at index: Int) -> Color {
        let colors: [Color] = [
            Color(red: 0.36, green: 0.42, blue: 0.95), Color(red: 0.18, green: 0.72, blue: 0.62),
            Color(red: 0.93, green: 0.45, blue: 0.55), Color(red: 0.98, green: 0.62, blue: 0.20),
            Color(red: 0.20, green: 0.62, blue: 0.95), Color(red: 0.80, green: 0.36, blue: 0.80),
            Color(red: 0.55, green: 0.70, blue: 0.30), Color(red: 0.50, green: 0.45, blue: 0.70),
        ]
        return colors[index % colors.count]
    }
}
