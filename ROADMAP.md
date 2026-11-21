---
projeto: DiskNotch
slug: disknotch
descricao: Monitor de armazenamento do Mac no notch, na barra de menus e em widgets, com histórico, análise e limpeza assistida.
atualizado: 2026-11-21 09:27
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
_21 nov 2026_ — Acompanhar a ocupação ao longo do tempo e ver o disco sem abrir nada. Os widgets aguardam o Xcode.

- [entregue] **Histórico de ocupação** · Histórico · sugestão
  Gráficos de 24 horas, 7 dias, 30 dias e 1 ano, com amostras a cada 5 minutos.
  - Gravado em SQLite e compactado em médias por hora e por dia
  - Mini gráfico das últimas 24 h no notch; janela própria com os gráficos completos
  > local: 2026-11-21 · github: 204ddb6
- [entregue] **Previsão de quando o disco enche** · Histórico · sugestão
  Estima, pelo ritmo das últimas semanas, em quantos dias o disco fica cheio.
  - Usa as últimas 2 semanas e precisa de pelo menos 6 h de dados
  > local: 2026-11-21 · github: 204ddb6
- [planejado] **Widgets para a mesa e a Central de Notificações** · Widgets · pedido
  Tamanhos pequeno, médio e grande, com botão para atualizar.
  - Depende do Xcode instalado

## Fase 3 · Análise do disco
_a definir_ — Descobrir o que ocupa o disco e onde está o crescimento.

- [planejado] **Categoria Desenvolvimento** · Análise · sugestão
  Mede caches de programação: Xcode, node_modules, npm, pnpm, pip, uv, Homebrew, Docker e modelos de IA locais.
- [planejado] **Categorias e maiores pastas** · Análise · sugestão
  Apps, Documentos, Downloads, Mídia, Sistema e snapshots, com as maiores pastas e arquivos.
- [planejado] **Permissão de Acesso Total ao Disco** · Permissões · sugestão
  Explica por que a permissão é necessária e leva direto ao lugar certo nos Ajustes do Sistema.
- [planejado] **Janela de painel completo** · Produto · sugestão
  Visão geral, categorias, histórico, volumes e ajustes numa janela própria, com mapa visual do disco.

## Fase 4 · Limpeza assistida
_a definir_ — Liberar espaço com segurança.

- [planejado] **Sugestões de limpeza** · Limpeza · sugestão
  Mostra quanto cada item libera e só move para o Lixo depois de confirmar.
  - Comandos de limpeza de ferramentas de dev exibidos antes de rodar

## Fase 5 · Acabamento e distribuição
_a definir_ — Deixar o app pronto para outras pessoas usarem.

- [planejado] **Acessibilidade e idiomas** · Produto · sugestão
  Suporte ao VoiceOver e textos em português e inglês.
- [planejado] **Instalação assinada com atualizações automáticas** · Distribuição · sugestão
  App assinado e notarizado pela Apple, que se atualiza sozinho.

## Ideias
_sem data_ — Possibilidades levantadas no caminho.

- [ideia] **Aviso de picos de ocupação** · Alertas · sugestão
  Avisar quando o disco cresce muito em pouco tempo e apontar a pasta responsável.
- [ideia] **Versão para a App Store** · Distribuição · sugestão
  Versão limitada às pastas escolhidas pelo usuário, por causa das regras da loja.

## Decisões

- **App nativo em Swift e SwiftUI** — Leve, sem dependências e com acesso direto às informações de disco do macOS.
- **Compilação sem Xcode** — Por enquanto o app é compilado só com o Swift Package Manager, sem os recursos que exigem Xcode.
- **Início pelo launchd** — Dois LaunchAgents substituem o Login Item do plano, que exigiria Xcode, e abrem o app na hora mesmo com o Mac carregado após o boot.
- **Informação recolhida de um lado só** — No macOS 27 não dá para saber onde ficam os ícones da barra de menus, então o painel não passa da borda do notch do lado dos ícones.
- **Histórico em SQLite** — O SwiftData depende de macros que não existem sem o Xcode; o SQLite já vem no macOS e não precisa de dependências.

## Pontos de atenção

- **Widgets dependem do Xcode** — Sem o Xcode instalado, a Fase 2 avança só no histórico e na previsão.
- **Notch sem API oficial** — O posicionamento é manual e pode mudar entre versões do macOS; o ícone na barra de menus fica sempre como alternativa.
- **Testes só da lógica** — Alertas, histórico e previsão têm testes automáticos no `disknotch-probe`; a interface ainda é verificada à mão.
- **Histórico começa na instalação** — O macOS não guarda histórico de espaço livre, então os gráficos se preenchem com o tempo e ficam com lacunas quando o Mac está desligado.
