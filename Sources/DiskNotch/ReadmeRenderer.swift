import AppKit
import DiskNotchUI
import StorageCore
import SwiftUI

/// Gera as imagens do README a partir das telas reais do app, com os dados de demonstração.
///
///     DiskNotch.app/Contents/MacOS/DiskNotch --render-readme-images docs/design
@MainActor
enum ReadmeRenderer {
    static func run(outputDirectory: URL) -> Bool {
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let model = StorageModel(demo: true)
        let geometry = NotchGeometry(notchWidth: 186, notchHeight: 32, hasNotch: true, side: .left)

        let expanded = NotchState(geometry: geometry)
        expanded.isExpanded = true
        let collapsed = NotchState(geometry: geometry)

        var ok = true
        ok = write(Banner(model: model), named: "disknotch-banner.png", in: outputDirectory) && ok
        ok = write(Screen(height: 300) { NotchView(state: expanded, model: model, openSettings: {}) },
                   named: "notch-expandido.png", in: outputDirectory) && ok
        ok = write(Screen(height: 90) { NotchView(state: collapsed, model: model, openSettings: {}) },
                   named: "notch-recolhido.png", in: outputDirectory) && ok
        let history = HistoryViewState(model: model)
        history.range = .month
        ok = write(HistoryView(state: history, forSnapshot: true)
                    .frame(width: 760, height: 500)
                    .background(Color(nsColor: .windowBackgroundColor))
                    .environment(\.colorScheme, .dark),
                   named: "historico.png", in: outputDirectory) && ok

        // Páginas do painel completo.
        let dashboard = DashboardState(model: model)
        for (section, name, height) in [(DashboardSection.overview, "painel-visao-geral.png", 640.0),
                                        (.cleanup, "painel-limpeza.png", 700.0),
                                        (.development, "painel-desenvolvimento.png", 900.0)] {
            dashboard.section = section
            ok = write(DashboardDetail(model: model, state: dashboard)
                        .environment(\.isSnapshot, true)
                        .frame(width: 860)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: 860, height: height, alignment: .top)
                        .clipped()
                        .background(Color(nsColor: .windowBackgroundColor))
                        .environment(\.colorScheme, .dark),
                       named: name, in: outputDirectory) && ok
        }
        return ok
    }

    private static func write<V: View>(_ view: V, named name: String, in directory: URL) -> Bool {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            print("falhou: \(name)")
            return false
        }
        do {
            try data.write(to: directory.appendingPathComponent(name))
            print("gerado: \(directory.appendingPathComponent(name).path) (\(image.width)×\(image.height))")
            return true
        } catch {
            print("falhou: \(name) — \(error)")
            return false
        }
    }
}

/// Fundo que imita o topo da tela, com o notch centralizado.
private struct Screen<Content: View>: View {
    var height: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.16, green: 0.20, blue: 0.36), Color(red: 0.36, green: 0.22, blue: 0.42)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Rectangle().fill(.black.opacity(0.18)).frame(height: 32)
            content().frame(width: 640, height: 260)
        }
        .frame(width: 900, height: height, alignment: .top)
        .clipped()
    }
}

/// Banner do topo do README: anel, nome em fonte arredondada e frase de apresentação.
private struct Banner: View {
    var model: StorageModel

    var body: some View {
        let root = model.root
        let level = root.map { model.level(of: $0) } ?? .ok
        HStack(spacing: 36) {
            ZStack {
                UsageRing(fraction: root?.usedFraction ?? 0.8, level: level, lineWidth: 16)
                Image(systemName: "internaldrive.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(width: 140, height: 140)

            VStack(alignment: .leading, spacing: 10) {
                Text("DiskNotch")
                    .font(.system(size: 92, weight: .heavy, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: [.white, Color(white: 0.78)],
                                                    startPoint: .top, endPoint: .bottom))
                Text("O espaço do seu Mac, sempre à vista no notch.")
                    .font(.system(size: 26, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 64)
        .frame(width: 1100, height: 320)
        .background(
            RoundedRectangle(cornerRadius: 36)
                .fill(LinearGradient(colors: [Color(red: 0.07, green: 0.08, blue: 0.12), Color(red: 0.13, green: 0.10, blue: 0.20)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .environment(\.colorScheme, .dark)
    }
}
