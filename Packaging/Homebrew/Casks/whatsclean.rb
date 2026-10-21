cask "whatsclean" do
  version "1.1.2"
  sha256 "1a7cc5374938dcbefa3183d07de99b53a0ad0a5eaa04199d7abe785720a73ab9"

  url "https://github.com/vviniciusbarreto/WhatsClean/releases/download/v#{version}/WhatsClean-#{version}-arm64.zip"
  name "WhatsClean"
  desc "Private WhatsApp media and storage cleaner"
  homepage "https://vviniciusbarreto.github.io/WhatsClean/"

  depends_on arch: :arm64
  depends_on macos: :monterey

  app "WhatsClean.app"

  caveats <<~EOS
    Release notes:
    https://github.com/vviniciusbarreto/WhatsClean/releases/tag/v#{version}

    WhatsClean is not Apple-notarized, so macOS may require approval on first
    launch. Try opening the app, then use System Settings > Privacy & Security >
    Open Anyway.
  EOS
end
