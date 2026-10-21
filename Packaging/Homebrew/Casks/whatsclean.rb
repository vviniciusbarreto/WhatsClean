cask "whatsclean" do
  version "1.1.3"
  sha256 "be046302eeb9c54d7f4c58f2263e224e9efb72e4066db833f2f89c18f9c84d3f"

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
