# Checklist · Segurança e validação pela Apple

Roteiro da **inspeção de segurança** (Fase 5 do [ROADMAP](../ROADMAP.md)) e dos **requisitos
para a Apple validar o app** (assinatura Developer ID e notarização), antes da primeira versão
distribuída.

- ✅ já atende · ⚠️ precisa de correção · 🔍 verificar na inspeção · ⬜ ainda não feito
- Levantamento inicial: 23 nov 2026, no código do commit `2574a1f`.

---

## Parte 1 · Inspeção de segurança

O DiskNotch tem **Acesso Total ao Disco**, roda comandos do sistema e move arquivos para o Lixo.
Por isso, ele vale como alvo: quem conseguir controlar o app herda essas permissões. A inspeção
procura falhas de código, brechas que exponham o Mac e riscos de apagar o que não deve.

### 1.1 Apagar arquivos indevidos

| # | Item | Situação |
|---|---|---|
| 1 | O app nunca apaga de vez: só move para o Lixo (`FileManager.trashItem`) ou roda o comando oficial da ferramenta. Não há `removeItem` em caminhos do usuário. | ✅ |
| 2 | Lista permitida: só vão para o Lixo caminhos do catálogo e pastas de projeto detectadas (`CleanupSafety.validate`). | ✅ (21 testes) |
| 3 | Pastas protegidas são recusadas mesmo se entrarem na lista: pasta pessoal, Biblioteca, Documentos, Mesa, Downloads, Fotos, Filmes, Música, Aplicativos, Lixo, `.ssh`, `.config`, `.cache`, `.local`. | ✅ |
| 4 | Link simbólico no último trecho do caminho é recusado. | ✅ |
| 5 | **Link simbólico num trecho intermediário** (ex.: `~/projetos` apontando para outro disco): o caminho passa na comparação de texto, mas aponta para fora da pasta pessoal. Comparar também o caminho real (`realpath`). | ⚠️ |
| 6 | **Corrida entre validar e mover** (TOCTOU): outro processo troca a pasta por um link entre a validação e o `trashItem`. Validar de novo imediatamente antes de mover, ou abrir com `O_NOFOLLOW`. | 🔍 |
| 7 | A análise que alimenta as sugestões pode estar velha: confirmar que o caminho ainda é uma pasta de projeto (ex.: `package.json` ao lado de `node_modules`) no momento de mover. | ⚠️ |
| 8 | Nenhuma ação de limpeza pode ser disparada por link (`disknotch://`), notificação, widget ou mensagem entre processos; só por clique, com confirmação. | ✅ (manter) |
| 9 | Testes com caminhos hostis (Unicode, `..`, `~`, espaços, nomes que imitam pastas protegidas, `/private/var` e `/var`). | 🔍 |

### 1.2 Execução de comandos

| # | Item | Situação |
|---|---|---|
| 10 | Os comandos de limpeza são fixos no código (`CleanupPlanner.commands`); nada vindo de arquivos, da rede ou do usuário entra no comando. | ✅ |
| 11 | **Shell de login** (`zsh -lc`): carrega `.zprofile` e `.zshrc` do usuário, que podem alterar o PATH ou trocar `npm` e `brew` por outro programa. Avaliar rodar o executável pelo caminho absoluto resolvido, sem shell, e com ambiente mínimo. | ⚠️ |
| 12 | Tempo-limite para comandos (hoje só há o botão "Interromper"). | ⚠️ |
| 13 | `stdin` fechado (`/dev/null`) para nenhum comando ficar esperando resposta. | ✅ |

### 1.3 Brechas que exponham o Mac

| # | Item | Situação |
|---|---|---|
| 14 | **Runtime endurecido** desligado (`flags=0x0`): outro programa do mesmo usuário pode injetar código no app (`DYLD_INSERT_LIBRARIES`) e herdar o Acesso Total ao Disco. Ligar `--options runtime` em todos os executáveis. | ⚠️ |
| 15 | Validação de bibliotecas (vem com o runtime endurecido): o app só carrega bibliotecas assinadas pela Apple ou pelo mesmo time. | ⚠️ |
| 16 | Esquema `disknotch://`: qualquer site ou app pode abrir. Hoje só abre janelas (`painel`, `historico`, `ajustes`); hosts desconhecidos devem ser ignorados, sem efeito colateral. | ✅ / 🔍 |
| 17 | Notificação distribuída `id.nexum.disknotch.open-url`: qualquer processo local pode enviar. Aceitar só o esquema `disknotch` e hosts conhecidos. | 🔍 |
| 18 | Encerrar "cópia antiga": o app encerra processos com o mesmo identificador de bundle. Confirmar que não dá para induzi-lo a encerrar outro app. | 🔍 |
| 19 | Agente `id.nexum.disknotch.rebuild`: no login, compila e roda o código da pasta do projeto. Quem conseguir escrever nessa pasta executa código como você. **Fica só no desenvolvimento**; a versão distribuída não o instala. | ⚠️ |
| 20 | Certificado local de assinatura: chave privada no chaveiro de login, liberada só para o `codesign`; arquivos temporários (`.p12`, `.pem`) apagados. | ✅ |
| 21 | Nenhuma dependência externa hoje (SQLite é do sistema). Na Fase 5, o Sparkle entra com versão fixa e verificação de integridade. | ✅ / ⬜ |

### 1.4 Dados e privacidade

