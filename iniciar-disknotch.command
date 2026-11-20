#!/bin/zsh
# Recompila o DiskNotch se o código mudou e (re)abre o app.
# Roda no login pelo agente id.nexum.disknotch.rebuild, ou com duplo clique no Finder.
# Usa poucos processos externos: logo após o boot, cada um pode levar dezenas de segundos.
set -uo pipefail
zmodload zsh/datetime

export PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:$PATH"

DIR="${0:A:h}"
APP="$DIR/build/DiskNotch.app"
BIN="$APP/Contents/MacOS/DiskNotch"
LOG="$HOME/Library/Logs/DiskNotch-start.log"
APP_AGENT="gui/$(id -u)/id.nexum.disknotch"

log() { print -r -- "$(strftime '%Y-%m-%d %H:%M:%S' $EPOCHSECONDS) $*" >> "$LOG"; }

# Agente do app carregado? Então quem abre e reinicia o app é o launchd.
agent_loaded() { launchctl print "$APP_AGENT" >/dev/null 2>&1; }

start_or_restart() {
    if agent_loaded; then
        launchctl kickstart -k "$APP_AGENT"
    else
        pkill -f "$BIN" 2>/dev/null && sleep 1
        open "$APP"
    fi
}

cd "$DIR" || { log "pasta não encontrada: $DIR"; exit 1; }

# Arquivos de código mais novos que o executável (glob do zsh, sem chamar `find`).
newer=( Package.swift(N.e:'[[ $REPLY -nt $BIN ]]':) Sources/**/*.swift(N.e:'[[ $REPLY -nt $BIN ]]':) Support/*(N.e:'[[ $REPLY -nt $BIN ]]':) )

if [[ ! -x "$BIN" || ${#newer} -gt 0 ]]; then
    log "código alterado (${#newer} arquivo(s)) — recompilando"
    if ./build-app.sh >> "$LOG" 2>&1; then
        start_or_restart
        log "DiskNotch recompilado e reiniciado"
    else
        log "falha na compilação; mantendo a versão anterior"
    fi
    exit 0
fi

log "sem alterações no código"
# Duplo clique sem o agente: só garante que o app está aberto.
if ! agent_loaded && ! pgrep -qf "$BIN"; then
    open "$APP"
    log "DiskNotch aberto"
fi
