# WhatsClean Homebrew Tap

This directory contains the source for the public `vviniciusbarreto/homebrew-tap` repository.

### WhatsClean 1.1.3 — clearer confirmation and localization

- Moving selected files to the Trash now shows the number of files and the space you will recover before you confirm.
- The WhatsApp folder access window and its alerts follow your macOS language, including Brazilian Portuguese.
- Regression tests use only synthetic files and can no longer reach a real WhatsApp folder authorization; automated macOS checks run on every change.

Automatic cleanup, scheduling, and Trash behavior are unchanged. [Full release notes](https://github.com/vviniciusbarreto/WhatsClean/releases/tag/v1.1.3).

To receive the update notice and release notes, open WhatsClean with automatic update checks enabled, or use **Check for Updates**. A fully quit app runs only its scheduled cleanup; it does not check for updates.

Install:

```bash
brew install --cask vviniciusbarreto/tap/whatsclean
```

Upgrade:

```bash
brew update
brew upgrade --cask whatsclean
```

`scripts/release.sh` updates `version` and `sha256` in `Packaging/Homebrew/Casks/whatsclean.rb`. Copy the cask to the tap with:

```bash
./scripts/update-cask.sh VERSION /path/to/homebrew-tap
```
