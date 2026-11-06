#!/usr/bin/env bash
# Prepara a assinatura do Hub Saúde no fork. Rode no SEU terminal (Git Bash).
# A senha não aparece na tela nem vai para o chat. Pode rodar de novo: cada passo confere o que já
# está feito.
#
# O que ele faz, nesta ordem:
#  1. Cria a chave em ~/hub-saude-assinatura.p12, ou reaproveita a que já existe (conferindo a senha).
#  2. Cria no GitHub o environment "assinatura", que só libera os secrets para a branch main. Assim,
#     nenhuma PR (nem a de sincronizar com o original) enxerga a chave.
#  3. Desliga no fork o release.yml do original, se o GitHub já o registrou. Ele assina quando
#     chega uma tag X.Y.Z, mas fica sem a chave porque não usa o environment.
#  4. Grava a chave, a senha e o alias como secrets desse environment.
#
# Precisa de: openssl (vem com o Git Bash) e gh logado na conta Iguinhowill.
set -euo pipefail

repo="Iguinhowill/life-dashboard-companion-app"
ambiente="assinatura"
alias_chave="hub-saude"
destino="${1:-$HOME/hub-saude-assinatura.p12}"

command -v openssl >/dev/null || { echo "Não achei o openssl. Rode no Git Bash."; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "O gh não está logado. Rode: gh auth login"; exit 1; }

# Secrets de assinatura no nível do repositório valeriam para qualquer workflow, inclusive o
# release.yml do original. Aqui eles só podem existir no environment.
antigos="$(gh secret list --repo "$repo" --json name --jq '.[].name' | grep -E '^(KEYSTORE_|KEY_)' || true)"
if [ -n "$antigos" ]; then
  echo "Há secrets de assinatura no nível do repositório: $(echo $antigos)."
  echo "Eles valem para qualquer workflow, inclusive o release.yml do original. Apague antes de seguir:"
  for s in $antigos; do echo "  gh secret delete $s --repo $repo"; done
  exit 1
fi

tmp="$(mktemp -d)"
criou_chave=false
concluiu=false
encerrar() {
  rm -rf "$tmp"
  if [ "$concluiu" != true ]; then
    # Uma chave criada agora ainda não está em uso: apagar deixa rodar de novo do zero.
    if [ "$criou_chave" = true ]; then rm -f "$destino"; fi
    echo "Falhou antes do fim. Corrija o erro acima e rode de novo." >&2
  fi
}
trap encerrar EXIT

# 1. Chave
if [ -e "$destino" ]; then
  echo "Usando a chave que já existe em $destino."
  read -rsp "Senha dessa chave: " senha; echo
  if ! SENHA_CHAVE="$senha" openssl pkcs12 -in "$destino" -passin env:SENHA_CHAVE -noout 2>/dev/null; then
    echo "A senha não abre $destino."
    exit 1
  fi
else
  read -rsp "Senha da chave nova (12+ caracteres; guarde no gerenciador de senhas): " senha; echo
  read -rsp "Repita a senha: " senha2; echo
  [ "$senha" = "$senha2" ] || { echo "As senhas não conferem."; exit 1; }
  [ "${#senha}" -ge 12 ] || { echo "Use pelo menos 12 caracteres."; exit 1; }

  echo "Gerando a chave..."
  # Certificado autoassinado de 10.000 dias, como o Android espera de uma chave de app. A chave
  # privada já sai cifrada com a senha, então nem o arquivo temporário fica em claro.
  # MSYS_NO_PATHCONV: sem ele, o Git Bash troca "/CN=..." por "C:/Program Files/Git/CN=..." e o
  # openssl recusa o nome. Como ele também deixa de converter /tmp/..., os arquivos vão com nome
  # relativo, de dentro da pasta temporária. Fora do Windows a variável não faz nada.
  if ! (cd "$tmp" && SENHA_CHAVE="$senha" MSYS_NO_PATHCONV=1 openssl req -x509 -newkey rsa:4096 \
    -sha256 -days 10000 -subj "/CN=Hub Saude" -keyout chave.pem -out cert.pem \
    -passout env:SENHA_CHAVE 2>erro.txt); then
    cat "$tmp/erro.txt" >&2
    exit 1
  fi
  # PKCS12: o apksigner lê direto. Nesse formato a senha da chave é a mesma do arquivo.
  SENHA_CHAVE="$senha" openssl pkcs12 -export -name "$alias_chave" \
    -inkey "$tmp/chave.pem" -passin env:SENHA_CHAVE -in "$tmp/cert.pem" \
    -out "$tmp/chave.p12" -passout env:SENHA_CHAVE
  cp "$tmp/chave.p12" "$destino"
  criou_chave=true
  chmod 600 "$destino"
fi

# 2. Environment que só libera a main
echo "Configurando o environment \"$ambiente\" (só a branch main)..."
gh api -X PUT "repos/$repo/environments/$ambiente" --input - > /dev/null <<'JSON'
{"deployment_branch_policy": {"protected_branches": false, "custom_branch_policies": true}}
JSON
if ! gh api "repos/$repo/environments/$ambiente/deployment-branch-policies" \
  --jq '.branch_policies[].name' | grep -qx main; then
  gh api -X POST "repos/$repo/environments/$ambiente/deployment-branch-policies" \
    -f name=main -f type=branch > /dev/null
fi

# 3. release.yml do original desligado no fork
# O GitHub só registra um workflow depois que ele roda uma vez. Enquanto o release.yml nunca rodou
# aqui, a API responde 404 e não há o que desligar. Tudo bem: ele não usa o environment
# "assinatura", então não lê a chave. O passo só reforça isso quando ele já existe.
estado_release() {
  local estado
  if estado="$(gh api "repos/$repo/actions/workflows/release.yml" --jq .state 2>"$tmp/erro-api.txt")"; then
    echo "$estado"
  elif grep -q "HTTP 404" "$tmp/erro-api.txt"; then
    echo "nunca rodou no fork (não registrado)"
  else
    # Rede, escopo do token, limite da API: mostra o erro em vez de fingir que está tudo bem.
    cat "$tmp/erro-api.txt" >&2
    return 1
  fi
}
estado="$(estado_release)"
if [ "$estado" = "active" ]; then
  echo "Desligando o release.yml do original..."
  gh api -X PUT "repos/$repo/actions/workflows/release.yml/disable"
fi

# 4. Secrets do environment
echo "Gravando os secrets..."
base64 -w0 "$destino" | gh secret set KEYSTORE_FILE_BASE64 --env "$ambiente" --repo "$repo"
printf '%s' "$senha" | gh secret set KEYSTORE_PASSWORD --env "$ambiente" --repo "$repo"
printf '%s' "$alias_chave" | gh secret set KEY_ALIAS --env "$ambiente" --repo "$repo"
concluiu=true

echo
echo "Secrets do environment $ambiente:"
gh secret list --env "$ambiente" --repo "$repo"
echo "Branches liberadas: $(gh api "repos/$repo/environments/$ambiente/deployment-branch-policies" --jq '[.branch_policies[].name] | join(", ")')"
echo "release.yml: $(estado_release || echo "não consegui consultar")"
echo
echo "Pronto. A chave fica em $destino."
echo "Guarde uma cópia desse arquivo junto da senha. Sem ele, o celular não aceita atualizações:"
echo "seria preciso desinstalar o app e configurar de novo."
