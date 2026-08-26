# WhatsClean

WhatsClean is a native macOS utility for finding and cleaning media files stored by WhatsApp.

Built for Apple Silicon and macOS 12 or later.

## Features

- Browse WhatsApp images, videos, audio files, and documents.
- Preview files before removing them.
- Move selected files to the Trash safely.
- Schedule daily cleanup of files older than seven days.
- Check for and install updates directly from the app with Sparkle.
- Show or hide the optional menu bar icon.
- Use the system appearance or choose Light or Dark mode.
- Grant persistent access to the detected WhatsApp folder with one guided click.

## Install

Download the latest DMG from [GitHub Releases](https://github.com/vviniciusbarreto/WhatsClean/releases/latest), open it, and drag **WhatsClean** to **Applications**.

Because the app is distributed without paid Apple notarization, macOS may block the first launch. Try opening the app once, then go to **System Settings > Privacy & Security** and choose **Open Anyway**.

If that option is unavailable, open Terminal and run:

```bash
xattr -dr com.apple.quarantine /Applications/WhatsClean.app
```

This is required only for the first launch after installation.

On the first app launch, click **Grant WhatsApp Access**. WhatsClean opens the
expected WhatsApp data location automatically; select the highlighted folder
and click **Grant Access**. The choice is stored and reused on future launches.

## Updates

WhatsClean checks its signed GitHub update feed through the embedded Sparkle framework. Update preferences are available under **WhatsClean > Settings**.

Sparkle is included in the app. Users do not need to install Sparkle, Xcode, or Homebrew.

## Homebrew

Once the official tap is available, install with:

```bash
brew install --cask vviniciusbarreto/tap/whatsclean
```

Upgrade with:

```bash
brew update
brew upgrade --cask whatsclean
```

## Build from source

```bash
git clone https://github.com/vviniciusbarreto/WhatsClean.git
cd WhatsClean
./scripts/install-sparkle.sh
./build.sh
```

The generated app, DMG, and ZIP are written to the project directory.

## Create a release

```bash
./scripts/release.sh 1.0.3 4
```

The Sparkle private signing key remains in the macOS Keychain and must never be committed or shared.

## License

WhatsClean is available under the [GNU General Public License v3.0](LICENSE).

Created by [Vinicius Barreto](https://github.com/vviniciusbarreto).
