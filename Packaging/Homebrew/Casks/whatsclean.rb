cask "whatsclean" do
  version "1.0.0"
  sha256 "d3032c64bea3c7e6d352a49fbc61cc0922b4e389fe70e222514f65150104e8fb"

  url "https://github.com/vviniciusbarreto/WhatsClean/releases/download/v#{version}/WhatsClean-#{version}-arm64.zip"
  name "WhatsClean"
  desc "Gerenciador e limpador de mídias do WhatsApp"
  homepage "https://github.com/vviniciusbarreto/WhatsClean"

  depends_on arch: :arm64
  depends_on macos: :monterey

  app "WhatsClean.app"

  caveats <<~EOS
    Como o WhatsClean ainda não possui notarização Apple, o macOS pode pedir
    autorização manual na primeira abertura. Tente abrir o app e use:
    Ajustes do Sistema > Privacidade e Segurança > Abrir Mesmo Assim.
  EOS
end
