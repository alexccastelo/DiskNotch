#!/bin/zsh
# Cria, uma única vez, o certificado "DiskNotch Local Signing" no chaveiro de login.
#
# Com ele, o build-app.sh assina o app sempre com a mesma identidade. Assim o macOS
# reconhece o DiskNotch depois de cada recompilação e não pede de novo o Acesso Total
# ao Disco. É um certificado só seu, válido nesta máquina; não precisa de conta de
# desenvolvedor da Apple e não é confiado pelo sistema para mais nada.
#
#   Scripts/criar-certificado-local.sh             cria (se ainda não existir)
#   Scripts/criar-certificado-local.sh --remover   apaga o certificado e a chave
set -euo pipefail

NAME="DiskNotch Local Signing"
KEYCHAIN="${DISKNOTCH_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
OPENSSL=/usr/bin/openssl   # LibreSSL do sistema: gera um .p12 que o chaveiro aceita

if [[ "${1:-}" == "--remover" ]]; then
    security delete-identity -c "$NAME" "$KEYCHAIN" && echo "Certificado removido." || echo "Nada a remover."
    exit 0
fi

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    echo "O certificado \"$NAME\" já existe. Nada a fazer."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<EOF
[ req ]
distinguished_name = dn
x509_extensions = ext
prompt = no
[ dn ]
CN = $NAME
[ ext ]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cnf" 2>/dev/null
PASS="$("$OPENSSL" rand -hex 16)"
"$OPENSSL" pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$NAME" -out "$TMP/identity.p12" -passout "pass:$PASS"

# -T: só o codesign pode usar a chave, sem perguntar a cada build.
security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "$PASS" -T /usr/bin/codesign >/dev/null

echo "Certificado \"$NAME\" criado em $(basename "$KEYCHAIN")."
echo "Rode ./build-app.sh: o app passa a ser assinado com ele."
