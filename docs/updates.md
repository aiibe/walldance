# App updates

The static site at `walldance.souk.dev` hosts the signed update feed. Downloads and in-app updates use DMGs from GitHub Releases.

## Release

1. Update `CHANGELOG.md`, commit, and push a version tag such as `v0.1.1`.
2. CI tests, builds, signs, and notarizes the universal DMG, then attaches it and `appcast.xml` to a **draft** release.
3. Review and publish the release on GitHub when ready.
4. In `../walldance-site`, run `python3 scripts/update-release.py v0.1.1`. Review, commit, push, and redeploy the static site. The command copies the signed feed unchanged and rejects drafts and prereleases.

Build numbers must increase with each release. Keep published DMGs available for clients with older feeds. Before changing macOS or hardware requirements, retain the last compatible release in the feed.

## Signing and verification

The public verification key is in `scripts/update-public-key.txt`. Its private key is stored in macOS Keychain under account `com.walldance.app` and in an encrypted repository secret for CI. Keep a secure private-key backup; never commit it.

To generate a feed locally after notarization, run `zsh scripts/generate-appcast.sh dist/Walldance-<version>.dmg`. Temporary staging files are removed automatically.

Verify installation and relaunch using two signed, notarized builds with increasing build numbers and a separate test feed. Use a temporary video library and wallpaper catalogue. Confirm restarting waits for video preparation and wallpaper changes to finish.

Version 0.1.0 needs one manual installation of an updater-enabled release.
