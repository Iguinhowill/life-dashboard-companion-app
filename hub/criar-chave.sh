#!/usr/bin/env bash
# Cria a chave que assina o APK do Hub Saúde e grava nos secrets do GitHub do fork.
# Rode no SEU terminal (Git Bash), uma vez só. A senha não aparece na tela nem vai para o chat.
# Precisa de: openssl (vem com o Git Bash) e gh logado na conta Iguinhowill.
set -euo pipefail

repo="Iguinhowill/life-dashboard-companion-app"
alias_chave="hub-saude"
destino="${1:-$HOME/hub-saude-assinatura.p12}"

if [ -e "$destino" ]; then
  echo "Já existe $destino. Não sobrescrevo: trocar a chave obriga a desinstalar o app do celular."
  exit 1
fi

read -rsp "Senha da chave (12+ caracteres; guarde no gerenciador de senhas): " senha; echo
read -rsp "Repita a senha: " senha2; echo
[ "$senha" = "$senha2" ] || { echo "As senhas não conferem."; exit 1; }
[ "${#senha}" -ge 12 ] || { echo "Use pelo menos 12 caracteres."; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Certificado autoassinado de 10.000 dias, como o Android espera de uma chave de app.
openssl req -x509 -newkey rsa:4096 -sha256 -days 10000 -noenc \
  -subj "/CN=Hub Saude" -keyout "$tmp/chave.pem" -out "$tmp/cert.pem" 2>/dev/null
# PKCS12: o Gradle lê direto. Nesse formato a senha da chave é a mesma do arquivo.
SENHA_CHAVE="$senha" openssl pkcs12 -export -name "$alias_chave" \
  -inkey "$tmp/chave.pem" -in "$tmp/cert.pem" -out "$destino" -passout env:SENHA_CHAVE
chmod 600 "$destino"

base64 -w0 "$destino" | gh secret set KEYSTORE_FILE_BASE64 --repo "$repo"
printf '%s' "$senha" | gh secret set KEYSTORE_PASSWORD --repo "$repo"
printf '%s' "$senha" | gh secret set KEY_PASSWORD --repo "$repo"
printf '%s' "$alias_chave" | gh secret set KEY_ALIAS --repo "$repo"

echo
echo "Pronto: os 4 secrets estão no GitHub e a chave ficou em $destino."
echo "Guarde uma cópia desse arquivo junto da senha. Sem ele, o celular não aceita atualizações:"
echo "seria preciso desinstalar o app e configurar de novo."
