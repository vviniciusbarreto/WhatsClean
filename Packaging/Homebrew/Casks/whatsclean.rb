cask "whatsclean" do
  version "1.1.1"
  sha256 "1bdaeaf2fdf5e85d228a12b6bd49b469df0fc375393225adf15dd609707b298f"

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