| # | Item | Situação |
|---|---|---|
| 22 | Nada sai do Mac: o app não faz conexões de rede. A verificação de atualização (Sparkle) será a única, por HTTPS. | ✅ |
| 23 | **`analysis.json` com permissão 0644**: ele lista caminhos dos seus arquivos, e a pasta pessoal (`drwxr-x---`) deixa outros usuários do Mac entrarem. Gravar com 0600 (também `history.sqlite`, `cleanup-log.json`). | ⚠️ |
| 24 | O app lê só tamanhos e datas; nunca abre o conteúdo dos arquivos do usuário. | ✅ |
| 25 | Logs (`~/Library/Logs/DiskNotch-start.log`) sem caminhos completos de arquivos do usuário. | 🔍 |
| 26 | Notificações mostram só o nome do volume e tamanhos. | ✅ |

### 1.5 Código

| # | Item | Situação |
|---|---|---|
| 27 | SQL: valores do usuário vão por parâmetros (`sqlite3_bind_*`); a única interpolação são constantes numéricas da compactação. | ✅ |
| 28 | Varredura: não segue links, não entra em outros volumes nem em pastas de nuvem sem cópia local; pode ser cancelada. | ✅ |
| 29 | Revisão das partes com `@unchecked Sendable` e `nonisolated(unsafe)` (`HistoryStore`, `Collector`, `LevelAppearance`) quanto a acesso concorrente. | 🔍 |
| 30 | Revisão automatizada do código (`/code-review` e `/security-review`) e testes atualizados para os itens corrigidos. | ⬜ |

---

## Parte 2 · Requisitos para a Apple validar o app

A distribuição é **fora da App Store**: assinatura **Developer ID** + **notarização**. A Apple
verifica o app automaticamente; o Gatekeeper só o abre sem aviso se tudo abaixo estiver certo.

### 2.1 Conta e certificados

- [ ] Inscrição no **Apple Developer Program** (US$ 99/ano).
- [ ] Certificado **Developer ID Application** no chaveiro (`security find-identity -v -p codesigning`).
- [ ] Credencial do `notarytool`: chave de API do App Store Connect (recomendado) ou senha de app.
- [ ] Credenciais guardadas só no chaveiro ou nos segredos do CI, nunca no repositório.

### 2.2 Assinatura

- [ ] **Runtime endurecido** (`--options runtime`) no app, no widget e em cada parte do Sparkle.
- [ ] **Carimbo de tempo seguro** (`--timestamp`).
- [ ] Assinar **de dentro para fora** (Sparkle, widget, app), sem `--deep`.
- [ ] Mesmo time (Team ID) em todo o código do pacote.
- [ ] Nenhum entitlement de depuração (`com.apple.security.get-task-allow`).
- [ ] Entitlements mínimos e revisados (`codesign -d --entitlements -`).
- [ ] Widget com `com.apple.security.app-sandbox`, como exige o WidgetKit.
- [ ] Exceções temporárias de sandbox do widget: confirmar que a notarização aceita; senão, trocar por **App Group** (`TEAMID.id.nexum.disknotch`).
- [ ] `codesign --verify --deep --strict --verbose=2` sem erros.

### 2.3 Pacote

- [ ] `Info.plist` completo: `CFBundleIdentifier`, `CFBundleShortVersionString` e `CFBundleVersion` que sobem a cada versão, `LSMinimumSystemVersion`, `NSHumanReadableCopyright`, `CFBundleIconFile`.
- [ ] Compilado com o SDK atual do macOS.
- [ ] Arquiteturas decididas: só Apple Silicon (todos os Macs com notch) ou também Intel.
- [ ] Nada solto no pacote: sem `.DS_Store`, sem links para fora do bundle, sem executável sem assinatura.
- [ ] Sem APIs privadas.

### 2.4 Notarização

- [ ] Enviar: `xcrun notarytool submit DiskNotch.dmg --keychain-profile … --wait`.
- [ ] Resultado **Accepted**, e o relatório (`xcrun notarytool log …`) sem avisos.
- [ ] Grampear o certificado de notarização no app e no DMG (`xcrun stapler staple`) e validar (`xcrun stapler validate`).

### 2.5 Verificação do Gatekeeper

- [ ] `spctl -a -vvv -t exec DiskNotch.app` → `accepted`, `source=Notarized Developer ID`.
- [ ] `spctl -a -vvv -t open --context context:primary-signature DiskNotch.dmg` → `accepted`.
- [ ] Teste numa conta de usuário limpa, com o DMG baixado pelo navegador (atributo de quarentena): abre sem aviso, sem `xattr`.
- [ ] Depois da instalação limpa: widget na galeria, notificações e Acesso Total ao Disco funcionam.

### 2.6 Atualizações (Sparkle)

- [ ] Appcast servido por HTTPS.
- [ ] Cada versão assinada com a chave **EdDSA** do Sparkle; chave privada fora do repositório.
- [ ] Atualização com assinatura inválida ou arquivo alterado é **recusada** (teste).
- [ ] O app atualizado mantém ajustes, histórico, análise e Acesso Total ao Disco.

### 2.7 Se um dia for para a App Store (fora do escopo atual)

- Sandbox no app principal, que limita a varredura às pastas escolhidas pelo usuário.
- Manifesto de privacidade (`PrivacyInfo.xcprivacy`) declarando as APIs com motivo obrigatório: espaço em disco, datas de arquivos e `UserDefaults`.
- Sem rodar comandos externos (a limpeza por comando sairia).
