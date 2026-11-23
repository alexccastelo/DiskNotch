import AppKit
import Observation
import StorageCore

/// Limpeza assistida: sugestões, confirmação, execução e registro do que foi liberado.
@MainActor
@Observable
final class CleanupModel {
    /// Ação esperando confirmação (abre a folha de confirmação).
    var pending: CleanupOption?
    private(set) var isRunning = false
    private(set) var output = ""
    private(set) var result: CleanupRecord?
    private(set) var errorMessage: String?
    private(set) var availableTools: Set<String> = []
    private(set) var records: [CleanupRecord] = []
    private(set) var ignored: Set<String>

    @ObservationIgnored let analysis: AnalysisModel
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private let isDemo: Bool

    private static let ignoredKey = "cleanupIgnored"
    static var recordsURL: URL {
        HistoryStore.defaultURL.deletingLastPathComponent().appendingPathComponent("cleanup-log.json")
    }

    init(analysis: AnalysisModel, demo: Bool = false) {
        self.analysis = analysis
        isDemo = demo
        ignored = Set(UserDefaults.standard.stringArray(forKey: Self.ignoredKey) ?? [])
        if demo {
            availableTools = CleanupPlanner.tools
            records = [CleanupRecord(date: .now.addingTimeInterval(-3 * 86_400), title: "Xcode · DerivedData",
                                     method: "Lixo", freedBytes: 14_200_000_000)]
        } else {
            records = (try? JSONDecoder().decode([CleanupRecord].self, from: Data(contentsOf: Self.recordsURL))) ?? []
            Task { await detectTools() }
        }
    }

    // MARK: Sugestões

    var options: [CleanupOption] {
        analysis.dev.map { CleanupPlanner.options(for: $0, availableTools: availableTools) } ?? []
    }

    var suggestions: [CleanupOption] {
        options.filter { $0.suggested && !ignored.contains($0.id) }
    }

    func option(forDevItem id: String) -> CleanupOption? { options.first { $0.id == "dev:\(id)" } }
    func option(forArtifact path: String) -> CleanupOption? { options.first { $0.id == "artifact:\(path)" } }

    func ignore(_ option: CleanupOption) {
        ignored.insert(option.id)
        UserDefaults.standard.set(Array(ignored), forKey: Self.ignoredKey)
    }

    func restoreIgnored() {
        ignored.removeAll()
        UserDefaults.standard.removeObject(forKey: Self.ignoredKey)
    }

    var totalFreed: Int64 { records.reduce(0) { $0 + $1.freedBytes } }

    /// O Xcode aberto continua escrevendo em DerivedData e nos simuladores.
    var xcodeIsRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dt.Xcode").isEmpty
    }

    // MARK: Execução

    func ask(_ option: CleanupOption) {
        guard !isRunning else { return }
        output = ""
        result = nil
        errorMessage = nil
        pending = option
    }

    func dismiss() {
        guard !isRunning else { return }
        pending = nil
    }

    func confirm() {
        guard let option = pending, !isRunning, !isDemo else { return }
        isRunning = true
        Task {
            defer { isRunning = false }
            switch option.method {
            case .trash: await moveToTrash(option)
            case .command(let command, _): await runCommand(command, for: option)
            }
        }
    }

    func cancel() { process?.terminate() }

    private func moveToTrash(_ option: CleanupOption) async {
        let allowed = CleanupPlanner.allowedPaths(for: options)
        do {
            // Valida tudo antes de mover qualquer coisa.
            for path in option.paths { try CleanupSafety.validate(path, home: analysis.home, allowed: allowed) }
            for path in option.paths {
                var trashed: NSURL?
                try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: &trashed)
                output += "Movido para o Lixo: \(analysis.display(path))\n"
            }
        } catch let refusal as CleanupSafety.Refusal {
            errorMessage = "Nada foi movido: \(refusal)."
            return
        } catch {
            errorMessage = "Não deu para mover para o Lixo: \(error.localizedDescription)"
        }
        await finish(option, method: "Lixo")
    }

    private func runCommand(_ command: String, for option: CleanupOption) async {
        output = "$ \(command)\n"
        let status = await Shell.run(command, process: { self.process = $0 }) { [weak self] chunk in
            self?.output += chunk
        }
        process = nil
        if status != 0 {
            errorMessage = status == 15 ? "Comando interrompido." : "O comando terminou com erro (código \(status))."
        }
        await finish(option, method: command)
    }

    /// Mede de novo e registra quanto foi liberado.
    private func finish(_ option: CleanupOption, method: String) async {
        let after = await analysis.remeasure(option.paths)
        let freed = max(0, option.bytes - after)
        let record = CleanupRecord(title: option.title, method: method, freedBytes: freed)
        result = record
        if freed > 0 {
            records.insert(record, at: 0)
            save()
        }
        AlertCenter.log("limpeza: \(option.title) via \(method) — \(ByteFormat.string(freed))")
    }

    private func save() {
        try? JSONEncoder().encode(records).write(to: Self.recordsURL, options: .atomic)
    }

    // MARK: Ferramentas

    /// Procura as ferramentas no PATH do shell de login do usuário (Homebrew, nvm, pyenv…).
    func detectTools() async {
        let names = CleanupPlanner.tools.sorted().joined(separator: " ")
        var found = ""
        _ = await Shell.run("for t in \(names); do command -v $t >/dev/null 2>&1 && echo $t; done") { found += $0 }
        availableTools = Set(found.split(whereSeparator: \.isNewline).map(String.init))
    }
}

/// Roda um comando no zsh de login, como se fosse digitado no Terminal.
enum Shell {
    @MainActor
    static func run(_ command: String, process onStart: ((Process) -> Void)? = nil,
                    output: @escaping @MainActor (String) -> Void) async -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in output(text) }
        }
        return await withCheckedContinuation { continuation in
            process.terminationHandler = { finished in
                pipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: finished.terminationStatus)
            }
            do {
                try process.run()
                onStart?(process)
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: -1)
            }
        }
    }
}
