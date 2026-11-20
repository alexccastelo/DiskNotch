# DiskNotch

Monitor de armazenamento para o MacBook que mora no **notch**. Mostra quanto espaço livre o Mac tem, o que pode ser liberado e quando o disco está ficando cheio, sem abrir nenhuma janela.

> **Status:** em desenvolvimento, fase 1 de 5. Veja o [ROADMAP.md](ROADMAP.md).

## O que ele faz hoje

- **Painel no notch.** Recolhido, mostra um anel de ocupação e os GB livres ao lado do notch. Ao passar o mouse, abre com:
  - espaço livre, purgável, usado e total do disco de inicialização;
  - barra de uso e nível de alerta (verde, âmbar abaixo de 20% livre, vermelho abaixo de 10%);
  - discos externos e de rede, com botão de ejetar;
  - atalhos para atualizar, abrir no Finder e abrir os Ajustes de Armazenamento.
- **Não cobre os ícones da barra de menus.** A informação recolhida fica de um lado só do notch, e o lado pode ser escolhido.
- **Ícone na barra de menus**, com os GB livres, a lista de volumes e as opções do painel. Ele também serve de alternativa em telas sem notch.
- **Alertas de espaço baixo.** Uma notificação do macOS avisa quando um disco local entra em "atenção" ou fica "crítico". Os limites são ajustáveis no menu da barra (padrão: 20% e 10% livres) e definem também as cores do painel.
  - Avisa só quando a situação piora; em nível crítico, lembra uma vez a cada 24 h.
  - Uma folga de 1 ponto percentual evita avisos repetidos quando o uso oscila perto do limite.
  - Clicar na notificação abre os Ajustes de Armazenamento.
- **Atualização automática** a cada 60 segundos, ao montar ou ejetar discos e quando o Mac acorda.
- **Abre sozinho no login** e reabre se travar.

### "Livre" e "purgável"

O DiskNotch mostra o espaço livre do mesmo jeito que o Finder: já conta o que o macOS consegue liberar sozinho (caches, arquivos do iCloud otimizados, snapshots locais). Essa parte aparece separada como **purgável**. Por isso o número pode ser maior que o "Avail" do `df`.

## Requisitos

- Mac com Apple Silicon e macOS 15 ou mais novo (desenvolvido e testado no macOS 27 "Golden Gate")
- Command Line Tools da Apple, com Swift 6 (`xcode-select --install`)
- **O Xcode não é necessário.** O projeto compila só com o Swift Package Manager.

## Como compilar e abrir

Compila em modo release e gera `build/DiskNotch.app` com assinatura local (ad hoc):

```bash
./build-app.sh
```

```bash
open build/DiskNotch.app
```

Ou, com duplo clique no Finder, `iniciar-disknotch.command`: ele recompila só se o código mudou e abre o app.

Para conferir a leitura dos discos pelo terminal, sem interface:

```bash
swift run disknotch-probe
```

Para testar a regra de quando notificar (11 casos, incluindo a folga e o lembrete de 24 h):

```bash
swift run disknotch-probe --testar-alertas
```

## Abrir no login

```bash
./inicio-automatico.sh
```

O script instala dois LaunchAgents em `~/Library/LaunchAgents`:

| Agente | O que faz |
|---|---|
| `id.nexum.disknotch` | Abre o app direto no login, sem passar pelo shell, e o reabre se ele travar. Sair pelo menu não reabre. |
| `id.nexum.disknotch.rebuild` | Em baixa prioridade, recompila se algum arquivo do código mudou e reinicia o app. |

O registro fica em `~/Library/Logs/DiskNotch-start.log`. Para desligar:

```bash
./inicio-automatico.sh --remover
```

## Estrutura

```
DiskNotch/
├── Package.swift                 pacote Swift (3 alvos)
├── Sources/
│   ├── StorageCore/              leitura dos volumes, sem interface
│   │   ├── VolumeInfo.swift      modelo, níveis de alerta e formatação de bytes
│   │   ├── VolumeService.swift   capacidade e metadados de cada volume
│   │   └── AlertPolicy.swift     regra de quando notificar
│   ├── DiskNotch/                o app
│   │   ├── DiskNotchApp.swift    ponto de entrada, menu da barra e ajustes
│   │   ├── StorageModel.swift    estado observável e atualização periódica
│   │   ├── AlertCenter.swift     notificações e ajustes de limites
│   │   ├── NotchPanelController.swift  janela do notch, posição e cliques
│   │   ├── NotchView.swift       estados recolhido e expandido
│   │   └── Components.swift      anel, barra de uso e formato do notch
│   └── disknotch-probe/          ferramenta de linha de comando para testes
├── Support/Info.plist            Info.plist do .app (sem ícone no Dock)
├── build-app.sh                  compila e empacota o .app
├── iniciar-disknotch.command     recompila se preciso e abre
├── inicio-automatico.sh          liga e desliga a abertura no login
└── ROADMAP.md                    fases, entregas e decisões
```

## Como funciona

- **Leitura do disco:** `URL.resourceValues` com as chaves de capacidade do volume. O espaço "livre para uso importante" (`volumeAvailableCapacityForImportantUsage`) inclui o purgável; a diferença para o livre estrito vira o número "purgável".
- **Painel no notch:** um `NSPanel` sem borda e que não rouba o foco, acima da barra de menus e presente em todos os espaços, inclusive em tela cheia. A posição vem de `NSScreen.auxiliaryTopLeftArea` e `auxiliaryTopRightArea`.
- **Cliques:** a janela do painel é maior que a forma desenhada. Monitores de mouse ligam `ignoresMouseEvents` sempre que o cursor está fora da forma, para não bloquear as janelas de baixo.

## Limitações conhecidas

- **Sem macros do SwiftUI.** As Command Line Tools não trazem o plugin de macros do SwiftUI, então `@State`, `@Entry` e `#Preview` não compilam. O estado das views fica em classes `@Observable`, que funcionam.
- **Widgets dependem do Xcode.** WidgetKit e Login Item nativo exigem Xcode e ficaram para quando ele estiver instalado.
- **O notch não tem API oficial.** O posicionamento é manual e pode mudar entre versões do macOS.
- **Ícones da barra de menus não são detectáveis no macOS 27.** Por isso a informação recolhida fica de um lado só, em vez de se ajustar ao espaço livre.

## Próximos passos

Histórico com previsão de quando o disco enche e a categoria **Desenvolvimento** (caches do Xcode, `node_modules`, npm, pip, Homebrew, Docker e modelos de IA locais). Detalhes no [ROADMAP.md](ROADMAP.md).
