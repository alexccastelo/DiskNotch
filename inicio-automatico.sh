#!/bin/zsh
# Liga ou desliga o início automático do DiskNotch no login.
#   ./inicio-automatico.sh           liga
#   ./inicio-automatico.sh --remover desliga
#
# São dois LaunchAgents:
#   id.nexum.disknotch          abre o executável direto (sem shell), na hora do login,
#                               e reabre se o app travar (sair pelo menu não reabre)
#   id.nexum.disknotch.rebuild  em baixa prioridade: recompila se o código mudou e reinicia o app
set -euo pipefail

DIR="${0:A:h}"
BIN="$DIR/build/DiskNotch.app/Contents/MacOS/DiskNotch"
SCRIPT="$DIR/iniciar-disknotch.command"
LOGFILE="$HOME/Library/Logs/DiskNotch-start.log"
AGENTS="$HOME/Library/LaunchAgents"
DOMAIN="gui/$(id -u)"
APP_LABEL="id.nexum.disknotch"
REBUILD_LABEL="id.nexum.disknotch.rebuild"
OLD_LABEL="id.nexum.disknotch.start"   # versão anterior, que rodava tudo pelo shell

for label in $APP_LABEL $REBUILD_LABEL $OLD_LABEL; do
    launchctl bootout "$DOMAIN/$label" 2>/dev/null || true
done
rm -f "$AGENTS/$OLD_LABEL.plist"

if [[ "${1:-}" == "--remover" ]]; then
    rm -f "$AGENTS/$APP_LABEL.plist" "$AGENTS/$REBUILD_LABEL.plist"
    echo "Início automático desligado."
    exit 0
fi

[[ -x "$BIN" ]] || "$DIR/build-app.sh"
mkdir -p "$AGENTS"

cat > "$AGENTS/$APP_LABEL.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$APP_LABEL</string>
    <key>ProgramArguments</key><array><string>$BIN</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
    <key>LimitLoadToSessionType</key><string>Aqua</string>
    <key>ProcessType</key><string>Interactive</string>
    <key>StandardErrorPath</key><string>$LOGFILE</string>
</dict>
</plist>
EOF

cat > "$AGENTS/$REBUILD_LABEL.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>$REBUILD_LABEL</string>
    <key>ProgramArguments</key><array><string>/bin/zsh</string><string>$SCRIPT</string></array>
    <key>RunAtLoad</key><true/>
    <key>ProcessType</key><string>Background</string>
    <key>Nice</key><integer>10</integer>
    <key>LowPriorityIO</key><true/>
    <key>StandardOutPath</key><string>$LOGFILE</string>
    <key>StandardErrorPath</key><string>$LOGFILE</string>
</dict>
</plist>
EOF

# Se o app já estiver aberto à mão, fecha para o agente assumir.
pkill -f "$BIN" 2>/dev/null && sleep 1 || true

for label in $APP_LABEL $REBUILD_LABEL; do
    plutil -lint "$AGENTS/$label.plist" >/dev/null
    launchctl bootstrap "$DOMAIN" "$AGENTS/$label.plist"
done
echo "Início automático ligado ($APP_LABEL e $REBUILD_LABEL)."
