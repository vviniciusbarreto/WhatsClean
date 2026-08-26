cask "whatsclean" do
  version "1.1.0"
  sha256 "dfe4afce95c8b5b8afed01b0c2e931a7e28c4056d2e25bd3bd3dce4ad7a4c71f"

  url "https://github.com/vviniciusbarreto/WhatsClean/releases/download/v#{version}/WhatsClean-#{version}-arm64.zip"
  name "WhatsClean"
  desc "Private WhatsApp media and storage cleaner"
  homepage "https://vviniciusbarreto.github.io/WhatsClean/"

  depends_on arch: :arm64
  depends_on macos: :monterey

  app "WhatsClean.app"

  caveats <<~EOS
    WhatsClean is not Apple-notarized, so macOS may require approval on first
    launch. Try opening the app, then use System Settings > Privacy & Security >
    Open Anyway.
  EOS
end
