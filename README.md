# WhatsClean 🧹✨

Um gerenciador e limpador nativo de mídias do WhatsApp para macOS em Macs Apple Silicon.

Criado por Vinicius Barreto (@vviniciusbarreto) • Copyright © 2026.
Open Source sob licença GPLv3.

---

## 🚀 Build local

```bash
cd ~/Documents/WhatsClean
./scripts/install-sparkle.sh # necessário apenas na primeira vez
bash build.sh
open WhatsClean.app
```

O build local usa assinatura ad-hoc e serve para desenvolvimento ou compartilhamento
informal com a confirmação manual descrita abaixo.

## Compartilhamento gratuito com amigos

Sem uma assinatura paga Developer ID, o DMG pode ser compartilhado, mas o macOS exigirá
uma autorização manual na primeira abertura. Gere o pacote com:

```bash
cd ~/Documents/WhatsClean
./build.sh
```

Envie o arquivo `WhatsClean.dmg`. Ele inclui o documento `LEIA PRIMEIRO - INSTALAÇÃO.txt`: após tentar abrir
o app uma vez, o usuário deve acessar Ajustes do Sistema > Privacidade e Segurança e clicar
em **Abrir Mesmo Assim**. Não é necessário usar `xattr`.

Para encontrar mídias nas pastas protegidas do WhatsApp, alguns Macs podem exigir que o
usuário autorize o WhatsClean em Ajustes do Sistema > Privacidade e Segurança > Acesso Total
ao Disco. Se o acesso for negado, o app mostra uma orientação e continua funcionando sem crash.

## Distribuição assinada e notarizada

É necessário ter uma assinatura **Developer ID Application** no Keychain e ser membro do
Apple Developer Program. Guarde as credenciais de notarização no Keychain uma única vez:

Substitua todos os campos `SEU_...` pelos seus dados reais; eles são exemplos, não valores
que funcionam literalmente. A senha deve ser uma senha específica de app, não a senha normal
da sua conta Apple.

```bash
xcrun notarytool store-credentials "WhatsClean-notary" \
  --apple-id "SEU_APPLE_ID" \
  --team-id "SEU_TEAM_ID" \
  --password "SENHA_ESPECIFICA_DE_APP"
```

Depois gere o app para Apple Silicon e o DMG final:

```bash
APP_SIGNING_IDENTITY="Developer ID Application: SEU NOME (SEU_TEAM_ID)" \
NOTARY_PROFILE="WhatsClean-notary" \
VERSION="1.0.0" BUILD_NUMBER="1" bash build.sh
```

Confira o artefato antes de publicar:

```bash
codesign --verify --deep --strict --verbose=2 WhatsClean.app
spctl --assess --type execute --verbose=4 WhatsClean.app
xcrun stapler validate WhatsClean.dmg
spctl --assess --type open --context context:primary-signature --verbose=4 WhatsClean.dmg
lipo -archs WhatsClean.app/Contents/MacOS/WhatsClean
```

Não distribua um build ad-hoc e não peça ao usuário para remover a quarentena com `xattr`.

## Atualizações pelo próprio aplicativo

O Sparkle 2.9.6 está incorporado ao bundle: quem instala o WhatsClean não precisa
instalar nenhuma dependência. Em **WhatsClean > Configurações**, o usuário pode
ativar ou desativar as verificações e os downloads automáticos. Também é possível
usar **Procurar atualização agora**.

A chave privada EdDSA fica somente no Chaves deste Mac. Nunca publique ou exporte
essa chave para o repositório. Para preparar uma nova versão e assinar seu ZIP:

```bash
./scripts/release.sh 1.0.1 2
```

Publique o ZIP criado em `Releases/1.0.1/` numa GitHub Release com a tag `v1.0.1`
e envie o `appcast.xml` atualizado para a branch `main`.

## Homebrew

O modelo do Cask está em `Packaging/Homebrew/Casks/whatsclean.rb`. Depois de
publicar o repositório `vviniciusbarreto/homebrew-tap`, a instalação será:

```bash
brew install --cask vviniciusbarreto/tap/whatsclean
```

O Homebrew não substitui o Sparkle: instalações pelo DMG podem ser atualizadas no
próprio app; usuários do Cask também podem usar `brew upgrade --cask whatsclean`.
