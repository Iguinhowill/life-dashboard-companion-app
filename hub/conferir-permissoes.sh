#!/usr/bin/env bash
# Confere as permissões de um APK contra hub/permissoes.txt.
# Falha se o APK pedir alguma permissão fora da lista; só avisa se faltar alguma da lista.
# Uso: bash hub/conferir-permissoes.sh app/build/outputs/apk/hub/app-hub.apk
set -euo pipefail

apk="${1:?Passe o caminho do APK}"
dir="$(cd "$(dirname "$0")" && pwd)"

: "${ANDROID_HOME:?ANDROID_HOME não definido}"
build_tools="$(ls -d "$ANDROID_HOME"/build-tools/*/ | sort -V | tail -1)"
aapt2="${build_tools}aapt2"

pacote="$("$aapt2" dump packagename "$apk")"
pacote_re="${pacote//./\.}"

reais="$("$aapt2" dump permissions "$apk" \
  | sed -n "s/^uses-permission[^:]*: name='\([^']*\)'.*/\1/p" \
  | sed "s/^${pacote_re}\./APP./" \
  | sort -u)"
if [ -z "$reais" ]; then
  # Lista vazia é o aapt2 com outro formato de saída, não um app sem permissões: sem esta
  # parada, a conferência passaria sem ter conferido nada.
  echo "::error::Não consegui ler as permissões do APK com $aapt2."
  exit 1
fi
esperadas="$(sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^$/d' "$dir/permissoes.txt" | sort -u)"

echo "Permissões do APK ($pacote):"
printf '  %s\n' $reais

faltando="$(comm -13 <(printf '%s\n' "$reais") <(printf '%s\n' "$esperadas"))"
extras="$(comm -23 <(printf '%s\n' "$reais") <(printf '%s\n' "$esperadas"))"

if [ -n "$faltando" ]; then
  echo "::warning::Estão em hub/permissoes.txt, mas o APK não pede: $(echo $faltando)"
fi
if [ -n "$extras" ]; then
  echo "::error::O APK pede permissões fora de hub/permissoes.txt: $(echo $extras)"
  echo "Se vieram do app original, decida: remova em app/src/hub/AndroidManifest.xml ou aceite em hub/permissoes.txt."
  exit 1
fi
echo "Permissões conferidas."
