cask "whatsclean" do
  version "1.0.1"
  sha256 "78ed3382aace53f90e1728caab0961236701cbcc20b6e2f0ec9bc26bffeb8c5b"

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
