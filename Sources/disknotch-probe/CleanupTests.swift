import Foundation
import StorageCore

/// Testes das regras de limpeza: o que é oferecido e o que é recusado antes de ir para o Lixo.
enum CleanupSelfTest {
    static func run() -> Bool {
        var failures = 0
        func check(_ name: String, _ ok: Bool, _ detail: String = "") {
            if !ok { failures += 1 }
            print("\(ok ? "ok  " : "FALHA") \(name)\(detail.isEmpty ? "" : " — \(detail)")")
        }

        let fm = FileManager.default
        let home = fm.temporaryDirectory.appendingPathComponent("disknotch-limpeza-\(UUID().uuidString)").path
        defer { try? fm.removeItem(atPath: home) }
        func h(_ p: String) -> String { (home as NSString).appendingPathComponent(p) }
        let gb: Int64 = 1_000_000_000
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        // Varredura fictícia: npm (cache com comando), DerivedData (cache sem comando),
        // Docker (revisar), Hugging Face (recriável sem comando) e duas pastas de projeto.
        let report = ScanReport(
            measured: [h(".npm"): 3 * gb, h("Library/Developer/Xcode/DerivedData"): 8 * gb,
                       h("Library/Containers/com.docker.docker"): 20 * gb, h(".cache/huggingface"): 4 * gb,
                       h("Library/Caches/pip"): 10_000_000],
            artifacts: [
                ProjectArtifact(kind: .nodeModules, path: h("projetos/antigo/node_modules"), bytes: 2 * gb,
                                modified: now.addingTimeInterval(-90 * 86_400)),
                ProjectArtifact(kind: .nodeModules, path: h("projetos/atual/node_modules"), bytes: 1 * gb,
                                modified: now.addingTimeInterval(-2 * 86_400)),
            ])
        let summary = DevSummary(report: report, home: home)

        let withNpm = CleanupPlanner.options(for: summary, availableTools: ["npm"], now: now)
        let byID = Dictionary(uniqueKeysWithValues: withNpm.map { ($0.id, $0) })
        check("npm instalado: oferece o comando oficial",
              byID["dev:npm"]?.method == .command("npm cache clean --force", tool: "npm"))
        let withoutNpm = CleanupPlanner.options(for: summary, availableTools: [], now: now)
        check("npm ausente: cache vai para o Lixo", withoutNpm.first { $0.id == "dev:npm" }?.method == .trash)
        check("DerivedData: Lixo e sugerido", byID["dev:xcode-deriveddata"]?.method == .trash && byID["dev:xcode-deriveddata"]?.suggested == true)
        check("Docker (revisar antes): nenhuma ação", byID["dev:docker"] == nil)
        check("Hugging Face (recriável): Lixo, mas não sugerido",
              byID["dev:huggingface"]?.method == .trash && byID["dev:huggingface"]?.suggested == false)
        check("cache pequeno (10 MB): não sugerido", byID["dev:pip"]?.suggested == false)
        check("projeto parado há 90 dias: sugerido", byID["artifact:\(h("projetos/antigo/node_modules"))"]?.suggested == true)
        check("projeto mexido há 2 dias: não sugerido", byID["artifact:\(h("projetos/atual/node_modules"))"]?.suggested == false)
        check("ordenado do maior para o menor", withNpm.map(\.bytes) == withNpm.map(\.bytes).sorted(by: >))

        // Barreira antes do Lixo.
        let allowed = CleanupPlanner.allowedPaths(for: withNpm)
        try? fm.createDirectory(atPath: h("Library/Developer/Xcode/DerivedData/Projeto-abc"), withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: h("projetos/antigo/node_modules"), withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: h("Documents"), withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: h("projetos/atual"), withIntermediateDirectories: true)
        try? fm.createSymbolicLink(atPath: h("projetos/atual/node_modules"), withDestinationPath: h("Documents"))

        func refusal(_ path: String, allowed: Set<String>) -> CleanupSafety.Refusal? {
            do { try CleanupSafety.validate(path, home: home, allowed: allowed); return nil }
            catch let r as CleanupSafety.Refusal { return r } catch { return nil }
        }
        check("DerivedData passa", refusal(h("Library/Developer/Xcode/DerivedData"), allowed: allowed) == nil)
        check("node_modules parado passa", refusal(h("projetos/antigo/node_modules"), allowed: allowed) == nil)
        check("caminho fora da lista é recusado", refusal(h("Documents"), allowed: allowed) == .notAllowed(h("Documents")))
        check("pasta protegida é recusada mesmo se permitida",
              refusal(h("Documents"), allowed: allowed.union([h("Documents")])) == .protected(h("Documents")))
        check("pasta pessoal é recusada", refusal(home, allowed: [home]) != nil)
        check("fora da pasta pessoal é recusado", refusal("/Applications/Safari.app", allowed: ["/Applications/Safari.app"]) == .outsideHome("/Applications/Safari.app"))
        check("link simbólico é recusado", refusal(h("projetos/atual/node_modules"), allowed: allowed) == .symbolicLink(h("projetos/atual/node_modules")))
        check("caminho inexistente é recusado (npm ausente: ~/.npm iria para o Lixo)",
              refusal(h(".npm"), allowed: CleanupPlanner.allowedPaths(for: withoutNpm)) == .missing(h(".npm")))
        check("com o comando do npm, ~/.npm não vai para o Lixo", refusal(h(".npm"), allowed: allowed) == .notAllowed(h(".npm")))
        check("\"..\" não escapa da lista", refusal(h("projetos/antigo/node_modules/../../../Documents"), allowed: allowed) != nil)

        print(failures == 0 ? "\nTodos os casos passaram." : "\n\(failures) caso(s) falharam.")
        return failures == 0
    }
}
