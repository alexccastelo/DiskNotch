---
projeto: DiskNotch
slug: disknotch
descricao: Monitor de armazenamento do Mac no notch, na barra de menus e em widgets, com histórico, análise e limpeza assistida.
atualizado: 2026-11-23 09:56
---

# Roadmap · DiskNotch

## Fase 0 · Validação técnica
_20 nov 2026_ — Provar que o painel no notch e a leitura do disco funcionam no macOS 27.

- [entregue] **Painel no notch do MacBook** · Notch · pedido
  Um painel preto que se funde ao notch e aparece em todos os espaços de trabalho, inclusive em tela cheia.
  - Posição calculada a partir da área do notch informada pelo sistema
  - Em telas sem notch, vira uma pílula no topo
  > local: 2026-11-20 · github: 17ebb1d
- [entregue] **Leitura de espaço livre, usado e purgável** · Armazenamento · pedido
  Mostra o espaço livre como o Finder mostra e separa a parte que o macOS consegue liberar sozinho.
  - Números conferidos com o `df`
  > local: 2026-11-20 · github: 17ebb1d

## Fase 1 · Primeira versão
_20 nov 2026_ — Ver o espaço do disco a qualquer momento, sem abrir nenhuma janela.

- [entregue] **Painel recolhido e expandido** · Notch · pedido
  Recolhido, mostra um anel de ocupação e os GB livres. Ao passar o mouse, abre com detalhes, barra de uso e atalhos.
  - Cores por nível: verde, âmbar (menos de 20% livre) e vermelho (menos de 10%)
  - Fora da forma desenhada, os cliques passam para as janelas de baixo
  > local: 2026-11-20 · github: 17ebb1d
- [entregue] **Painel que não cobre os ícones da barra de menus** · Notch · pedido
  A informação recolhida fica só de um lado do notch, e o lado pode ser escolhido no menu.
  > local: 2026-11-20 · github: 17ebb1d
- [entregue] **Ícone na barra de menus** · Barra de menus · sugestão
  Mostra os GB livres e abre a lista de volumes com uso, espaço purgável e opções do painel.
  > local: 2026-11-20 · github: 17ebb1d
- [entregue] **Abre sozinho no login** · Infra · pedido
  O app abre logo após o login, volta sozinho se travar e é recompilado automaticamente quando o código muda.
  - Dois LaunchAgents: um abre o app direto, outro recompila em baixa prioridade
  - Validado com reinício real do Mac
  > local: 2026-11-20 · github: 17ebb1d
- [entregue] **Alertas de espaço baixo** · Alertas · pedido
  Notificação do macOS quando o espaço livre cai abaixo de um limite, com limites ajustáveis no menu.
  - Avisa só quando piora; em nível crítico, lembra a cada 24 h
  - Os limites também definem as cores do painel
  > local: 2026-11-20 · github: f4a23c1
- [planejado] **Discos externos com botão de ejetar** · Armazenamento · sugestão
  Discos externos e de rede aparecem no painel com uso e botão de ejetar.
  - Já implementado; em espera até haver um disco externo para testar

## Fase 2 · Histórico e widgets
_21 nov 2026_ — Acompanhar a ocupação ao longo do tempo e ver o disco sem abrir nada.

- [entregue] **Histórico de ocupação** · Histórico · sugestão
  Gráficos de 24 horas, 7 dias, 30 dias e 1 ano, com amostras a cada 5 minutos.
  - Gravado em SQLite e compactado em médias por hora e por dia
  - Mini gráfico das últimas 24 h no notch; janela própria com os gráficos completos
  > local: 2026-11-21 · github: 204ddb6
- [entregue] **Previsão de quando o disco enche** · Histórico · sugestão
  Estima, pelo ritmo das últimas semanas, em quantos dias o disco fica cheio.
  - Usa as últimas 2 semanas e precisa de pelo menos 6 h de dados
  > local: 2026-11-21 · github: 204ddb6
