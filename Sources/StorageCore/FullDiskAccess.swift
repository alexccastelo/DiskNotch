import Foundation

/// Acesso Total ao Disco (Ajustes do Sistema › Privacidade e Segurança).
///
/// Sem ele, pastas como Mail, Mensagens, Safari, a Lixeira e os dados de outros apps
/// não podem ser lidas, e a análise fica parcial.
public enum FullDiskAccess {
    /// O banco de permissões do usuário só pode ser aberto com Acesso Total ao Disco.
    /// Sem a permissão, a abertura falha com EPERM; o arquivo sempre existe.
    public static var isGranted: Bool {
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        let path = home + "/Library/Application Support/com.apple.TCC/TCC.db"
        let fd = open(path, O_RDONLY)
        if fd >= 0 {
            close(fd)
            return true
        }
        return errno == ENOENT   // sem o arquivo, não há como saber; não bloqueia a análise
    }

    /// Abre o painel certo dos Ajustes do Sistema.
    public static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
}
