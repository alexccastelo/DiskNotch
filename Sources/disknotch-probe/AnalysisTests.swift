import CoreGraphics
import Foundation
import StorageCore

/// Testes da varredura, do catálogo de desenvolvimento, das categorias e do treemap,
/// sobre uma pasta pessoal falsa com tamanhos conhecidos.
enum AnalysisSelfTest {
    static func run() async -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            if !ok { failures += 1 }
            print("\(ok ? "ok  " : "FALHA") \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        }

        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("disknotch-casa-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: home) }
        let mb = 1_000_000

        var expected: Int64 = 0
        var allocated: [String: Int64] = [:]
        @discardableResult
        func write(_ relative: String, bytes: Int) -> Int64 {
            let url = home.appendingPathComponent(relative)
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Bytes aleatórios: o APFS não economiza espaço com eles.
            var data = Data(count: bytes)
            data.withUnsafeMutableBytes { _ = SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!) }
            try? data.write(to: url)
            let size = Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
            expected += size
            allocated[url.path] = size
            return size
        }

        // Projeto Node com node_modules (inclui um node_modules aninhado, que não pode contar duas vezes).
        write("Documents/site/package.json", bytes: 200)
        let nm1 = write("Documents/site/node_modules/react/index.js", bytes: 3 * mb)
        let nm2 = write("Documents/site/node_modules/pkg/package.json", bytes: 300)
        let nm3 = write("Documents/site/node_modules/pkg/node_modules/dep/lib.js", bytes: 1 * mb)
        let src = write("Documents/site/src/app.js", bytes: 1 * mb)
        // Ambiente Python.
        let venvCfg = write("Documents/api/.venv/pyvenv.cfg", bytes: 100)
        let venvLib = write("Documents/api/.venv/lib/python3/site.py", bytes: 2 * mb)
        // Pasta chamada "target" sem Cargo.toml: não é artefato.
        write("Documents/livro/target/capa.png", bytes: 1 * mb)
        // Caches.
        let pip = write("Library/Caches/pip/wheels/a.whl", bytes: 3 * mb)
        let otherCache = write("Library/Caches/com.exemplo.app/cache.db", bytes: 1 * mb)
        write(".npm/_cacache/x", bytes: 2 * mb)
        // node_modules dentro de cache de ferramenta (npx): não é pasta de projeto.
        write(".npm/_npx/abc/package.json", bytes: 100)
        write(".npm/_npx/abc/node_modules/x/index.js", bytes: 1 * mb)
        let npmAll = allocated.filter { $0.key.contains("/.npm/") }.values.reduce(0, +)
        // Pasta de serviço de nuvem: não pode ser percorrida.
        write("Library/CloudStorage/GoogleDrive-voce/Meu Drive/backup.zip", bytes: 2 * mb)
        let cloudBytes = allocated.first { $0.key.contains("CloudStorage") }!.value
        expected -= cloudBytes
        // Arquivo grande em Downloads.
        let big = write("Downloads/instalador.dmg", bytes: 6 * mb)
        // Link simbólico para Documentos: não pode ser seguido.
        try? fm.createSymbolicLink(at: home.appendingPathComponent("Atalho"), withDestinationURL: home.appendingPathComponent("Documents"))
        expected += Int64((try? home.appendingPathComponent("Atalho").resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)

        let homePath = home.standardizedFileURL.path
        var options = AnalysisDefaults.options(home: homePath)
        options.treeThreshold = 1 * Int64(mb)
        options.topFileMinimum = 5 * Int64(mb)
        let progress = ScanProgress()
        do {
            let report = try await DiskScanner.scan(roots: [home], options: options, progress: progress)
            let total = report.roots[homePath] ?? -1

            check("total soma todos os arquivos, sem seguir o link", total == expected, "\(total) de \(expected) bytes")
            check("pasta de nuvem pulada e registrada", report.skipped == [homePath + "/Library/CloudStorage"], report.skipped.joined(separator: ", "))
            check("progresso acompanha a varredura", progress.snapshot().fileCount >= 12, "\(progress.snapshot().fileCount) arquivos")

            let kinds = report.artifacts.map(\.kind)
            check("node_modules e .venv detectados, sem o aninhado nem o falso target",
                  kinds.sorted { $0.rawValue < $1.rawValue } == [.nodeModules, .pythonVenv],
                  report.artifacts.map { "\($0.kind.rawValue)=\($0.bytes)" }.joined(separator: ", "))
            let node = report.artifacts.first { $0.kind == .nodeModules }
            check("node_modules inclui o aninhado", node?.bytes == nm1 + nm2 + nm3)
            check("nome do projeto", node?.projectName == "site", node?.projectName ?? "nil")
            check(".venv com o tamanho certo", report.artifacts.first { $0.kind == .pythonVenv }?.bytes == venvCfg + venvLib)

            check("maiores arquivos", report.topFiles.map(\.name) == ["instalador.dmg"], report.topFiles.map(\.name).joined(separator: ", "))

            let dev = DevSummary(report: report, home: homePath)
            let devByID = Dictionary(uniqueKeysWithValues: dev.items.map { ($0.item.id, $0.bytes) })
            check("catálogo: pip e npm medidos", devByID["pip"] == pip && devByID["npm"] == npmAll,
                  devByID.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ", "))

            let breakdown = CategoryBreakdown(report: report, home: homePath, usedBytes: nil)
            let byID = Dictionary(uniqueKeysWithValues: breakdown.slices.map { ($0.id, $0.bytes) })
            let devExpected = pip + npmAll + nm1 + nm2 + nm3 + venvCfg + venvLib
            check("Desenvolvimento = catálogo + pastas de projeto", byID[StorageCategory.developmentID] == devExpected,
                  "\(byID[StorageCategory.developmentID] ?? 0) de \(devExpected)")
            check("Caches sem o pip", byID["caches"] == otherCache, "\(byID["caches"] ?? 0)")
            let documentsExpected = Int64(allocated.filter { $0.key.contains("/Documents/") }.values.reduce(0, +))
                - (nm1 + nm2 + nm3 + venvCfg + venvLib)
            check("Documentos sem node_modules nem .venv", byID["documents"] == documentsExpected,
                  "\(byID["documents"] ?? 0) de \(documentsExpected) (inclui \(src) de código)")
            check("Downloads", byID["downloads"] == big)
            check("categorias somam o total, sem contar nada duas vezes", breakdown.totalBytes == total,
                  "\(breakdown.totalBytes) de \(total)")

            let withSystem = CategoryBreakdown(report: report, home: homePath, usedBytes: total + 50 * Int64(mb))
            check("o resto do volume vira Sistema e outros",
                  withSystem.slices.first { $0.id == StorageCategory.systemID }?.bytes == 50 * Int64(mb))

            // Varredura cancelada no meio.
            let task = Task { try await DiskScanner.scan(roots: [home], options: options) }
            task.cancel()
            let cancelled: Bool
            do { _ = try await task.value; cancelled = false } catch is CancellationError { cancelled = true } catch { cancelled = false }
            check("varredura cancelável", cancelled)
        } catch {
            check("varredura", false, "\(error)")
        }

        // Treemap.
        let values: [Double] = [6, 6, 4, 3, 2, 2, 1, 0]
        let rect = CGRect(x: 0, y: 0, width: 600, height: 400)
        let rects = Treemap.layout(values, in: rect)
        let scale = Double(rect.width * rect.height) / values.reduce(0, +)
        let proportional = zip(values, rects).allSatisfy { v, r in abs(Double(r.width * r.height) - v * scale) < 1 }
        let inside = rects.allSatisfy { $0 == .zero || rect.insetBy(dx: -0.01, dy: -0.01).contains($0) }
        var overlap = false
        for i in rects.indices { for j in rects.indices where j > i {
            let x = rects[i].intersection(rects[j])
            if !x.isNull, x.width > 0.01, x.height > 0.01 { overlap = true }
        } }
        let worstRatio = rects.filter { $0 != .zero }.map { max($0.width / $0.height, $0.height / $0.width) }.max() ?? 0
        check("treemap: áreas proporcionais", proportional)
        check("treemap: dentro do retângulo e sem sobreposição", inside && !overlap)
        check("treemap: blocos razoavelmente quadrados", worstRatio < 4, String(format: "pior proporção %.2f", worstRatio))
        check("treemap: valor zero fica vazio", rects.last == .zero)

        print(failures == 0 ? "\nTodos os casos passaram." : "\n\(failures) caso(s) falharam.")
        return failures == 0
    }
}