- [entregue] **Widgets para a mesa e a Central de Notificações** · Widgets · pedido
  Tamanhos pequeno, médio e grande, com espaço livre, gráfico das últimas 24 h e previsão. Clicar abre o histórico.
  - Montados sem Xcode; o app os atualiza a cada 15 min ou quando o nível muda
  > local: 2026-11-21 · github: e4c4d77

## Fase 3 · Análise do disco
_23 nov 2026_ — Descobrir o que ocupa o disco e onde está o crescimento.

- [entregue] **Categoria Desenvolvimento** · Análise · sugestão
  Mede caches de programação: Xcode, node_modules, npm, pnpm, pip, uv, Homebrew, Docker e modelos de IA locais.
  - Comando oficial de limpeza de cada ferramenta, com botão para copiar; o painel não apaga nada
  - Pastas de projeto (node_modules, .venv, .build, target) só na pasta pessoal
  > local: 2026-11-23 · github: 6f921b8
- [entregue] **Categorias e maiores pastas** · Análise · sugestão
  Apps, Documentos, Downloads, Mídia, Caches, Sistema e outras, com as maiores pastas e arquivos.
  - Cada byte numa categoria só; o que sobra do espaço usado vira "Sistema e outros"
  - Mapa navegável das pastas grandes
  > local: 2026-11-23 · github: 6f921b8
- [entregue] **Permissão de Acesso Total ao Disco** · Permissões · sugestão
  Explica por que a permissão é necessária e leva direto ao lugar certo nos Ajustes do Sistema.
  - Certificado local para a permissão sobreviver aos builds
  > local: 2026-11-23 · github: 6f921b8
- [entregue] **Janela de painel completo** · Produto · sugestão
  Visão geral, desenvolvimento, categorias, pastas, histórico e volumes numa janela própria, com mapa visual do disco.
  > local: 2026-11-23 · github: 6f921b8

## Fase 4 · Limpeza assistida
_23 nov 2026_ — Liberar espaço com segurança.

- [entregue] **Sugestões de limpeza** · Limpeza · sugestão
  Mostra quanto cada item libera e só move para o Lixo depois de confirmar.
  - Comando oficial da ferramenta, quando ela está instalada, com a saída na hora
  - Lixo para caches sem comando e para pastas de projeto paradas há mais de 30 dias
  - Barreira que recusa pastas protegidas, links simbólicos e caminhos fora da pasta pessoal
  - Registro do quanto foi liberado
  > local: 2026-11-23 · github: 8406a5a

## Fase 5 · Acabamento e distribuição
_a definir_ — Deixar o app pronto para outras pessoas usarem.

- [planejado] **Acessibilidade e idiomas** · Produto · sugestão
  Suporte ao VoiceOver e textos em português e inglês.
- [entregue] **Faixas e cores configuráveis** · Ajustes · pedido
  Escolher quando o disco passa a "espaço baixo" e "espaço crítico", e as cores de cada nível.
  - Por porcentagem livre, por GB livres ou pelos dois (vale o que disparar primeiro), com prévia nos seus discos
  - Cores aplicadas no notch, no menu, no painel e nos widgets
  - Seção Ajustes no painel; o teste de notificação explica quando um Foco segura o aviso
  > local: 2026-11-23
- [entregue] **Ícone do app** · Produto · pedido
  O mesmo anel do banner, no formato que o macOS 26+ exige.
  > local: 2026-11-23
- [proximo] **Instalação assinada com atualizações automáticas** · Distribuição · sugestão
  App assinado e notarizado pela Apple, que se atualiza sozinho.
  - Developer ID, runtime endurecido e notarização
  - DMG com nome fixo no GitHub Releases
  - Atualização automática pelo Sparkle
  - Abertura no login pelo SMAppService
- [proximo] **Aviso de picos de ocupação** · Alertas · sugestão
  Avisar quando o disco cresce muito em pouco tempo e apontar a pasta responsável.

