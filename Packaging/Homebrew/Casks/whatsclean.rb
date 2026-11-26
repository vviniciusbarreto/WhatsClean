cask "whatsclean" do
  version "1.1.4"
  sha256 "b1e74dace36a4b1f70d2154258fd59ff248fdbc32196632783d8c6eeee493c2d"

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
