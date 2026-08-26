cask "whatsclean" do
  version "1.0.3"
  sha256 "fea08e6be5897997a041609ad4b42cb4f1763c3fd67c629e673ac06cb245c0c1"

  url "https://github.com/vviniciusbarreto/WhatsClean/releases/download/v#{version}/WhatsClean-#{version}-arm64.zip"
  name "WhatsClean"
  desc "Browse and clean media files stored by WhatsApp"
  homepage "https://github.com/vviniciusbarreto/WhatsClean"

  depends_on arch: :arm64
  depends_on macos: :monterey

  app "WhatsClean.app"

  caveats <<~EOS
    WhatsClean is not Apple-notarized, so macOS may require approval on first
    launch. Try opening the app, then use System Settings > Privacy & Security >
    Open Anyway.
  EOS
end