## Ideias
_sem data_ — Possibilidades levantadas no caminho.

- [ideia] **Versão para a App Store** · Distribuição · sugestão
  Versão limitada às pastas escolhidas pelo usuário, por causa das regras da loja.
- [ideia] **Snapshots locais do Time Machine** · Análise · sugestão
  Mostrar quantos snapshots locais existem e quanto espaço ocupam.

## Decisões

- **App nativo em Swift e SwiftUI** — Leve, sem dependências e com acesso direto às informações de disco do macOS.
- **Compilação sem Xcode** — Por enquanto o app é compilado só com o Swift Package Manager, sem os recursos que exigem Xcode.
- **Início pelo launchd** — Dois LaunchAgents substituem o Login Item do plano, que exigiria Xcode, e abrem o app na hora mesmo com o Mac carregado após o boot.
- **Informação recolhida de um lado só** — No macOS 27 não dá para saber onde ficam os ícones da barra de menus, então o painel não passa da borda do notch do lado dos ícones.
- **Histórico em SQLite** — O SwiftData depende de macros que não existem sem o Xcode; o SQLite já vem no macOS e não precisa de dependências.
- **Widgets sem Xcode** — A extensão é compilada pelo Swift Package Manager e ligada com a entrada `_NSExtensionMain`, como o Xcode faz; o `build-app.sh` grava as chaves de plataforma e SDK no `Info.plist`.
- **Análise sob demanda numa passada só** — A pasta pessoal, os Aplicativos e o Homebrew são percorridos juntos, em cerca de 20 s para 1 milhão de arquivos; o resultado fica salvo.
- **Pastas de nuvem fora da análise** — Abrir ~/Library/CloudStorage e pastas sem cópia local força o serviço a baixar listagens e trava a varredura.
- **Certificado local de assinatura** — O Acesso Total ao Disco fica preso à assinatura; a assinatura ad hoc muda a cada build e a permissão se perderia.
- **Nada é apagado de vez** — Só o Lixo ou o comando oficial da ferramenta; o DiskNotch nunca esvazia o Lixo.
- **Uma cópia do app por vez** — Se a cópia aberta é de uma versão anterior, a nova a encerra e assume; se é da mesma versão, a nova repassa o link e fecha.
- **Ícone de ponta a ponta** — Quadrado opaco, em 8 bits por canal e sem cantos arredondados: é assim que o macOS 26+ aplica o recorte e o vidro sem moldura cinza.

## Pontos de atenção

- **Sem botão interativo no widget** — Botões em widgets dependem de App Intents, cujos metadados só o Xcode gera; o app atualiza os widgets por conta própria.
- **Notch sem API oficial** — O posicionamento é manual e pode mudar entre versões do macOS; o ícone na barra de menus fica sempre como alternativa.
- **Testes só da lógica** — Alertas, histórico, previsão, análise e limpeza têm testes automáticos no `disknotch-probe` (63 casos, rodados pelo CI); a interface ainda é verificada à mão.
- **Histórico começa na instalação** — O macOS não guarda histórico de espaço livre, então os gráficos se preenchem com o tempo e ficam com lacunas quando o Mac está desligado.
- **"Sistema e outros" é estimado** — É o espaço usado menos tudo o que foi medido; não há como medir o próprio macOS sem permissões de administrador.
- **Pastas de nuvem não são medidas** — O espaço local usado pelo Google Drive, Dropbox e afins fica de fora da análise.
- **O espaço do Lixo só volta ao esvaziar** — O que vai para o Lixo continua ocupando o disco até ele ser esvaziado no Finder.
- **Foco segura os alertas** — Com um Foco ativo, as notificações vão direto para a Central de Notificações, a não ser que o DiskNotch esteja entre os apps permitidos.
- **Distribuição depende de conta paga** — A Fase 5 exige o Apple Developer Program (certificado Developer ID e notarização).
