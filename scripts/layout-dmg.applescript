on run arguments
    set mountPath to item 1 of arguments
    tell application "Finder"
        set installerFolder to folder (POSIX file mountPath as alias)
        open installerFolder
        tell container window of installerFolder
            set current view to icon view
            set toolbar visible to false
            set statusbar visible to false
            set pathbar visible to false
            set sidebar width to 0
            set bounds to {160, 160, 840, 588}
        end tell
        tell icon view options of container window of installerFolder
            set arrangement to not arranged
            set icon size to 104
            set text size to 13
            set label position to bottom
            set shows item info to false
            set background picture to file ".background:installer.png" of installerFolder
        end tell
        set position of item "Walldance.app" of installerFolder to {166, 208}
        set position of item "Applications" of installerFolder to {514, 208}
        close container window of installerFolder
        open installerFolder
        delay 2
        update installerFolder without registering applications
        close container window of installerFolder
    end tell
end run
