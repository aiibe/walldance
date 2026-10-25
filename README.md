# Walldance

A small, native macOS video shelf built with SwiftUI and AVKit. Drop videos into the window, or use **+** / **⌘O**. Hover over a card to play its video; move the pointer away to pause. Videos loop silently, with one playing at a time. Right-click a card to remove it.

Imported videos are copied into `~/Library/Application Support/Walldance/Videos`, so moving the original won’t break your library. Removing a video deletes its imported copy, leaving the original untouched. Playback pauses when the app becomes inactive.

Runs on macOS 14 or later. Building requires Swift 6 and Xcode 26 or later for the macOS 26 SDK. No dependencies.

```sh
swift run Walldance
```

To build a standalone app:

```sh
zsh scripts/build-app.sh
open dist/Walldance.app
```

Run library tests with `swift test`. Open `Package.swift` in Xcode to develop the app.