/// Análise real da pasta pessoal, de /Applications e de /opt/homebrew, com tempo e resumo.
enum RealAnalysis {
    static func run() async {
        setvbuf(stdout, nil, _IOLBF, 0)   // uma linha por vez, mesmo redirecionado
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        let roots = AnalysisDefaults.roots(home: home)
        let progress = ScanProgress()
        let ticker = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                let s = progress.snapshot()
                print("  … \(s.fileCount) arquivos, \(ByteFormat.string(s.bytes))")
            }
        }
        print("Acesso Total ao Disco: \(FullDiskAccess.isGranted ? "sim" : "não")")
        do {
            let report = try await DiskScanner.scan(roots: roots,
                                                    options: AnalysisDefaults.options(home: home),
                                                    progress: progress)
            ticker.cancel()
            print(String(format: "\nVarredura: %.1f s, %d arquivos, %d pastas sem acesso", report.duration, report.fileCount, report.unreadableCount))
            let used = VolumeService.rootVolume()?.usedBytes
            print("\nCategorias:")
            for s in CategoryBreakdown(report: report, home: home, usedBytes: used).slices {
                print("  \(s.name.padding(toLength: 26, withPad: " ", startingAt: 0)) \(ByteFormat.string(s.bytes))\(s.partial ? "  (parcial)" : "")")
            }
            let dev = DevSummary(report: report, home: home)
            print("\nDesenvolvimento: \(ByteFormat.string(dev.totalBytes)) (caches: \(ByteFormat.string(dev.cacheBytes)))")
            for r in dev.items.prefix(12) {
                print("  \(r.item.name.padding(toLength: 34, withPad: " ", startingAt: 0)) \(ByteFormat.string(r.bytes))")
            }
            print("\nPastas de projeto: \(report.artifacts.count), \(ByteFormat.string(dev.artifactsBytes))")
            for a in report.artifacts.prefix(8) {
                print("  \(a.kind.rawValue.padding(toLength: 12, withPad: " ", startingAt: 0)) \(ByteFormat.string(a.bytes).padding(toLength: 10, withPad: " ", startingAt: 0)) \(a.projectPath.replacingOccurrences(of: home, with: "~"))")
            }
            print("\nMaiores arquivos:")
            for f in report.topFiles.prefix(8) {
                print("  \(ByteFormat.string(f.bytes).padding(toLength: 10, withPad: " ", startingAt: 0)) \(f.path.replacingOccurrences(of: home, with: "~"))")
            }
            let json = try JSONEncoder().encode(report)
            if !report.skipped.isEmpty {
                print("\nPuladas (nuvem ou sem cópia local): \(report.skipped.count)")
                for p in report.skipped.prefix(6) { print("  \(p.replacingOccurrences(of: home, with: "~"))") }
            }
            print("\nRelatório em JSON: \(ByteFormat.string(Int64(json.count))), \(report.children.count) pastas na árvore")
        } catch {
            ticker.cancel()
            print("erro: \(error)")
        }
    }
}
