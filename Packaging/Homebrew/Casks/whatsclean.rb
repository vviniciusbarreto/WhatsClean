cask "whatsclean" do
  version "1.0.2"
  sha256 "2efabdb933a9dae07103b78bc0100e24141436807b9c7f8fd99c69ddcb0de9de"

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
