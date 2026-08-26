cask "whatsclean" do
  version "1.0.0"
  sha256 "2af0cb3d8e7d23a03e73b10b77a97fe963318ef45b5ff29398d4cb14967ec5c3"

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
