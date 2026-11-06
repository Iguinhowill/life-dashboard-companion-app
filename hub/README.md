# Hub Saúde

Fork do [Life Dashboard Companion](https://github.com/owen282000/life-dashboard-companion-app) (licença MIT, de Owen Vogelaar) usado pelo [hub pessoal](https://github.com/Iguinhowill/hub-pessoal). Ele lê do Health Connect o sono, os passos e a FC em repouso do Galaxy Watch e manda para o webhook do hub.

O app é o mesmo do original. A variante `hub` só **tira** coisas, e tira pelo manifesto. Assim o Android garante o limite, independentemente do código que venha do original.

## O que muda em relação ao original

| | Original | Hub Saúde |
|---|---|---|
| Health Connect | leitura de 33 tipos e gravação de 7 | leitura de sono, passos e FC em repouso, em segundo plano e com histórico |
| Câmera e tempo de tela | pede | não pede |
| Links de pareamento (`lifedashboard://pair` e owen282000.github.io) | abrem o app | não abrem por link |
| Application id | `com.owen282000.lifedashboard` | `com.owen282000.lifedashboard.hub` |
| Nome no celular | Life Dashboard | Hub Saúde |
| Assinatura e atualizações | as do autor | a nossa chave; só atualiza quando a gente puxar do original |

O resto é o original: telas, destinos (Home Assistant e MQTT continuam no menu, só não são usados), fila de reenvio, widget e agenda. Os tipos sem permissão aparecem bloqueados na tela de tipos.

## Onde fica cada mudança

O diff contra o original fica pequeno de propósito, para os merges do original continuarem limpos:

- `app/build.gradle.kts`: o build type `hub`, no fim de `buildTypes`. É o único arquivo do original alterado.
- `app/src/hub/AndroidManifest.xml`: as permissões removidas e a `MainActivity` sem os links de pareamento.
- `app/src/hub/res/values/strings.xml`: o nome "Hub Saúde".
- `hub/permissoes.txt` e `hub/conferir-permissoes.sh`: a lista fechada de permissões. O build falha se o APK pedir qualquer outra, inclusive uma que o original acrescente.
- `hub/criar-chave.sh`: prepara a assinatura (chave, environment `assinatura` e secrets; desliga o `release.yml` quando o GitHub já o registrou).
- `.github/workflows/hub.yml`: compila e confere as permissões em toda PR e push; na `main`, assina e publica o APK.

Não edite outros arquivos do original. Se precisar mudar comportamento, prefira um arquivo novo em `app/src/hub/`.

## Assinatura

A chave fica longe do código que ainda não foi revisado:

- **Build sem chave:** o job `apk` roda o Gradle do original sem nenhum secret e com o token só de leitura. Numa PR de sincronização, é ali que roda o código novo do autor.
- **Assinatura separada:** o job `publicar` pega o APK pronto do artefato e assina com o `apksigner` do SDK, sem rodar o Gradle.
- **Só na `main`:** os secrets moram no environment `assinatura`, que só libera a `main`. Nenhuma PR consegue ler a chave, nem um workflow novo que venha do original.
- **`release.yml` sem a chave:** o original assina por ele quando chega uma tag `X.Y.Z`. Como ele não usa o environment, não lê a chave. O `upstream` também não traz tags (`tagOpt --no-tags`). O GitHub só registra um workflow depois que ele roda; quando o `release.yml` for registrado, `hub/criar-chave.sh` o desliga.

## Primeira instalação

1. **Chave de assinatura**, uma vez só, no seu terminal (Git Bash), fora do chat:
   ```sh
   bash hub/criar-chave.sh
   ```
   Ele pede uma senha e cria `~/hub-saude-assinatura.p12`. Depois cria o environment `assinatura` restrito à `main`, desliga o `release.yml` do original se o GitHub já o tiver registrado e grava 3 secrets no environment. Guarde o arquivo e a senha no gerenciador de senhas. Sem eles, o celular não aceita atualizações e é preciso desinstalar e configurar de novo. Pode rodar de novo: ele reaproveita a chave e confere o que já está feito.
2. **Gerar o APK assinado:** depois dos secrets, rode o workflow *Hub APK* na `main` pela aba Actions (*Run workflow*) ou faça um push na `main`. O APK sai na pré-release [hub-latest](https://github.com/Iguinhowill/life-dashboard-companion-app/releases/tag/hub-latest), junto com o `mapping-hub.txt` do R8, que serve para ler um stack trace de crash.
3. **No celular:**
   1. Abra a página da hub-latest, baixe `hub-saude.apk` e instale.
   2. Nos Galaxy com o Bloqueador automático ligado (*Configurações › Segurança e privacidade*), desligue-o durante a instalação e religue depois.
   3. Confira se o SHA-256 das notas da release bate, se quiser.
4. **Configuração:** siga `docs/saude.md` do hub (endereço do webhook, segredo HMAC e agenda).
   - **Tipos de dados:** no assistente inicial, escolha **Decidir depois**. O Conexão Saúde oferece só sono, passos e FC em repouso, e o que você permitir vira a seleção. Os presets *O essencial* e *Todos* ligam tipos que esta variante não pode ler, e o botão de permitir ficaria pendente para sempre.
   - **Pareamento:** recuse qualquer diálogo que aparecer, porque o destino do hub é cadastrado à mão.

## Atualizar a partir do original

Não use o botão *Sync fork* direto na `main`: ele traz o código sem revisão. O caminho é:

```sh
git fetch upstream
git log --oneline main..upstream/main      # o que mudou
git switch -c chore/sincroniza-upstream-<versão>
git merge upstream/main
git push -u origin HEAD
gh pr create --repo Iguinhowill/life-dashboard-companion-app --base main
```

Na PR:
1. Leia o diff do original, começando por `.github/workflows`. Workflow novo ou alterado roda na própria PR. Ele não enxerga a chave, mas pode pedir permissão de escrita no repositório.
2. Espere o *Hub APK* passar. Se ele acusar permissão nova, decida entre removê-la em `app/src/hub/AndroidManifest.xml` e aceitá-la em `hub/permissoes.txt`.
3. Depois do merge, a hub-latest é refeita, e você instala por cima no celular.

No clone local, o remote `upstream` é só de leitura, para nada ir parar no repositório do autor por engano. Num clone novo, repita:

```sh
git remote add upstream https://github.com/owen282000/life-dashboard-companion-app.git
git remote set-url --push upstream NAO-ENVIAR-PARA-O-ORIGINAL
git config remote.upstream.tagOpt --no-tags
```
