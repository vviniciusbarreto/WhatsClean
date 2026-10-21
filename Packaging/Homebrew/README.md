# WhatsClean Homebrew Tap

This directory contains the source for the public `vviniciusbarreto/homebrew-tap` repository.

### WhatsClean 1.1.2 — macOS Golden Gate improvements

Updated for macOS Golden Gate and validated on macOS 27.0.1 (Apple Silicon).

- Reliable Auto (7d) cleanup with the app closed and its menu bar icon disabled.
- Daily cleanup at 10:00 local time, with catch-up after sleep and execution at login; only recognized media older than seven days goes to the Trash.
- Schedule repair after app or macOS updates.
- Folder access retained through scanning and cleanup, with clear reports for access failures or incomplete scans.
- File age rechecked before cleanup; recently changed files, symbolic links, and content outside the authorized media folder are preserved.

The regression tests and a calendar-triggered background check passed. [Full release notes](https://github.com/vviniciusbarreto/WhatsClean/releases/tag/v1.1.2).

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
