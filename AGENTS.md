# Repository Guidelines

## Project Structure & Module Organization

Walldance is a native macOS video wallpaper shelf using SwiftUI and AVKit, with automatic app updates.

- `Package.swift` defines the executable, core library, and test target.
- `Sources/Walldance/` contains the app entry point, views, playback, and `LibraryModel`.
- `Sources/WalldanceCore/VideoLibrary.swift` owns video imports, persistence, deduplication, and removal.
- `Tests/WalldanceCoreTests/` contains library tests and generated video fixtures.
- `scripts/build-app.sh` packages the executable into `dist/Walldance.app`.

Keep UI behavior in the app target and storage logic in the core. `Assets/` contains the icon master; `Sources/Walldance/Resources/` contains the runtime app icon. UI icons use SF Symbols. Generated `.build/`, `.swiftpm/`, and `dist/` files are ignored.

The installer shows only Walldance and the Applications shortcut. Keep the artwork in `scripts/InstallerBackground.swift` aligned with `scripts/layout-dmg.applescript`; keep the changelog in the release description.

## Build, Test, and Development Commands

Use macOS 26 or later with Swift 6 and an SDK supporting the macOS 26 APIs referenced by the UI. The deployment target is macOS 26.

- `swift build` — compile the package for development.
- `swift run Walldance` — build and launch locally.
- `swift test` — run all library tests.
- `swift test --filter VideoLibraryTests` — run the library suite explicitly.
- `zsh scripts/build-app.sh` — create a release app bundle with ad hoc code signing.
- `zsh scripts/build-dmg.sh` — build the app and package a drag-to-Applications installer.
- `open dist/Walldance.app` — launch the packaged app.

After app or asset changes, rebuild `dist/Walldance.app` with `zsh scripts/build-app.sh` before handing off.

Open `Package.swift` in Xcode for interactive development.

## Coding Style & Naming Conventions

Match existing Swift style: four-space indentation, same-line opening braces, `UpperCamelCase` types, and `lowerCamelCase` methods and properties. Name files after their primary type. Keep UI state on `@MainActor` and library mutations isolated in the `VideoLibrary` actor. Prefer structured concurrency and explicit error handling. No formatter or linter is configured.

## Testing Guidelines

Use Swift Testing (`@Test`, `#expect`, `#require`), with descriptive behavior-based method names in `*Tests.swift` files. Generate media in unique temporary directories and clean up with `defer`. Cover persistence, concurrent imports, invalid media, and corrupt manifests when changing storage behavior. No coverage threshold is configured. For UI changes, manually verify import, hover playback, removal, and inactive-window pausing.

## Commit & Pull Request Guidelines

Use concise imperative commit subjects, such as `Fix duplicate video imports`. Describe behavior changes, link relevant issues, and report validation in pull requests. Include screenshots for visible UI changes.

## Documentation

Keep `CHANGELOG.md` in sync as user-visible changes happen, including behavior changes, additions, and fixes. Update it as part of the work rather than waiting for a commit or release, and revise entries when the behavior changes again.

Keep `README.md` and `CHANGELOG.md` concise and easy to read. The README should cover what the app does, requirements, installation, and basic use in plain language. Leave out implementation details, build commands, signing, notarization, and CI setup. Keep changelog entries to a few short bullets about user-visible changes per version; avoid technical details and development history. Update the changelog for user-visible releases. Use `## 1.2.3` version headings: tag releases create a draft with that section as the GitHub release description and attach the notarized DMG. Keep releases as drafts for user review unless explicitly asked to publish.

## Releases and Site Updates

For every new version, remind the user that publishing the GitHub release and updating the static site are separate steps:

1. Update `CHANGELOG.md`, commit, and push a version tag such as `v0.1.2`.
2. CI creates a draft GitHub release with the notarized DMG and signed `appcast.xml`. Keep it as a draft for review unless explicitly asked to publish.
3. After the release is published, run `python3 scripts/update-release.py v0.1.2` in `../walldance-site`, using the actual release tag.
4. Review, commit, push, and redeploy the static site to `https://walldance.souk.dev`.

The site hosts the landing page and update feed; DMGs download from GitHub Releases. Installed apps discover the new version only after the site's feed is updated and deployed. Keep signed feed bytes unchanged and retain published DMGs for clients with older feeds. See `docs/updates.md` for signing and verification details.

## Data Safety

`library.json` lives in `~/Library/Application Support/Walldance/Videos` and owns all shelf records. Each record requires prepared wallpaper metadata. The single prepared video and its thumbnail live in the per-user `com.apple.wallpaper/aerials` directory, shared with macOS. Preserve original files, atomic manifest writes, catalogue backups, and corrupt-manifest protection. Use temporary libraries and wallpaper catalogues for automated tests.
