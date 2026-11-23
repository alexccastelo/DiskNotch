import CoreGraphics

/// Layout "squarified" de treemap (Bruls, Huizing e van Wijk, 2000): divide um retângulo
/// em blocos com área proporcional a cada valor, mantendo os blocos o mais quadrados possível.
public enum Treemap {
    /// Retorna um retângulo por valor, na mesma ordem de `values`. Valores ≤ 0 recebem `.zero`.
    public static func layout(_ values: [Double], in rect: CGRect) -> [CGRect] {
        var result = Array(repeating: CGRect.zero, count: values.count)
        let total = values.filter { $0 > 0 }.reduce(0, +)
        guard total > 0, rect.width > 0, rect.height > 0 else { return result }

        // Escala para que a soma das áreas seja a área do retângulo; maiores primeiro.
        let scale = Double(rect.width * rect.height) / total
        var items = values.enumerated()
            .filter { $0.element > 0 }
            .map { (index: $0.offset, area: $0.element * scale) }
            .sorted { $0.area > $1.area }

        var free = rect
        while !items.isEmpty {
            let side = Double(min(free.width, free.height))
            var row: [(index: Int, area: Double)] = []
            // Acrescenta à fileira enquanto a pior proporção não piorar.
            while let next = items.first {
                let candidate = row + [next]
                if row.isEmpty || worst(candidate.map(\.area), side: side) <= worst(row.map(\.area), side: side) {
                    row = candidate
                    items.removeFirst()
                } else {
                    break
                }
            }
            free = place(row, in: free, into: &result)
        }
        return result
    }

    /// Maior razão entre os lados dos blocos de uma fileira encostada num lado de tamanho `side`.
    static func worst(_ areas: [Double], side: Double) -> Double {
        let sum = areas.reduce(0, +)
        guard let maxArea = areas.max(), let minArea = areas.min(), sum > 0, side > 0 else { return .infinity }
        let s2 = side * side, sum2 = sum * sum
        return max(s2 * maxArea / sum2, sum2 / (s2 * minArea))
    }

    /// Coloca a fileira ao longo do lado menor e devolve o espaço que sobra.
    private static func place(_ row: [(index: Int, area: Double)], in free: CGRect, into result: inout [CGRect]) -> CGRect {
        let sum = row.reduce(0) { $0 + $1.area }
        if free.width >= free.height {
            // Coluna à esquerda.
            let width = CGFloat(sum / Double(free.height))
            var y = free.minY
            for item in row {
                let height = CGFloat(item.area / Double(width))
                result[item.index] = CGRect(x: free.minX, y: y, width: width, height: height)
                y += height
            }
            return CGRect(x: free.minX + width, y: free.minY, width: max(0, free.width - width), height: free.height)
        } else {
            // Linha no topo.
            let height = CGFloat(sum / Double(free.width))
            var x = free.minX
            for item in row {
                let width = CGFloat(item.area / Double(height))
                result[item.index] = CGRect(x: x, y: free.minY, width: width, height: height)
                x += width
            }
            return CGRect(x: free.minX, y: free.minY + height, width: free.width, height: max(0, free.height - height))
        }
    }
}
