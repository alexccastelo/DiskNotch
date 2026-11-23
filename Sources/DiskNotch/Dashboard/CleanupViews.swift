import AppKit
import DiskNotchUI
import StorageCore
import SwiftUI

// MARK: - Página "Limpeza"

struct CleanupPage: View {
    var model: StorageModel
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        let analysis = model.analysis
        let cleanup = model.cleanup
        PageScroll {
            VStack(alignment: .leading, spacing: 18) {
                AnalysisHeader(title: "Limpeza", analysis: analysis)
                if analysis.report == nil {
                    EmptyAnalysis(analysis: analysis).frame(height: 360)
                } else {
                    let suggestions = cleanup.suggestions
                    summary(suggestions)
                    trashReminder
                    if suggestions.isEmpty {
                        Label("Nenhuma sugestão agora. Caches pequenos e pastas de projeto usadas nos últimos 30 dias ficam de fora.",
                              systemImage: "checkmark.seal")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(suggestions) { option in row(option, cleanup: cleanup) }
                        }
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                    }
                    if !cleanup.ignored.isEmpty, !isSnapshot {
                        Button("Voltar a sugerir \(cleanup.ignored.count) item(ns) ignorado(s)") { cleanup.restoreIgnored() }
                            .buttonStyle(.link)
                    }
                    Text("Outros itens, inclusive os que pedem revisão antes de apagar, estão na seção Desenvolvimento.")
                        .font(.caption).foregroundStyle(.secondary)
                    if !cleanup.records.isEmpty { history(cleanup.records) }
                }
            }
            .padding(22)
        }
    }

    private func summary(_ suggestions: [CleanupOption]) -> some View {
        let total = suggestions.reduce(0) { $0 + $1.bytes }
        return HStack(spacing: 14) {
            Image(systemName: "sparkles").font(.title).foregroundStyle(CategoryPalette.color(for: "development"))
            VStack(alignment: .leading, spacing: 3) {
                Text("Dá para liberar até \(ByteFormat.string(total)) com segurança").font(.title3.weight(.semibold))
                Text("\(suggestions.count) sugestão(ões): caches que as ferramentas recriam sozinhas e pastas de projeto paradas há mais de 30 dias. Nada é apagado de vez: o que sai vai para o Lixo ou é removido pelo comando oficial da ferramenta.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    /// O espaço do que vai para o Lixo só volta quando o Lixo é esvaziado.
    @ViewBuilder
    private var trashReminder: some View {
        let trash = model.analysis.report?.measured[(model.analysis.home as NSString).appendingPathComponent(".Trash")] ?? 0
        HStack(spacing: 12) {
            Image(systemName: "trash").font(.title2).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(trash > 0 ? "O Lixo ocupa \(ByteFormat.string(trash))" : "O Lixo")
                    .font(.headline)
                Text("O espaço dos itens movidos para o Lixo só volta quando você o esvaziar no Finder. Até lá, dá para devolver qualquer item com \"Colocar de Volta\".")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if !isSnapshot {
                Button("Abrir o Lixo") {
                    NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"))
                }
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private func row(_ option: CleanupOption, cleanup: CleanupModel) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: option.method == .trash ? "trash" : "terminal")
                .foregroundStyle(.secondary).frame(width: 20).padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(option.title).font(.body.weight(.medium))
                Text(subtitle(option)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 12)
            Text(ByteFormat.string(option.bytes)).font(.body.weight(.semibold)).monospacedDigit()
            if !isSnapshot {
                Button("Liberar…") { cleanup.ask(option) }
                Button { cleanup.ignore(option) } label: { Image(systemName: "eye.slash") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Não sugerir mais")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .overlay(alignment: .bottom) { Divider().opacity(0.5) }
    }

    private func subtitle(_ option: CleanupOption) -> String {
        switch option.method {
        case .command(let command, _): return "Comando oficial: \(command)"
        case .trash:
            if let modified = option.modified {
                return "Parada desde \(modified.formatted(date: .abbreviated, time: .omitted)) · \(option.detail)"
            }
            return "Vai para o Lixo · \(option.detail)"
        }
    }

    private func history(_ records: [CleanupRecord]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Já liberado: \(ByteFormat.string(records.reduce(0) { $0 + $1.freedBytes }))").font(.headline).padding(.top, 6)
            VStack(spacing: 0) {
                ForEach(records.prefix(8)) { record in
                    HStack {
                        Text(record.title)
                        Text(record.method == "Lixo" ? "para o Lixo" : record.method)
                            .font(record.method == "Lixo" ? .caption : .caption.monospaced())
                            .foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Text(record.date.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(.tertiary)
                        Text(ByteFormat.string(record.freedBytes)).monospacedDigit().frame(width: 80, alignment: .trailing)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .overlay(alignment: .bottom) { Divider().opacity(0.5) }
                }
            }
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

// MARK: - Confirmação

struct CleanupSheet: View {
    var cleanup: CleanupModel
    var option: CleanupOption

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(option.title).font(.title3.weight(.semibold))
                Spacer()
                Text(ByteFormat.string(option.bytes)).font(.title3.weight(.semibold)).monospacedDigit()
            }
            Text(option.detail).foregroundStyle(.secondary)

            switch option.method {
            case .trash: trashDetails
            case .command(let command, _): commandDetails(command)
            }

            if usesXcode, cleanup.xcodeIsRunning {
                Label("O Xcode está aberto. Feche-o antes, para ele não recriar os arquivos durante a limpeza.",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }

            if !cleanup.output.isEmpty {
                ScrollView {
                    Text(cleanup.output).font(.caption.monospaced()).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 140)
                .padding(8)
                .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
            }
            if let error = cleanup.errorMessage {
                Label(error, systemImage: "xmark.octagon").foregroundStyle(.red)
            }
            if let result = cleanup.result, cleanup.errorMessage == nil {
                Label(resultText(result), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            }

            HStack {
                Spacer()
                if cleanup.isRunning {
                    ProgressView().controlSize(.small)
                    if case .command = option.method { Button("Interromper") { cleanup.cancel() } }
                } else if cleanup.result != nil || cleanup.errorMessage != nil {
                    Button("Fechar") { cleanup.dismiss() }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancelar") { cleanup.dismiss() }.keyboardShortcut(.cancelAction)
                    Button(confirmTitle) { cleanup.confirm() }.keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(20)
        .frame(width: 520)
        .interactiveDismissDisabled(cleanup.isRunning)
    }

    private var usesXcode: Bool {
        if case .devItem(let id) = option.source { return id.hasPrefix("xcode") || id.hasPrefix("simulator") }
        return false
    }

    private var confirmTitle: String {
        if case .trash = option.method { return "Mover para o Lixo" }
        return "Rodar o comando"
    }

    private var trashDetails: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Vai para o Lixo:").font(.callout.weight(.medium))
            ForEach(option.paths, id: \.self) { path in
                Text(cleanup.analysis.display(path)).font(.callout.monospaced()).lineLimit(1).truncationMode(.middle)
            }
            Text("Dá para devolver pelo Finder (\"Colocar de Volta\"). O espaço volta quando você esvaziar o Lixo.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func commandDetails(_ command: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("O DiskNotch vai rodar o comando oficial da ferramenta, como se você digitasse no Terminal:")
                .font(.callout)
            Text(command).font(.callout.monospaced())
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            Text("Ele remove só o cache da ferramenta, que ela baixa de novo quando precisar.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func resultText(_ record: CleanupRecord) -> String {
        if record.freedBytes == 0 { return "Pronto. O tamanho não mudou." }
        if record.method == "Lixo" { return "\(ByteFormat.string(record.freedBytes)) foram para o Lixo." }
        return "Liberado: \(ByteFormat.string(record.freedBytes))."
    }
}
